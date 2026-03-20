# Онбординг нового сервиса

## Цель

Сделать путь от идеи нового сервиса до GitOps-managed workload коротким, повторяемым и понятным без догадок.

## Базовый путь

1. Скопировать один из каталогов в `demo-microservices/services/` как основу для нового сервиса.
2. Реализовать код сервиса в `app/` и убедиться, что есть:
   - `/health`
   - `/ready`
   - `/metrics`
3. Заполнить `requirements.txt` и `Dockerfile`.
4. Заполнить `values/common.yaml` неизменяемыми параметрами сервиса:
   - `nameOverride`
   - `fullnameOverride`
   - `image.repository`
   - `containerPort`
   - `service.port`
   - `readinessProbe`
   - `livenessProbe`
5. Определить, какие платформенные возможности нужны сервису:
   - `configmap.enabled`
   - в git-tracked baseline предпочитать `secret.existingSecretName`; `secret.enabled` оставлять только для одноразовых локальных экспериментов вне коммитов
   - `ingress.enabled`
   - `serviceMonitor.enabled`
   - `rollout.enabled`
   - `podDisruptionBudget.enabled`
   - для GitOps/Vault-ready окружений добавить или обновить `ExternalSecret` в `platform-core/kubernetes/secrets/<env>/external-secrets.yaml`
6. Добавить или скорректировать environment overlays:
   - `platform-core/templates/service-template/values-dev.yaml`
   - `platform-core/templates/service-template/values-preview.yaml`
   - `platform-core/templates/service-template/values-stage.yaml`
   - `demo-microservices/services/<service>/values/dev.yaml`
   - `demo-microservices/services/<service>/values/preview.yaml`
   - `demo-microservices/services/<service>/values/stage.yaml`
7. Скопировать ArgoCD Application manifest из `demo-microservices/gitops/applications/` и обновить:
   - имя application
   - namespace назначения
   - Helm `releaseName`
   - пути к values-файлам сервиса
8. Проверить сервис локально:
   - `python -m pytest demo-microservices/tests`
   - `.\scripts\demo\build-images.ps1 -Environment dev`
9. Закоммитить код, values и Application manifest вместе. После этого сервис можно подхватить через родительское приложение в `platform-core/kubernetes/argocd/app-demo-services.yaml`.

## Обязательный контракт сервиса

- Для каждого окружения должны использоваться immutable image tags.
- У сервиса обязательно должны быть `requests` и `limits`.
- У сервиса обязательно должны быть readiness и liveness probes.
- Сервис должен публиковать `http_requests_total` и `http_request_duration_seconds_bucket` либо совместимый relabeled equivalent.
- Сервис должен оставаться совместимым и с `Deployment`, и с опциональным `Rollout`.
- Базовые labels под `app.kubernetes.io/*` и `platform.example.io/*` нельзя ломать service-specific overrides.

## Чеклист проверки

- В `values/common.yaml` задана identity сервиса и его порты.
- Для `dev`, `preview` и `stage` заданы корректные image tags.
- Публичные сервисы включают `ingress`, внутренние сервисы оставляют его выключенным.
- `configmap` не содержит чувствительных данных, а `secret` в committed values ссылается на `existingSecretName`, а не хранит `stringData`.
- Для сервиса существует соответствующий ArgoCD Application manifest в `demo-microservices/gitops/applications/`.
- Для `demo-dev`, `demo-preview` и `demo-stage` существует соответствующий `ExternalSecret` baseline, если сервису нужны секреты в GitOps-сценарии.

## Допущения

- ArgoCD версии 2.6+ поддерживает multi-source Applications с `$values/...`.
- CRD Prometheus Operator уже установлены до включения `serviceMonitor.enabled: true`.
- CRD Argo Rollouts уже установлены до включения `rollout.enabled: true` в `stage`.
- Локальный bootstrap создает Kubernetes secrets вне git, а GitOps/Vault-ready baseline уже описан через `SecretStore` и `ExternalSecret` manifests в `platform-core/kubernetes/secrets/`.
