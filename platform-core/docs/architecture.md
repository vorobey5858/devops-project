# Архитектура платформенного ядра

## Цель

`platform-core` задает базовый стандарт, при котором команда заводит новый сервис через один переиспользуемый Helm-чарт и один шаблон приложения ArgoCD, а не собирает новую схему развёртывания с нуля.

## Основные блоки

- `kubernetes/argocd/project-platform.yaml` определяет общий ArgoCD project.
- `kubernetes/argocd/app-demo-services.yaml` задает входную точку для схемы app-of-apps с демонстрационными нагрузками.
- `kubernetes/namespaces/team-template.yaml` остается базовым namespace шаблоном с quota и limits.
- `kubernetes/namespaces/demo-environments.yaml` добавляет готовые демонстрационные namespace для `dev`, `preview` и `stage`.
- `kubernetes/secrets/demo-*/external-secrets.yaml` задает Vault-backed `SecretStore` и `ExternalSecret` baseline для demo-окружений.
- `templates/service-template/` содержит переиспользуемый чарт для рабочей нагрузки.
- `docs/` фиксирует рабочий контракт для онбординга и наблюдаемости.

## Устройство сервисного шаблона

Чарт рендерит один сервис в формате, совместимом и с обычным `Deployment`, и с опциональным `Rollout`:

- `Deployment` используется по умолчанию.
- `Rollout` включается при `rollout.enabled: true` и в `stage` уже подключает контракт анализа через Prometheus.
- `Service` создается всегда и остается стабильной точкой доступа.
- `Ingress` опционален и включается только в окруженческих overlay сервиса.
- `ConfigMap` хранит только несекретную конфигурацию, а committed service values должны ссылаться на уже созданный `Secret` через `existingSecretName`.
- `ServiceMonitor` опционален и использует те же метки, что и рабочая нагрузка.
- `PodDisruptionBudget` и topology spread constraints можно включать через values без отдельного чарта на сервис.

## GitOps-структура

Базовый слой использует multi-source приложения ArgoCD:

- Первый источник указывает на `platform-core/templates/service-template`.
- Второй источник указывает на тот же репозиторий с `ref: values`.
- `valueFiles` объединяют:
  - значения окружения по умолчанию из `platform-core/templates/service-template/values-<env>.yaml`
  - сервисные значения по умолчанию из `demo-microservices/services/<service>/values/common.yaml`
  - окруженческие overlays из `demo-microservices/services/<service>/values/<env>.yaml`

За счет этого платформенный стандарт остаётся централизованным, а сервис владеет только своими values.

## Карта демонстрационных нагрузок

- `api-gateway` является внешней точкой входа и включает `Ingress`.
- `orders-service` является внутренней HTTP-нагрузкой и вызывает `payments-service`.
- `payments-service` является внутренней зависимостью и используется как основной stage canary пример.

## Допущения и зависимости

- Приложения ArgoCD уже привязаны к текущему удалённому репозиторию `https://github.com/vorobey5858/devops-project.git`.
- CRD Argo Rollouts должны быть доставлены слоем `secure-delivery` до синка stage-приложений.
- Локальный bootstrap уже использует pre-created `Secret` references, а GitOps/Vault-ready baseline для тех же имен секретов лежит в `platform-core/kubernetes/secrets/`.
- GitOps manifests фиксируют ветку через `targetRevision: refs/heads/main`, чтобы ArgoCD не дрейфовал между `master`, `HEAD` и фактической основной веткой репозитория.
- SLO и alerting, которыми владеет reliability-слой, должны использовать те же метки и пути метрик, что определены здесь.
- Локальный runtime использует образы вида `devops/<service>` и импорт в `k3s` containerd, а доставка через реестр остаётся задачей CI.

## Что не входит в этот слой

- Backstage или более широкий internal portal
- автоматизация production DNS
- логика продвижения между кластерами
