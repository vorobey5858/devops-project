# Модель SLO и SLI

## Сервисы в зоне действия

- `api-gateway`
- `orders-service`
- `payments-service`

## Основные SLI

| SLI | Смысл | Пример источника метрики |
| --- | --- | --- |
| Доступность | Доступен ли сервис и отвечает ли без 5xx? | Доля успешных HTTP-ответов из Prometheus |
| Доля ошибок | Достаточно ли быстро растёт число ошибок, чтобы запускать rollback? | 5xx-запросы, делённые на общее число запросов |
| p95 latency | Не стал ли сервис медленнее пользовательской цели? | Histogram quantile по длительности запросов |
| Readiness failures | Не перестают ли pod становиться доступными для трафика? | Метрики readiness-состояния Kubernetes |
| Число перезапусков | Не стала ли новая ревизия нестабильной? | Счётчик перезапусков контейнера |

## Целевые steady-state SLO

| Сервис | Доступность | Доля ошибок | p95 latency |
| --- | --- | --- | --- |
| `api-gateway` | 99.9% | меньше 1% | 300 мс |
| `orders-service` | 99.5% | меньше 2% | 400 мс |
| `payments-service` | 99.5% | меньше 1.5% | 450 мс |

## Общий контракт rollback для canary

Rollout-слой использует следующие общие rollback-gates. Они соответствуют `AnalysisTemplate` в `secure-delivery/argo-rollouts/analysis-templates.yaml`:

- доля ошибок больше или равна 5% за 5 минут
- p95 latency больше или равна 500 мс за 5 минут
- больше 3 readiness-сбоев на реплику за 5 минут
- 2 и более неожиданных перезапуска на canary-pod за 10 минут

Эти пороги специально выровнены с текущей стратегией отката из `secure-delivery/docs/rollback-strategy.md`.

## Рекомендуемые окна анализа на шагах canary

| Шаг canary | Основной сигнал | Решение |
| --- | --- | --- |
| 5% трафика | readiness failures, restarts | Быстро прервать релиз, если canary явно нестабилен |
| 25% трафика | error ratio, p95 latency | Откатывать, если деградация уже видна пользователю |
| 50% трафика | error ratio, p95 latency, состояние зависимости | Ставить паузу, если деградируют и stable, и canary: это похоже на общую проблему зависимости |

## Наброски Prometheus-запросов

Эти запросы определяют текущий контракт, на который опирается canary rollback в `demo-stage`.

- Доля ошибок:
  `sum(rate(http_requests_total{service="payments-service",status=~"5.."}[5m])) / sum(rate(http_requests_total{service="payments-service"}[5m]))`
- p95 latency:
  `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service="payments-service"}[5m])) by (le))`
- Число перезапусков:
  `sum(increase(kube_pod_container_status_restarts_total{namespace="demo-stage",pod=~"payments-service-.*"}[10m]))`
- Readiness failures:
  `sum(max_over_time(kube_pod_status_ready{namespace="demo-stage",condition="false",pod=~"payments-service-.*"}[5m]))`

## Ручные точки принятия решения по rollback

- Откатывать сразу, если нарушение касается только canary-ревизии.
- Ставить релиз на паузу, а не откатывать, если за порогом и stable-ревизия: это признак деградации зависимости.
- Эскалировать в DR-оценку только тогда, когда проблема связана с более широким site issue или основной кластер не может восстановиться в пределах RTO 30 минут.
