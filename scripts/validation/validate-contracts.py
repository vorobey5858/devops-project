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


def main() -> None:
    assert_no_placeholders()
    assert_analysis_templates_and_rollout_align()
    assert_service_values_point_to_local_images()
    print("Contracts validated successfully.")


if __name__ == "__main__":
    main()
