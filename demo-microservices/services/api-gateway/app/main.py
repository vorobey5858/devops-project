from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
import os
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException

from commerce_demo import build_async_client, install_instrumentation

APP_NAME = os.getenv("APP_NAME", "api-gateway")
ORDERS_BASE_URL = os.getenv("ORDERS_BASE_URL", "http://orders-service:8081")
PAYMENTS_BASE_URL = os.getenv("PAYMENTS_BASE_URL", "http://payments-service:8082")
JsonObject = dict[str, Any]


def _http_client() -> httpx.AsyncClient:
    client = getattr(app.state, "http_client", None)
    if client is None:
        client = build_async_client()
        app.state.http_client = client
    return client


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http_client = build_async_client()
    try:
        yield
    finally:
        await app.state.http_client.aclose()
        app.state.http_client = None


app = FastAPI(title=APP_NAME, version="1.0.0", lifespan=lifespan)
install_instrumentation(app, APP_NAME)


async def get_json(url: str) -> JsonObject:
    response = await _http_client().get(url)
    response.raise_for_status()
    return response.json()


async def post_json(url: str, payload: JsonObject) -> JsonObject:
    response = await _http_client().post(url, json=payload)
    response.raise_for_status()
    return response.json()


def _result_payload(result: JsonObject | Exception) -> JsonObject:
    if isinstance(result, Exception):
        return {"status": "error", "detail": str(result)}
    return result


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": APP_NAME}


@app.get("/ready")
async def ready() -> dict[str, str]:
    return {"status": "ready", "service": APP_NAME}


@app.get("/")
async def root() -> dict[str, str]:
    return {"service": APP_NAME, "status": "ready"}


@app.get("/api/downstream")
async def downstream_status() -> dict[str, object]:
    results = await asyncio.gather(
        get_json(f"{ORDERS_BASE_URL}/health"),
        get_json(f"{PAYMENTS_BASE_URL}/health"),
        return_exceptions=True,
    )
    payload = {
        "service": APP_NAME,
        "dependencies": {
            "orders-service": _result_payload(results[0]),
            "payments-service": _result_payload(results[1]),
        },
    }
    if any(isinstance(result, Exception) for result in results):
        raise HTTPException(status_code=503, detail=payload)
    return payload


@app.get("/api/demo")
async def demo_snapshot() -> dict[str, object]:
    results = await asyncio.gather(
        get_json(f"{ORDERS_BASE_URL}/api/orders/summary"),
        get_json(f"{PAYMENTS_BASE_URL}/api/payments/methods"),
        return_exceptions=True,
    )

    return {
        "service": APP_NAME,
        "orders": _result_payload(results[0]),
        "payments": _result_payload(results[1]),
    }


@app.post("/api/checkout", status_code=201)
async def checkout(payload: JsonObject) -> JsonObject:
    try:
        order = await post_json(f"{ORDERS_BASE_URL}/api/orders", payload)
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    return {
        "service": APP_NAME,
        "checkout_status": "accepted",
        "order": order,
    }
