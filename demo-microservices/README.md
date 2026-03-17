# Демо-микросервисы

Этот каталог показывает платформу на живом примере. Здесь лежат сервисы, которые можно собрать, развернуть через GitOps, катить в `stage`, тестировать под нагрузкой и использовать в chaos-сценариях.

## Что внутри

- `shared/python/commerce_demo/` с общим runtime-кодом и инструментированием
- `services/<service>/app/` с кодом конкретного сервиса
- `services/<service>/Dockerfile` и `requirements.txt`
- `services/<service>/values/*.yaml` для `dev`, `preview` и `stage`
- `gitops/applications/*.yaml` для ArgoCD
- `tests/test_services.py` для базовой проверки сервисов

## Сервисы

- `api-gateway` принимает внешний трафик и собирает пользовательский путь
- `orders-service` принимает checkout-запрос и координирует создание заказа
- `payments-service` имитирует внешний платёжный провайдер и удобен как цель для canary

## Локальный запуск

```powershell
python -m pip install -r demo-microservices/requirements-dev.txt
pytest demo-microservices/tests
.\scripts\demo\build-images.ps1 -Environment dev
.\scripts\demo\build-images.ps1 -Environment stage
```

## Как это связано с GitOps

Сначала применяется `platform-core/kubernetes/argocd/project-platform.yaml`, затем `platform-core/kubernetes/argocd/app-demo-services.yaml`. После этого ArgoCD подхватывает `demo-environments` и service applications из `gitops/applications/`.

## Допущения

- application manifests указывают на `https://github.com/vorobey5858/devops-project.git`
- локальный runtime использует образы вида `devops/<service>` и неизменяемые теги из values
- наружу публикуется только `api-gateway`, остальные сервисы остаются cluster-local
