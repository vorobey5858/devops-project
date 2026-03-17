# Чек-лист демо

## Перед запуском

- установлен `k3s`
- установлен `kubectl`
- установлен `helm`
- установлен `Docker` или другой OCI builder
- у репозитория настроен `origin`, доступный ArgoCD

## Локальный bootstrap

1. Запустить:
   `sh ./scripts/bootstrap/install-k3s.sh`
2. Затем запустить:
   `.\scripts\bootstrap\bootstrap-local.ps1`
3. Убедиться, что проходит:
   `.\scripts\bootstrap\validate-local.ps1`

## Сборка образов

1. Собрать `stage` образы:
   `sh ./scripts/demo/build-images.sh stage`
2. Убедиться, что импорт в `k3s` завершился без ошибок.

## Smoke-путь

1. Запустить:
   `.\scripts\demo\smoke-test.ps1 -Namespace demo-stage`
2. Проверить, что:
   - `api-gateway` отвечает по `/health`
   - `/api/demo` показывает downstream snapshot
   - `/api/checkout` успешно создает заказ

## Постепенное развёртывание

1. Проверить rollout resources:
   `kubectl -n demo-stage get rollout`
2. Проверить наличие analysis templates:
   `kubectl -n demo-stage get analysistemplate`
3. Убедиться, что stage workloads отрендерены как `Rollout`, а не `Deployment`.

## Сценарий надёжности

1. Проверить runbooks и SLO:
   - `reliability-lab/docs/runbooks.md`
   - `reliability-lab/docs/slo-sli.md`
2. При необходимости подготовить chaos запуск:
   - `reliability-lab/chaos/pod-delete.yaml`
   - `reliability-lab/chaos/network-latency.yaml`
   - `reliability-lab/chaos/node-failure.md`

## Сценарий безопасности

1. Проверить reusable workflow:
   `.github/workflows/secure-ci-reusable.yml`
2. Проверить policies:
   - `secure-delivery/policies/kyverno/disallow-latest-tag.yaml`
   - `secure-delivery/policies/kyverno/require-resources.yaml`
   - `secure-delivery/policies/kyverno/require-security-context.yaml`
3. Если нужен registry-based signature enforcement, отдельно включить:
   `.\scripts\bootstrap\bootstrap-local.ps1 -EnableSignaturePolicy`
