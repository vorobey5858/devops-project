from __future__ import annotations

import asyncio
import importlib.util
import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "demo-microservices" / "shared" / "python"

if str(SHARED) not in sys.path:
    sys.path.insert(0, str(SHARED))


def load_module(module_name: str, relative_path: str):
    path = ROOT / relative_path
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_payments_service_charge_and_health():
    module = load_module("payments_service_main", "demo-microservices/services/payments-service/app/main.py")
    client = TestClient(module.app)

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["service"] == "payments-service"

    response = client.post(
        "/api/payments/charge",
        json={"order_id": "ord-100", "amount": 42.5, "currency": "USD"},
    )
    assert response.status_code == 201
    assert response.json()["payment_id"] == "pay-ord-100"


def test_orders_service_creates_order_with_stubbed_payment(monkeypatch):
    module = load_module("orders_service_main", "demo-microservices/services/orders-service/app/main.py")
    asyncio.run(module.ORDER_STORE.clear())

    async def fake_charge(order_id: str, amount: float, currency: str):
        return {
            "payment_id": f"pay-{order_id}",
            "order_id": order_id,
            "amount": amount,
            "currency": currency,
            "provider_mode": "stub",
            "status": "authorized",
        }

    monkeypatch.setattr(module, "charge_payment", fake_charge)

    client = TestClient(module.app)
    response = client.post(
        "/api/orders",
        json={
            "customer_id": "cust-1",
            "items": [{"sku": "sku-1", "quantity": 2, "unit_price": 19.5}],
            "currency": "USD",
        },
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["order_id"].startswith("ord-")
    assert payload["status"] == "payment_authorized"
    assert payload["total_amount"] == 39.0

    summary = client.get("/api/orders/summary")
    assert summary.status_code == 200
    assert summary.json()["authorized_orders"] >= 1


def test_api_gateway_checkout_and_snapshot(monkeypatch):
    module = load_module("api_gateway_main", "demo-microservices/services/api-gateway/app/main.py")

    async def fake_get_json(url: str):
        if url.endswith("/api/orders/summary"):
            return {"service": "orders-service", "total_orders": 1}
        if url.endswith("/api/payments/methods"):
            return {"service": "payments-service", "methods": ["card"]}
        if url.endswith("/health"):
            return {"status": "ok"}
        raise AssertionError(f"Unexpected URL: {url}")

    async def fake_post_json(url: str, payload):
        return {
            "order_id": "ord-900",
            "status": "payment_authorized",
            "total_amount": 12.0,
            "echo": payload,
        }

    monkeypatch.setattr(module, "get_json", fake_get_json)
    monkeypatch.setattr(module, "post_json", fake_post_json)

    client = TestClient(module.app)

    snapshot = client.get("/api/demo")
    assert snapshot.status_code == 200
    assert snapshot.json()["orders"]["total_orders"] == 1

    checkout = client.post(
        "/api/checkout",
        json={
            "customer_id": "cust-9",
            "items": [{"sku": "sku-1", "quantity": 1, "unit_price": 12.0}],
        },
    )
    assert checkout.status_code == 201
    assert checkout.json()["order"]["status"] == "payment_authorized"
