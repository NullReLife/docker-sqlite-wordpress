#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$(mktemp)"
cleanup() {
  rm -f "${ENV_FILE}"
}
trap cleanup EXIT

bash "${ROOT_DIR}/scripts/resolve-latest-versions.sh" --output "${ENV_FILE}"

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

IMAGE_TAG="sqlite-wordpress:${WORDPRESS_IMAGE#wordpress:}-sqlite-${SQLITE_DATABASE_INTEGRATION_SHORT_COMMIT}-native-parser"

cat <<EOF
Resolved realtime build inputs:
  WORDPRESS_VERSION=${WORDPRESS_VERSION}
  WORDPRESS_IMAGE=${WORDPRESS_IMAGE}
  WORDPRESS_PHP_VERSION=${WORDPRESS_PHP_VERSION}
  SQLITE_DATABASE_INTEGRATION_COMMIT=${SQLITE_DATABASE_INTEGRATION_COMMIT}
  IMAGE_TAG=${IMAGE_TAG}
EOF

cd "${ROOT_DIR}"

docker build \
  --pull \
  --no-cache \
  --build-arg WORDPRESS_IMAGE="${WORDPRESS_IMAGE}" \
  --build-arg SQLITE_DATABASE_INTEGRATION_COMMIT="${SQLITE_DATABASE_INTEGRATION_COMMIT}" \
  --build-arg WORDPRESS_HTTP_PORT="${WORDPRESS_HTTP_PORT}" \
  --build-arg UPDATE_CACHE_BUST="${UPDATE_CACHE_BUST}" \
  -t "${IMAGE_TAG}" \
  .
