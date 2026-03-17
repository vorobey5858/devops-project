# Процедура отказа узла

## Цель

Проверить, что `demo-stage` продолжает обслуживать трафик после потери одного worker-узла и что stage-rollout остаются в пределах rollback-порогов.

## Предварительные условия

- `api-gateway`, `orders-service` и `payments-service` работают как минимум с двумя готовыми репликами
- `kubectl get nodes` показывает запас ёмкости вне узла, выбранного для эксперимента
- текущие error ratio и p95 latency находятся в пределах SLO из `docs/slo-sli.md`

## Порядок действий

1. Выбрать один worker-узел, который не является control-plane:
   `kubectl get nodes -o wide`
2. Перевести узел в cordon:
   `kubectl cordon <node-name>`
3. Выполнить drain, сохранив daemonset:
   `kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data`
4. Наблюдать за rescheduling pod в `demo-stage`:
   `kubectl -n demo-stage get pods -w`
5. Во время и после drain отслеживать:
   - error ratio
   - p95 latency
   - число restarts
   - pending pod
6. После сбора артефактов вернуть узел в работу:
   `kubectl uncordon <node-name>`

## Ожидаемый результат

- Допустим максимум один короткий всплеск ошибок в момент перераспределения endpoint.
- Сервисы `demo-stage` остаются ниже rollback-порогов либо восстанавливаются до следующего analysis-step.
- DR-действия не требуются.
