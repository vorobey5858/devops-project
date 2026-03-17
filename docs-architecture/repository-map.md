# Карта репозитория

## Корень репозитория

- `README.md` - общий обзор проекта и демо-потока
- `bootstrap/**` - артефакты локального bootstrap для foundation и наблюдаемости
- `scripts/bootstrap/**` - скрипты автоматизации для локального подъёма и проверки
- `scripts/demo/**` - локальная сборка образов и smoke-проверки
- `scripts/security/**` - локальные вспомогательные security-скрипты
- `scripts/validation/**` - скрипты проверки контрактов

## Общая архитектурная документация

- `docs-architecture/unified-architecture.md`
- `docs-architecture/repository-map.md`
- `docs-architecture/decision-log.md`
- `docs-architecture/demo-checklist.md`

## Платформенный слой

- `platform-core/README.md`
- `platform-core/docs/architecture.md`
- `platform-core/docs/onboarding.md`
- `platform-core/docs/observability-baseline.md`
- `platform-core/kubernetes/argocd/project-platform.yaml`
- `platform-core/kubernetes/namespaces/team-template.yaml`
- `platform-core/kubernetes/namespaces/demo-environments.yaml`
- `platform-core/kubernetes/observability/**`
- `platform-core/templates/service-template/**`

## Слой надёжности

- `reliability-lab/README.md`
- `reliability-lab/docs/dr-plan.md`
- `reliability-lab/docs/slo-sli.md`
- `reliability-lab/docs/runbooks.md`
- `reliability-lab/docs/postmortem-example.md`
- `reliability-lab/backup/velero-values.yaml`
- `reliability-lab/chaos/pod-delete.yaml`
- `reliability-lab/chaos/network-latency.yaml`
- `reliability-lab/chaos/node-failure.md`

## Слой безопасной поставки

- `secure-delivery/README.md`
- `secure-delivery/docs/supply-chain.md`
- `secure-delivery/docs/threat-model.md`
- `secure-delivery/docs/rollback-strategy.md`
- `secure-delivery/ci/github-actions-secure-template.yml`
- `secure-delivery/policies/kyverno/require-signed-images.yaml`
- `secure-delivery/policies/kyverno/disallow-latest-tag.yaml`
- `secure-delivery/argo-rollouts/demo-canary.yaml`
- `secure-delivery/signing/cosign.pub`

## Демо-сервисы

- `demo-microservices/README.md`
- `demo-microservices/shared/python/**`
- `demo-microservices/services/*/app/**`
- `demo-microservices/tests/**`
