# Локальный bootstrap

Этот каталог нужен для первого подъёма стенда. Он не заменяет GitOps, а готовит кластер и базовые компоненты так, чтобы дальше можно было синхронизировать приложения, собрать образы и пройти smoke-путь.

## Что входит в bootstrap

- `k3s/config.yaml` с минимальной конфигурацией `k3s`
- `helm-values/*.yaml` для foundation- и observability-компонентов
- `scripts/bootstrap/install-k3s.sh` для установки `k3s` на Linux или VPS
- `scripts/bootstrap/bootstrap-local.ps1` как основной сценарий установки
- `scripts/bootstrap/validate-local.ps1` для быстрой проверки стенда

## Что нужно заранее

- Linux-хост или VPS под `k3s`
- `kubectl`
- `helm`
- локальный OCI-сборщик вроде `Docker`, если нужно собирать свои образы
- опубликованный remote-репозиторий, доступный для ArgoCD

## Что ставится автоматически

- `ingress-nginx`
- `cert-manager`
- `ArgoCD`
- `Kyverno`
- `Argo Rollouts`
- `kube-prometheus-stack`
- `Loki`
- demo namespace для `dev`, `preview`, `stage`
- `AppProject` и app-of-apps для demo-сервисов
- стартовые policy и analysis templates
- ingress и стартовый дашборд для Grafana и Prometheus

## Базовый сценарий

```bash
sh ./scripts/bootstrap/install-k3s.sh
```

```powershell
.\scripts\bootstrap\bootstrap-local.ps1
sh ./scripts/demo/build-images.sh stage
.\scripts\demo\smoke-test.ps1 -Namespace demo-stage
```

## Полезные флаги

```powershell
.\scripts\bootstrap\bootstrap-local.ps1 -SkipObservability
.\scripts\bootstrap\bootstrap-local.ps1 -SkipGitOps
.\scripts\bootstrap\bootstrap-local.ps1 -EnableSignaturePolicy
.\scripts\bootstrap\validate-local.ps1
```

## Ограничения

- `require-signed-images` не включается по умолчанию в локальном сценарии
- `CloudNativePG`, `Velero`, `Vault` и `External Secrets` остаются отдельным расширением
- если текущая ветка ещё не опубликована в remote, GitOps-часть лучше запускать с `-SkipGitOps`
