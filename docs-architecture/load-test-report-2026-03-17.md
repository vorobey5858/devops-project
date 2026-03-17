# Отчет по нагрузочному тестированию от 2026-03-17

## Контекст

- Площадка: `95.163.226.124`
- Кластер: `k3s`, namespace теста `demo-stage`
- Профиль узла: `8 vCPU`, `15 GiB RAM`
- Точка входа пользовательского сценария: `https://127.0.0.1/api/checkout` с `Host: api-gateway.stage.platform.local`
- Внутренние точки проверки:
  - `http://10.43.79.250:8081/api/orders`
  - `http://10.43.27.5:8082/api/payments/charge`

## Сценарии

### 1. Checkout через ingress

- `checkout-64`: `wrk -t4 -c64 -d30s`
- `checkout-256`: `wrk -t8 -c256 -d60s`
- `checkout-512`: `wrk -t12 -c512 -d90s`

### 2. Прямой тест payments-service

- `payments-256`: `wrk -t8 -c256 -d45s`
- `payments-512`: `wrk -t12 -c512 -d60s`

### 3. Прямой тест orders-service

- `orders-256`: `wrk -t8 -c256 -d45s`

## Результаты wrk

### Checkout через ingress

| Сценарий | RPS | Avg latency | p99 | Ошибки |
| --- | ---: | ---: | ---: | ---: |
| `checkout-64` | `205.69` | `308.96 ms` | `644.56 ms` | `0` |
| `checkout-256` | `203.33` | `1.25 s` | `2.81 s` | `0` |
| `checkout-512` | `194.42` | `2.54 s` | `4.40 s` | `8475` non-2xx/3xx |

### Прямой payments-service

| Сценарий | RPS | Avg latency | p99 | Ошибки |
| --- | ---: | ---: | ---: | ---: |
| `payments-256` | `3790.68` | `67.43 ms` | `109.22 ms` | `0` |
| `payments-512` | `4240.67` | `118.62 ms` | `188.36 ms` | `0` |

### Прямой orders-service

| Сценарий | RPS | Avg latency | p99 | Ошибки |
| --- | ---: | ---: | ---: | ---: |
| `orders-256` | `239.17` | `1.06 s` | `1.69 s` | `0` |

## Метрики Prometheus

### Пиковые значения за окно теста

- Пик `api-gateway` по входящему трафику: `212.07 RPS`
- Пик `orders-service`: `217.40 RPS`
- Пик `payments-service`: `4178.87 RPS`
- Максимальный `p95` у `api-gateway`: `4806.54 ms`
- Максимальный `p95` у `orders-service`: `1911.33 ms`
- Максимальный `p95` у `payments-service`: `185.28 ms`
- Минимальная доля успешных ответов у `api-gateway`: `32.88%`
- 5xx у `api-gateway` за окно теста: около `8243` ответов `503`

### Память

- Пик памяти `orders-service` pod:
  - `268.27 MiB`
  - `185.62 MiB`
  - `156.09 MiB`
- Пик памяти `api-gateway` pod:
  - до `304.05 MiB`
- Пик памяти `payments-service` pod:
  - около `47 MiB`

## Состояние подов после теста

- Все `Rollout` в `demo-stage` остались `Healthy`
- Все pod вернулись в `Running/Ready`
- Зафиксирован `1` restart у `orders-service-585f84d9f8-4m9cp`

## Причина деградации

### Что именно произошло

- Под жесткой нагрузкой узкое место оказалось не в ingress и не в `payments-service`, а в `orders-service`
- `api-gateway` начал возвращать `503 Service Unavailable`
- Один pod `orders-service` был перезапущен kubelet

### Подтверждение

- `payments-service` выдержал `4k+ RPS` без ошибок
- прямой тест `orders-service` показал потолок около `239 RPS` уже с секундными задержками
- у проблемного pod `orders-service`:
  - `Last State: Terminated`
  - `Exit Code: 137`
  - события kubelet: `Liveness probe failed` и `Readiness probe failed`
  - причина рестарта: kubelet убил контейнер после провала liveness probe, а не из-за OOM

## Главные выводы

1. Текущий безопасный потолок пользовательского checkout-пути находится примерно в диапазоне `180-200 RPS`
2. Увеличение concurrency выше этого уровня почти не растит throughput, а переводит систему в рост latency и 503
3. Главный bottleneck сейчас `orders-service`
4. Проблема проявляется как насыщение event loop и провал probe под высокой нагрузкой
5. `payments-service` имеет большой запас и сейчас не ограничивает checkout-путь

## Что исправлять в первую очередь

1. Ослабить probe-чувствительность для `orders-service`
   - увеличить `timeoutSeconds`
   - увеличить `failureThreshold`
   - не убивать pod так агрессивно на коротких пиках
2. Увеличить горизонтальное масштабирование `orders-service`
   - поднять реплики
   - добавить HPA по CPU/latency/RPS
3. Снизить стоимость одного запроса в `orders-service`
   - ограничить синхронную глубину цепочки
   - вынести часть работы в очередь или async processing
4. Добавить backpressure на входе
   - rate limiting
   - queue depth guards
   - circuit breaker между `api-gateway` и `orders-service`
5. Пересмотреть бизнес-модель хранения заказов
   - сейчас `ORDER_STORE` держится в памяти процесса и растет с каждым запросом
   - под длительной нагрузкой это приведет к росту memory footprint и ухудшению latency

## Рекомендуемый следующий этап

После правок имеет смысл повторить тот же профиль:

- `checkout`: `64 -> 256 -> 512`
- `orders-service`: `256`
- acceptance-критерий:
  - без рестартов
  - без 5xx на `checkout-256`
  - `p95` checkout ниже `1.5 s` на `checkout-256`
  - заметно лучший запас по latency на прямом `orders-service`
