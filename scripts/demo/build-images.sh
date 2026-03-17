#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-stage}"
IMPORT_IMAGES="${IMPORT_IMAGES:-true}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCHIVE_DIR="${ARCHIVE_DIR:-$REPO_ROOT/.bootstrap/images}"

mkdir -p "$ARCHIVE_DIR"

get_image_tag() {
  local values_file="$1"
  grep -E 'tag:\s*"' "$values_file" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/'
}

build_and_optionally_import() {
  local service="$1"
  local dockerfile="$2"
  local values_file="$REPO_ROOT/demo-microservices/services/$service/values/$ENVIRONMENT.yaml"
  local tag
  tag="$(get_image_tag "$values_file")"
  local image_ref="devops/$service:$tag"
  local archive_path="$ARCHIVE_DIR/$service-$tag.tar"

  docker build \
    --file "$REPO_ROOT/$dockerfile" \
    --tag "$image_ref" \
    "$REPO_ROOT"

  docker save --output "$archive_path" "$image_ref"
  echo "Saved archive $archive_path"

  if [[ "$IMPORT_IMAGES" == "true" ]]; then
    sudo k3s ctr -n k8s.io images import "$archive_path"
  fi
}

build_and_optionally_import "api-gateway" "demo-microservices/services/api-gateway/Dockerfile"
build_and_optionally_import "orders-service" "demo-microservices/services/orders-service/Dockerfile"
build_and_optionally_import "payments-service" "demo-microservices/services/payments-service/Dockerfile"

echo "Image build workflow completed for environment $ENVIRONMENT."
