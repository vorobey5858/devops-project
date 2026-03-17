from __future__ import annotations

import asyncio
from collections import deque
from copy import deepcopy
from dataclasses import dataclass
from typing import Any


@dataclass(slots=True)
class OrderCounters:
    total_orders: int = 0
    authorized_orders: int = 0
    queued_orders: int = 0
    pending_orders: int = 0

    def observe(self, status: str) -> None:
        self.total_orders += 1
        if status == "payment_authorized":
            self.authorized_orders += 1
        elif status == "payment_queued":
            self.queued_orders += 1
        else:
            self.pending_orders += 1

    def as_dict(self, service_name: str) -> dict[str, object]:
        return {
            "service": service_name,
            "total_orders": self.total_orders,
            "authorized_orders": self.authorized_orders,
            "queued_orders": self.queued_orders,
            "pending_orders": self.pending_orders,
        }


class RecentOrderStore:
    def __init__(self, max_records: int):
        self._max_records = max_records
        self._orders: dict[str, dict[str, Any]] = {}
        self._order_ids: deque[str] = deque()
        self._counters = OrderCounters()
        self._lock = asyncio.Lock()

    async def save(self, order: dict[str, Any]) -> None:
        async with self._lock:
            order_id = order["order_id"]
            self._orders[order_id] = deepcopy(order)
            self._order_ids.append(order_id)
            self._counters.observe(order["status"])

            while len(self._order_ids) > self._max_records:
                oldest_order_id = self._order_ids.popleft()
                self._orders.pop(oldest_order_id, None)

    async def get(self, order_id: str) -> dict[str, Any] | None:
        async with self._lock:
            order = self._orders.get(order_id)
            return deepcopy(order) if order is not None else None

    async def list_recent(self, limit: int) -> list[dict[str, Any]]:
        async with self._lock:
            recent_order_ids = list(self._order_ids)[-limit:]
            return [deepcopy(self._orders[order_id]) for order_id in recent_order_ids if order_id in self._orders]

    async def summary(self, service_name: str) -> dict[str, object]:
        async with self._lock:
            return self._counters.as_dict(service_name)

    async def clear(self) -> None:
        async with self._lock:
            self._orders.clear()
            self._order_ids.clear()
            self._counters = OrderCounters()
