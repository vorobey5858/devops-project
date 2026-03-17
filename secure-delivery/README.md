# Безопасная поставка

Этот каталог отвечает за то, чтобы релиз был не только автоматическим, но и проверяемым. Здесь собраны CI-проверки, admission-политики и rollout-механика для `demo-stage`.

## Что здесь лежит

- reusable workflow для secure CI в `ci/github-actions-secure-template.yml`
- документы по цепочке поставки, модели угроз и откату в `docs/*`
- Kyverno-политики в `policies/kyverno/*`
- rollout и analysis templates в `argo-rollouts/*`
- публичный ключ подписи в `signing/cosign.pub`

## Как работает этот слой

1. CI собирает образ и прогоняет secret scan, SAST и image scan.
2. После успешных проверок формируется SBOM и подписывается digest.
3. В кластере admission-политики не дают обойти базовые требования к образу и pod.
4. В `stage` релиз идёт через `Argo Rollouts` и откатывается по метрикам.

## Локальный сценарий

- В bootstrap по умолчанию включаются `disallow-latest-tag`, `require-resources` и `require-security-context`.
- Политика `require-signed-images` включается отдельно, потому что локальный стенд использует импорт образов в `k3s`, а не полноценный registry-путь.
- Вместо прямой мутации GitOps-манифестов этот слой готовит `release-metadata.json`, чтобы не смешивать сборку и GitOps-состояние.

## Границы слоя

- `platform-core/templates/service-template` считается входным контрактом и здесь не меняется;
- реальные секреты для реестра и подписи должны жить вне репозитория;
- этот каталог не подменяет операционные runbook-и и recovery-процедуры.
