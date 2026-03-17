# Единая архитектура

## Цель

Собрать платформу, которую можно поднять локально или на небольшом VPS и при этом показать на ней полный путь сервиса: шаблон, безопасную сборку, GitOps-развёртывание, canary, откат и восстановление.

## Основной сценарий

1. Платформа даёт сервису единый шаблон.
2. Изменение кода запускает CI.
3. CI собирает образ, проверяет его, формирует SBOM и подписывает digest.
4. ArgoCD синхронизирует изменения в кластер.
5. В `stage` сервис катится через `Argo Rollouts`.
6. Prometheus отдаёт метрики для анализа.
7. При деградации включается rollback, а при серьёзном сбое команда переходит к runbook-ам и recovery-процедурам.

## Слои системы

### Кластерная основа

- `k3s`
- `ingress-nginx`
- `cert-manager`
- `ArgoCD`
- `Vault`
- `External Secrets Operator`

### Общие платформенные сервисы

- `kube-prometheus-stack`
- `Loki`
- `OpenTelemetry Collector`
- `Kyverno`
- namespace-модель окружений
- общий Helm-шаблон сервиса

### Компоненты состояния и восстановления

- `CloudNativePG`
- `Redis Sentinel`
- `Velero`
- chaos-сценарии
- runbook-и

### Контроли поставки

- шаблоны GitHub Actions
- `Gitleaks`
- `Semgrep`
- `Trivy`
- `Syft`
- `Cosign`
- `Argo Rollouts`

### Прикладная нагрузка

- `api-gateway`
- `orders-service`
- `payments-service`

## Интеграционные контракты

### Контракт сервиса

Каждый сервис, который входит на платформу, должен иметь:

- неизменяемый тег образа;
- `securityContext`;
- probes;
- resource limits и requests;
- метрики приложения;
- совместимость с `ServiceMonitor`;
- переключатель `rollout.enabled`.

### Контракт метрик

Canary, SLO и recovery-сценарии используют общий набор сигналов:

- доля ошибок;
- latency;
- рестарты pod;
- сбои readiness.

### Контракт восстановления

Runbook-и и DR-процедуры опираются на:

- состояние приложений в ArgoCD;
- сигналы Prometheus;
- данные о backup;
- общую namespace-модель из `platform-core`.

## Следующие архитектурные шаги

1. Подготовить multi-node или dual-site стенд для DR-прогона.
2. Расширить demo-нагрузку stateful-компонентами.
3. Выравнять дашборды, alert rules и rollout-анализ по одному набору идентификаторов.
