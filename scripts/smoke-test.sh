#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="sqlite-wordpress-realtime-native-parser-smoke:local"
CONTAINER_NAME="sqlite-wordpress-realtime-native-parser-smoke-test"
HOST_PORT="18080"
CONTAINER_PORT="7860"
TEST_VOLUME="$(mktemp -d)"
ENV_FILE="$(mktemp)"

cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  rm -rf "${TEST_VOLUME}"
  rm -f "${ENV_FILE}"
}
trap cleanup EXIT

bash "${ROOT_DIR}/scripts/resolve-latest-versions.sh" --output "${ENV_FILE}"

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

cd "${ROOT_DIR}"

cat <<EOF
Resolved realtime smoke-test inputs:
  WORDPRESS_VERSION=${WORDPRESS_VERSION}
  WORDPRESS_IMAGE=${WORDPRESS_IMAGE}
  WORDPRESS_PHP_VERSION=${WORDPRESS_PHP_VERSION}
  SQLITE_DATABASE_INTEGRATION_COMMIT=${SQLITE_DATABASE_INTEGRATION_COMMIT}
EOF

docker build \
  --pull \
  --no-cache \
  --build-arg WORDPRESS_IMAGE="${WORDPRESS_IMAGE}" \
  --build-arg SQLITE_DATABASE_INTEGRATION_COMMIT="${SQLITE_DATABASE_INTEGRATION_COMMIT}" \
  --build-arg WORDPRESS_HTTP_PORT="${CONTAINER_PORT}" \
  --build-arg UPDATE_CACHE_BUST="${UPDATE_CACHE_BUST}" \
  -t "${IMAGE_NAME}" \
  .

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  -v "${TEST_VOLUME}:/var/www/html" \
  "${IMAGE_NAME}" >/dev/null

for _ in $(seq 1 60); do
  if curl -fsSL "http://127.0.0.1:${HOST_PORT}/wp-admin/install.php" >/dev/null; then
    break
  fi
  sleep 1
done

curl -fsSL "http://127.0.0.1:${HOST_PORT}/wp-admin/install.php" >/dev/null

docker exec "${CONTAINER_NAME}" test -f /var/www/html/wp-content/db.php
docker exec "${CONTAINER_NAME}" test -f /var/www/html/wp-config.php
docker exec "${CONTAINER_NAME}" test -d /var/www/html/wp-content/mu-plugins/sqlite-database-integration
docker exec "${CONTAINER_NAME}" test -d /var/www/html/wp-content/database

docker exec "${CONTAINER_NAME}" sh -c "php -m | grep -Eiq '^(sqlite3|pdo_sqlite)$'"
docker exec "${CONTAINER_NAME}" sh -c "php -m | grep -qx wp_mysql_parser"

echo "Realtime native parser self-check passed."
