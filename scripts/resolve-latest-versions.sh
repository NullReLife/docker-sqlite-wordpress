#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FILE=""
FORMAT="dotenv"

usage() {
  cat <<'EOF'
Usage: scripts/resolve-latest-versions.sh [--output FILE] [--format dotenv|shell|github-output]

Resolves the latest upstream versions for this realtime-update branch:
  - Latest stable WordPress version from api.wordpress.org
  - Highest PHP Apache tag for that WordPress version from docker-library/official-images
  - Latest sqlite-database-integration source commit from GitHub

By default, the result is printed as dotenv key=value lines.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      OUTPUT_FILE="${2:?Missing value for --output}"
      shift 2
      ;;
    --format)
      FORMAT="${2:?Missing value for --format}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${FORMAT}" in
  dotenv|shell|github-output) ;;
  *)
    echo "Unsupported format: ${FORMAT}" >&2
    exit 2
    ;;
esac

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

require_command curl
require_command python3

WORDPRESS_CORE_API="${WORDPRESS_CORE_API:-https://api.wordpress.org/core/version-check/1.7/}"
DOCKER_WORDPRESS_LIBRARY_URL="${DOCKER_WORDPRESS_LIBRARY_URL:-https://raw.githubusercontent.com/docker-library/official-images/master/library/wordpress}"
SQLITE_DATABASE_INTEGRATION_COMMITS_API="${SQLITE_DATABASE_INTEGRATION_COMMITS_API:-https://api.github.com/repos/WordPress/sqlite-database-integration/commits?per_page=1}"
WORDPRESS_HTTP_PORT="${WORDPRESS_HTTP_PORT:-7860}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

CORE_JSON="${TMP_DIR}/wordpress-core.json"
DOCKER_LIBRARY="${TMP_DIR}/docker-wordpress-library.txt"
SQLITE_JSON="${TMP_DIR}/sqlite-commits.json"

curl -fsSL "${WORDPRESS_CORE_API}" -o "${CORE_JSON}"
curl -fsSL "${DOCKER_WORDPRESS_LIBRARY_URL}" -o "${DOCKER_LIBRARY}"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  curl -fsSL \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${SQLITE_DATABASE_INTEGRATION_COMMITS_API}" \
    -o "${SQLITE_JSON}"
else
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "${SQLITE_DATABASE_INTEGRATION_COMMITS_API}" \
    -o "${SQLITE_JSON}"
fi

RESULT="$(
  python3 - "${CORE_JSON}" "${DOCKER_LIBRARY}" "${SQLITE_JSON}" "${WORDPRESS_HTTP_PORT}" "${FORMAT}" <<'PY'
import json
import re
import shlex
import sys
from datetime import datetime, timezone

core_path, docker_path, sqlite_path, http_port, output_format = sys.argv[1:6]

with open(core_path, "r", encoding="utf-8") as f:
    core = json.load(f)

offers = core.get("offers") or []
if not offers:
    raise SystemExit("WordPress core API returned no offers")

latest_offer = next((offer for offer in offers if offer.get("response") == "upgrade"), offers[0])
wordpress_version = str(latest_offer.get("current") or latest_offer.get("version") or "").strip()
if not wordpress_version:
    raise SystemExit("Could not resolve latest WordPress version")

def version_tuple(value, width=3):
    parts = [int(part) for part in str(value).split(".")]
    while len(parts) < width:
        parts.append(0)
    return tuple(parts[:width])

wordpress_tuple = version_tuple(wordpress_version)

with open(docker_path, "r", encoding="utf-8") as f:
    docker_library = f.read()

tags = []
for line in docker_library.splitlines():
    if line.startswith("Tags:"):
        tags.extend(tag.strip() for tag in line[len("Tags:"):].split(",") if tag.strip())

candidates = []
for tag in tags:
    match = re.fullmatch(r"(\d+(?:\.\d+){1,2})-php(\d+\.\d+)-apache", tag)
    if not match:
        continue
    tag_wordpress_version, php_version = match.groups()
    if version_tuple(tag_wordpress_version) != wordpress_tuple:
        continue
    php_major, php_minor = [int(part) for part in php_version.split(".")]
    candidates.append({
        "tag": tag,
        "wordpress_version": tag_wordpress_version,
        "php_version": php_version,
        "php_tuple": (php_major, php_minor),
        "specificity": len(tag_wordpress_version.split(".")),
    })

if not candidates:
    raise SystemExit(f"No official wordpress:*php*-apache Docker tag found for WordPress {wordpress_version}")

selected = max(candidates, key=lambda item: (item["php_tuple"], item["specificity"], item["tag"]))
wordpress_image = f"wordpress:{selected['tag']}"

with open(sqlite_path, "r", encoding="utf-8") as f:
    sqlite_data = json.load(f)

if isinstance(sqlite_data, list):
    if not sqlite_data:
        raise SystemExit("GitHub commits API returned no sqlite-database-integration commits")
    sqlite_commit = sqlite_data[0].get("sha", "")
else:
    sqlite_commit = sqlite_data.get("sha", "")

sqlite_commit = str(sqlite_commit).strip()
if not re.fullmatch(r"[0-9a-f]{40}", sqlite_commit):
    raise SystemExit("Could not resolve latest sqlite-database-integration commit SHA")

values = {
    "WORDPRESS_VERSION": wordpress_version,
    "WORDPRESS_IMAGE": wordpress_image,
    "WORDPRESS_PHP_VERSION": selected["php_version"],
    "SQLITE_DATABASE_INTEGRATION_COMMIT": sqlite_commit,
    "SQLITE_DATABASE_INTEGRATION_SHORT_COMMIT": sqlite_commit[:12],
    "WORDPRESS_HTTP_PORT": str(http_port),
    "UPDATE_CACHE_BUST": datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S"),
}

if output_format == "shell":
    for key, value in values.items():
        print(f"export {key}={shlex.quote(value)}")
else:
    for key, value in values.items():
        print(f"{key}={value}")
PY
)"

if [ -n "${OUTPUT_FILE}" ]; then
  printf '%s\n' "${RESULT}" > "${OUTPUT_FILE}"
else
  printf '%s\n' "${RESULT}"
fi
