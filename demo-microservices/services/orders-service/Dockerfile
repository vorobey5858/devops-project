FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app/shared/python
ENV APP_PORT=8081

WORKDIR /app

COPY demo-microservices/services/orders-service/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY demo-microservices/shared /app/shared
COPY demo-microservices/services/orders-service/app /app/app

EXPOSE 8081

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${APP_PORT} --workers ${UVICORN_WORKERS:-1} --timeout-keep-alive ${UVICORN_KEEPALIVE_TIMEOUT:-15} --no-access-log"]
