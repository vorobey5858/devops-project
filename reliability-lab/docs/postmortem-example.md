# Пример postmortem

## Инцидент

Во время canary-релиза `payments-service` рост latency скрыл деградацию PostgreSQL replica lag, после чего часть запросов начала получать timeout.

## Воздействие

- до 18% запросов к `payments-service` завершались ошибкой
- автоматический rollback сработал корректно
- восстановление заняло 14 минут

## Корневая причина

- нагрузочный профиль нового релиза увеличил число синхронных обращений
- alert по replica lag был слишком мягким
- release checklist не включал DB pressure test

## Корректирующие действия

- добавить DB saturation check в pre-release checklist
- ужесточить alert threshold по replica lag
- расширить rollback-analysis дополнительной метрикой database wait time
