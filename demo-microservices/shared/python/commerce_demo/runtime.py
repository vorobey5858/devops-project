from __future__ import annotations

import os

import httpx


def _env_int(name: str, default: int) -> int:
    return int(os.getenv(name, str(default)))


def _env_float(name: str, default: float) -> float:
    return float(os.getenv(name, str(default)))


def build_async_client() -> httpx.AsyncClient:
    shared_timeout = _env_float("HTTP_TIMEOUT_SECONDS", 5.0)
    timeout = httpx.Timeout(
        connect=_env_float("HTTP_CONNECT_TIMEOUT_SECONDS", 1.0),
        read=_env_float("HTTP_READ_TIMEOUT_SECONDS", shared_timeout),
        write=_env_float("HTTP_WRITE_TIMEOUT_SECONDS", shared_timeout),
        pool=_env_float("HTTP_POOL_TIMEOUT_SECONDS", 1.0),
    )
    limits = httpx.Limits(
        max_connections=_env_int("HTTP_MAX_CONNECTIONS", 1024),
        max_keepalive_connections=_env_int("HTTP_MAX_KEEPALIVE_CONNECTIONS", 256),
        keepalive_expiry=_env_float("HTTP_KEEPALIVE_EXPIRY_SECONDS", 30.0),
    )
    return httpx.AsyncClient(
        timeout=timeout,
        limits=limits,
        headers={"User-Agent": "commerce-demo-platform/1.0"},
    )
