# Безопасная цепочка поставки

## Цель

Базовый контур безопасной поставки реализует готовую для GitHub цепочку `scan -> build -> image scan -> SBOM -> push -> sign -> GitOps handoff`.
Основной переиспользуемый сценарий находится в `.github/workflows/secure-ci-reusable.yml`.
Копируемый пример для сервисных репозиториев лежит в `secure-delivery/ci/github-actions-secure-template.yml`.

## Этапы конвейера

1. `secret-scan`
   - проверяет всю историю Git через Gitleaks
   - публикует SARIF-отчёт и сохраняет его как артефакт
2. `sast`
   - запускает Semgrep с ruleset `auto`
   - сохраняет JSON-отчёт как артефакт
3. `build-scan-sign`
   - собирает образ локально на runner и не публикует его до завершения защитных проверок
   - запускает Trivy по локально собранному образу
   - генерирует SPDX JSON SBOM через Syft
   - публикует в целевой реестр только образ, прошедший проверки
   - подписывает digest и прикрепляет attestations для SBOM через Cosign
   - загружает все отчёты плюс `release-metadata.json`

## Хранение артефактов и отчётов

- `gitleaks-report`
  - SARIF-артефакт с результатами поиска секретов
- `semgrep-report`
  - JSON-артефакт с результатами SAST
- `supply-chain-reports`
  - `trivy.sarif`
  - `sbom.spdx.json`
  - `release-metadata.json`
- публикация SARIF
  - Gitleaks и Trivy отправляют SARIF в GitHub Code Scanning

## Обязательные секреты и права

- `COSIGN_PRIVATE_KEY`
  - приватный ключ для подписи парой ключей
- `COSIGN_PASSWORD`
  - опциональный пароль для зашифрованного ключа
- `GITHUB_TOKEN`
  - достаточно для публикации в GHCR при включённых правах на пакеты
- права вызывающего сценария
  - `contents: read`
  - `packages: write`
  - `security-events: write`

## Явные допущения по совместимости

- Текущий контракт `platform-core/templates/service-template` остаётся источником истины для `resources`, контейнерного `securityContext`, probes, labels и annotations для метрик.
- Встроенный рендеринг `Rollout` уже находится в `platform-core`, а `secure-delivery/argo-rollouts/demo-canary.yaml` остаётся опорным манифестом для ревью и ручной отладки.
- Мутация GitOps-окружений пока не зафиксирована. Поэтому конвейер публикует подписанный `release-metadata.json` как контракт-передачу для будущего шага обновления Argo CD.
- Метрики приложений публикуются в Prometheus с label `service` и меткой namespace, совместимыми с `analysis-templates.yaml`.

## Почему выбрана локальная схема подписи

Базовый сценарий использует подпись парой ключей вместо keyless OIDC, чтобы его можно было воспроизвести в локальном или VM-only окружении без зависимости от внешней облачной identity. В локальном bootstrap политика `require-signed-images` не включается автоматически: она рассчитана на доставку образов через реестр, а не на сценарий `k3s ctr images import`.
