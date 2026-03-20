from __future__ import annotations

from pathlib import Path
import sys

import yaml


ROOT = Path(__file__).resolve().parents[2]
SCAN_ROOTS = [
    ROOT / ".github" / "workflows",
    ROOT / "bootstrap",
    ROOT / "platform-core",
    ROOT / "secure-delivery",
    ROOT / "demo-microservices",
    ROOT / "reliability-lab",
    ROOT / "scripts",
]


def load_yaml(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return list(yaml.safe_load_all(handle))


def assert_no_placeholders() -> None:
    banned = {
        "team-demo": [],
        "REPLACE_WITH_REAL_COSIGN_PUBLIC_KEY": [],
        "ghcr.io/example": [],
    }

    files = [ROOT / "README.md"]
    for scan_root in SCAN_ROOTS:
        for path in scan_root.rglob("*"):
            if path.is_dir():
                continue
            if path.suffix.lower() not in {".md", ".py", ".yaml", ".yml", ".tpl", ".ps1"}:
                continue
            files.append(path)

    for path in files:
        if path.resolve() == Path(__file__).resolve():
            continue
        content = path.read_text(encoding="utf-8")
        for token in banned:
            if token in content:
                banned[token].append(path.relative_to(ROOT))

    errors = [f"{token}: {paths}" for token, paths in banned.items() if paths]
    if errors:
        raise SystemExit("Found unresolved placeholders:\n" + "\n".join(errors))


def assert_analysis_templates_and_rollout_align() -> None:
    analysis_docs = load_yaml(ROOT / "secure-delivery/argo-rollouts/analysis-templates.yaml")
    rollout_docs = load_yaml(ROOT / "secure-delivery/argo-rollouts/demo-canary.yaml")

    template_names = {doc["metadata"]["name"] for doc in analysis_docs if doc}
    rollout = next(doc for doc in rollout_docs if doc and doc["kind"] == "Rollout")
    steps = rollout["spec"]["strategy"]["canary"]["steps"]

    referenced_templates = set()
    for step in steps:
        if "analysis" not in step:
            continue
        for template in step["analysis"]["templates"]:
            referenced_templates.add(template["templateName"])

    missing = sorted(referenced_templates - template_names)
    if missing:
        raise SystemExit(f"Rollout references missing analysis templates: {missing}")


def assert_service_values_point_to_local_images() -> None:
    expected = {
        "api-gateway": "devops/api-gateway",
        "orders-service": "devops/orders-service",
        "payments-service": "devops/payments-service",
    }
    for service, repository in expected.items():
        values = load_yaml(ROOT / f"demo-microservices/services/{service}/values/common.yaml")[0]
        actual = values["image"]["repository"]
        if actual != repository:
            raise SystemExit(f"{service} image repository mismatch: expected {repository}, got {actual}")


def assert_demo_services_use_precreated_secrets() -> None:
    expected_secret_names = {
        "api-gateway": "api-gateway-secrets",
        "orders-service": "orders-service-secrets",
        "payments-service": "payments-service-secrets",
    }

    for service, secret_name in expected_secret_names.items():
        values = load_yaml(ROOT / f"demo-microservices/services/{service}/values/common.yaml")[0]
        secret_config = values.get("secret", {})

        if secret_config.get("enabled"):
            raise SystemExit(f"{service} must not commit inline Secret manifests in values/common.yaml.")

        if secret_config.get("existingSecretName") != secret_name:
            raise SystemExit(
                f"{service} secret reference mismatch: expected {secret_name}, got {secret_config.get('existingSecretName')!r}"
            )

        if secret_config.get("stringData"):
            raise SystemExit(f"{service} must not keep stringData defaults in git-tracked values/common.yaml.")


def assert_gitops_target_revisions_are_explicit() -> None:
    expected_revision = "refs/heads/main"
    application_paths = [
        ROOT / "platform-core/kubernetes/argocd/app-demo-services.yaml",
        *sorted((ROOT / "demo-microservices/gitops/applications").glob("*.yaml")),
    ]

    for path in application_paths:
        for doc in load_yaml(path):
            if not doc or doc.get("kind") != "Application":
                continue

            spec = doc.get("spec", {})
            sources = []
            if "source" in spec:
                sources.append(spec["source"])
            sources.extend(spec.get("sources", []))

            for source in sources:
                if source.get("repoURL") != "https://github.com/vorobey5858/devops-project.git":
                    continue
                actual_revision = source.get("targetRevision")
                if actual_revision != expected_revision:
                    raise SystemExit(
                        f"{path.relative_to(ROOT)} must pin targetRevision to {expected_revision!r}, got {actual_revision!r}"
                    )


def assert_grafana_admin_secret_is_externalized() -> None:
    values = load_yaml(ROOT / "bootstrap/helm-values/kube-prometheus-stack-values.yaml")[0]
    grafana = values.get("grafana", {})

    if "adminPassword" in grafana:
        raise SystemExit("Grafana adminPassword must not be committed in bootstrap helm values.")

    admin = grafana.get("admin", {})
    expected = {
        "existingSecret": "grafana-admin-credentials",
        "userKey": "admin-user",
        "passwordKey": "admin-password",
    }

    for key, expected_value in expected.items():
        actual_value = admin.get(key)
        if actual_value != expected_value:
            raise SystemExit(f"Grafana admin secret config mismatch for {key}: expected {expected_value!r}, got {actual_value!r}")


def assert_gitignore_covers_local_secrets() -> None:
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    if ".secrets/" not in gitignore:
        raise SystemExit("Missing .secrets/ entry in .gitignore.")


def assert_external_secrets_baseline_exists() -> None:
    expected_apps = {
        "demo-dev-secrets": "demo-dev",
        "demo-preview-secrets": "demo-preview",
        "demo-stage-secrets": "demo-stage",
    }
    expected_secret_names = {
        "api-gateway-secrets",
        "orders-service-secrets",
        "payments-service-secrets",
    }

    for app_name, namespace in expected_apps.items():
        app_path = ROOT / f"demo-microservices/gitops/applications/{app_name}.yaml"
        if not app_path.exists():
            raise SystemExit(f"Missing External Secrets application manifest: {app_path.relative_to(ROOT)}")

        app = load_yaml(app_path)[0]
        if app["spec"]["destination"]["namespace"] != namespace:
            raise SystemExit(
                f"{app_path.relative_to(ROOT)} destination namespace mismatch: expected {namespace!r}, got {app['spec']['destination']['namespace']!r}"
            )

        secret_path = ROOT / f"platform-core/kubernetes/secrets/{namespace}/external-secrets.yaml"
        if not secret_path.exists():
            raise SystemExit(f"Missing External Secrets manifest: {secret_path.relative_to(ROOT)}")

        docs = [doc for doc in load_yaml(secret_path) if doc]
        if not docs or docs[0]["kind"] != "SecretStore":
            raise SystemExit(f"{secret_path.relative_to(ROOT)} must start with a SecretStore definition.")

        actual_secret_names = {
            doc["metadata"]["name"]
            for doc in docs
            if doc.get("kind") == "ExternalSecret"
        }
        if actual_secret_names != expected_secret_names:
            raise SystemExit(
                f"{secret_path.relative_to(ROOT)} must define {sorted(expected_secret_names)}, got {sorted(actual_secret_names)}"
            )

        for doc in docs:
            if doc["metadata"].get("namespace") != namespace:
                raise SystemExit(
                    f"{secret_path.relative_to(ROOT)} contains resource in namespace {doc['metadata'].get('namespace')!r}, expected {namespace!r}"
                )


def main() -> None:
    assert_no_placeholders()
    assert_analysis_templates_and_rollout_align()
    assert_service_values_point_to_local_images()
    assert_demo_services_use_precreated_secrets()
    assert_gitops_target_revisions_are_explicit()
    assert_grafana_admin_secret_is_externalized()
    assert_gitignore_covers_local_secrets()
    assert_external_secrets_baseline_exists()
    print("Contracts validated successfully.")


if __name__ == "__main__":
    main()
