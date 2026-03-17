from __future__ import annotations

import os
import random
import asyncio
from typing import Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from commerce_demo import install_instrumentation

APP_NAME = os.getenv("APP_NAME", "payments-service")
PROVIDER_MODE = os.getenv("PROVIDER_MODE", os.getenv("PAYMENT_PROVIDER", "stub"))
FAILURE_RATE = float(os.getenv("PAYMENTS_FAILURE_RATE", "0"))
BASE_LATENCY_MS = int(os.getenv("PAYMENTS_BASE_LATENCY_MS", "40"))

app = FastAPI(title=APP_NAME, version="1.0.0")
install_instrumentation(app, APP_NAME)


class ChargeRequest(BaseModel):
    order_id: str = Field(..., min_length=3)
    amount: float = Field(..., gt=0)
    currency: str = Field(default="USD", min_length=3, max_length=3)


class ChargeResponse(BaseModel):
    payment_id: str
    order_id: str
    amount: float
    currency: str
    provider_mode: str
    status: Literal["authorized", "queued"]


ChargeRequest.model_rebuild()
ChargeResponse.model_rebuild()


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": APP_NAME}


@app.get("/ready")
async def ready() -> dict[str, str]:
    return {"status": "ready", "service": APP_NAME}


@app.get("/")
async def root() -> dict[str, str]:
    return {"service": APP_NAME, "provider_mode": PROVIDER_MODE}


@app.get("/api/payments/methods")
async def payment_methods() -> dict[str, object]:
    return {
        "service": APP_NAME,
        "provider_mode": PROVIDER_MODE,
        "methods": ["card", "invoice", "wallet"],
    }


@app.post("/api/payments/charge", status_code=201, response_model=ChargeResponse)
async def charge(request: ChargeRequest) -> ChargeResponse:
    if FAILURE_RATE > 0 and random.random() < FAILURE_RATE:
        raise HTTPException(status_code=503, detail="Payment provider is temporarily unavailable.")

    if BASE_LATENCY_MS > 0:
        await asyncio.sleep(BASE_LATENCY_MS / 1000)

    status: Literal["authorized", "queued"] = "queued" if PROVIDER_MODE == "dry-run" else "authorized"
    return ChargeResponse(
        payment_id=f"pay-{request.order_id}",
        order_id=request.order_id,
        amount=request.amount,
        currency=request.currency.upper(),
        provider_mode=PROVIDER_MODE,
        status=status,
    )
