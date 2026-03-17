from __future__ import annotations

from contextlib import asynccontextmanager
import os
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

import httpx
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from commerce_demo import RecentOrderStore, build_async_client, install_instrumentation

APP_NAME = os.getenv("APP_NAME", "orders-service")
PAYMENTS_BASE_URL = os.getenv("PAYMENTS_BASE_URL", "http://payments-service:8082")
ORDER_HISTORY_LIMIT = int(os.getenv("ORDER_HISTORY_LIMIT", "5000"))
JsonObject = dict[str, Any]


class OrderItem(BaseModel):
    sku: str = Field(..., min_length=2)
    quantity: int = Field(default=1, ge=1)
    unit_price: float = Field(..., gt=0)


class OrderRequest(BaseModel):
    customer_id: str = Field(..., min_length=3)
    items: list[OrderItem] = Field(..., min_length=1)
    currency: str = Field(default="USD", min_length=3, max_length=3)
    capture_payment: bool = True


OrderItem.model_rebuild()
OrderRequest.model_rebuild()


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.payments_client = build_async_client()
    try:
        yield
    finally:
        await app.state.payments_client.aclose()
        app.state.payments_client = None


app = FastAPI(title=APP_NAME, version="1.0.0", lifespan=lifespan)
install_instrumentation(app, APP_NAME)
ORDER_STORE = RecentOrderStore(max_records=ORDER_HISTORY_LIMIT)


def _calculate_total(items: list[OrderItem]) -> float:
    return round(sum(item.quantity * item.unit_price for item in items), 2)


def _payments_client() -> httpx.AsyncClient:
    client = getattr(app.state, "payments_client", None)
    if client is None:
        client = build_async_client()
        app.state.payments_client = client
    return client


async def charge_payment(order_id: str, amount: float, currency: str) -> JsonObject:
    response = await _payments_client().post(
        f"{PAYMENTS_BASE_URL}/api/payments/charge",
        json={"order_id": order_id, "amount": amount, "currency": currency},
    )
    response.raise_for_status()
    return response.json()


def _mark_payment_pending(order_record: JsonObject, message: str, status_code: int | None = None) -> None:
    order_record["status"] = "payment_pending"
    payment_error: JsonObject = {"message": message}
    if status_code is not None:
        payment_error["status_code"] = status_code
    order_record["payment_error"] = payment_error


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": APP_NAME}


@app.get("/ready")
async def ready() -> dict[str, str]:
    return {"status": "ready", "service": APP_NAME}


@app.get("/")
async def root() -> dict[str, str]:
    return {"service": APP_NAME, "payments_base_url": PAYMENTS_BASE_URL}


@app.get("/api/orders")
async def list_orders(limit: int = Query(default=100, ge=1, le=500)) -> dict[str, object]:
    return {
        "service": APP_NAME,
        "orders": await ORDER_STORE.list_recent(limit=limit),
    }


@app.get("/api/orders/summary")
async def order_summary() -> dict[str, object]:
    return await ORDER_STORE.summary(service_name=APP_NAME)


@app.get("/api/orders/{order_id}")
async def get_order(order_id: str) -> JsonObject:
    order = await ORDER_STORE.get(order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found.")
    return order


@app.post("/api/orders", status_code=201)
async def create_order(request: OrderRequest) -> JsonObject:
    order_id = f"ord-{uuid4().hex[:12]}"
    total_amount = _calculate_total(request.items)
    currency = request.currency.upper()

    order_record: JsonObject = {
        "order_id": order_id,
        "customer_id": request.customer_id,
        "currency": currency,
        "total_amount": total_amount,
        "status": "pending",
        "payment": None,
        "created_at": datetime.now(tz=timezone.utc).isoformat(),
        "items": [item.model_dump() for item in request.items],
    }

    if request.capture_payment:
        try:
            payment = await charge_payment(order_id, total_amount, currency)
            payment_status = payment.get("status", "authorized")
            order_record["payment"] = payment
            order_record["status"] = "payment_queued" if payment_status == "queued" else "payment_authorized"
        except httpx.HTTPStatusError as exc:
            _mark_payment_pending(order_record, exc.response.text, status_code=exc.response.status_code)
        except httpx.HTTPError as exc:
            _mark_payment_pending(order_record, str(exc))

    await ORDER_STORE.save(order_record)

    return order_record
