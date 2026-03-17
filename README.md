# Учебная DevOps-платформа

Этот репозиторий показывает полный путь сервиса в Kubernetes: от шаблона и сборки до GitOps-развёртывания, canary, отката по метрикам и базового восстановления после сбоя. Здесь один и тот же demo-workload проходит через платформенный, security и reliability-слои, поэтому проект удобно показывать как цельную систему, а не как набор разрозненных манифестов.

## Что внутри

- `platform-core` задаёт общий способ подключения сервиса к платформе
- `demo-microservices` содержит три рабочих сервиса: `api-gateway`, `orders-service`, `payments-service`
- `secure-delivery` описывает безопасную сборку, политики допуска и rollout в `stage`
- `reliability-lab` фиксирует SLO, chaos-сценарии, backup/restore и DR-процедуры
- `docs-architecture` собирает архитектуру, журнал решений, карту репозитория и сценарии показа

## Что уже реализовано

- bootstrap под `k3s` для локального стенда или недорогого VPS
- единый Helm-шаблон сервиса с `Deployment` или `Rollout`, `Service`, `Ingress`, `ServiceMonitor` и базовыми ограничениями
- GitOps-путь через ArgoCD для `demo-dev`, `demo-preview` и `demo-stage`
- secure CI со scan-проверками, SBOM и подписью образа
- canary и rollback по метрикам Prometheus
- базовая наблюдаемость через Prometheus, Grafana и Loki
- chaos, backup/restore, DR и runbook-и для демонстрации устойчивости

## Быстрый старт

```powershell
sh ./scripts/bootstrap/install-k3s.sh
.\scripts\bootstrap\bootstrap-local.ps1
sh ./scripts/demo/build-images.sh stage
.\scripts\demo\smoke-test.ps1 -Namespace demo-stage
```

Нужны `k3s`, `kubectl`, `helm` и локальный OCI-сборщик вроде `Docker`.

## Как проходит демо

1. Сервис живёт в `demo-microservices/services/*` и использует общий шаблон из `platform-core`.
2. CI собирает образ, прогоняет проверки, формирует SBOM и подписывает digest.
3. ArgoCD синхронизирует изменения в `demo-dev`, `demo-preview` и `demo-stage`.
4. В `demo-stage` сервис выкатывается через `Argo Rollouts`.
5. Prometheus отдаёт метрики для анализа, а при деградации срабатывает rollback.
6. Те же сигналы используются в chaos-сценариях, runbook-ах и DR-проверках.

## Куда смотреть дальше

- [`bootstrap/README.md`](/c:/Users/struz/OneDrive/Документы/devops/bootstrap/README.md)
- [`docs-architecture/unified-architecture.md`](/c:/Users/struz/OneDrive/Документы/devops/docs-architecture/unified-architecture.md)
- [`docs-architecture/repository-map.md`](/c:/Users/struz/OneDrive/Документы/devops/docs-architecture/repository-map.md)
- [`docs-architecture/demo-checklist.md`](/c:/Users/struz/OneDrive/Документы/devops/docs-architecture/demo-checklist.md)
- [`docs-architecture/decision-log.md`](/c:/Users/struz/OneDrive/Документы/devops/docs-architecture/decision-log.md)
- [`platform-core/docs/architecture.md`](/c:/Users/struz/OneDrive/Документы/devops/platform-core/docs/architecture.md)
- [`secure-delivery/docs/supply-chain.md`](/c:/Users/struz/OneDrive/Документы/devops/secure-delivery/docs/supply-chain.md)
- [`reliability-lab/docs/dr-plan.md`](/c:/Users/struz/OneDrive/Документы/devops/reliability-lab/docs/dr-plan.md)
