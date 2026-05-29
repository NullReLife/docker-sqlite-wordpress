#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env.latest"

bash "${ROOT_DIR}/scripts/resolve-latest-versions.sh" --output "${ENV_FILE}"

cat <<EOF
Wrote ${ENV_FILE}
Use this file to reproduce the same resolved build inputs until you refresh it again.
EOF

cd "${ROOT_DIR}"

docker compose --env-file "${ENV_FILE}" build --pull --no-cache
docker compose --env-file "${ENV_FILE}" up -d
