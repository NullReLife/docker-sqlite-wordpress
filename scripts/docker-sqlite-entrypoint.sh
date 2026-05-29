#!/usr/bin/env bash
set -euo pipefail

WP_RUNTIME_DIR="${WORDPRESS_RUNTIME_DIR:-/var/www/html}"
WP_SOURCE_DIR="${WP_PREPARE_DIR:-/usr/src/wordpress}"
WP_OWNER="${WORDPRESS_FILE_OWNER:-www-data:www-data}"
WP_DIR_MODE="${WORDPRESS_DIR_MODE:-755}"
WP_FILE_MODE="${WORDPRESS_FILE_MODE:-644}"
WORDPRESS_UPLOAD_MAX_FILESIZE="${WORDPRESS_UPLOAD_MAX_FILESIZE:-256M}"
WORDPRESS_POST_MAX_SIZE="${WORDPRESS_POST_MAX_SIZE:-256M}"
WORDPRESS_PHP_MEMORY_LIMIT="${WORDPRESS_PHP_MEMORY_LIMIT:-512M}"
WORDPRESS_MEMORY_LIMIT="${WORDPRESS_MEMORY_LIMIT:-256M}"
WORDPRESS_MAX_MEMORY_LIMIT="${WORDPRESS_MAX_MEMORY_LIMIT:-512M}"
WORDPRESS_MAX_EXECUTION_TIME="${WORDPRESS_MAX_EXECUTION_TIME:-300}"
WORDPRESS_MAX_INPUT_TIME="${WORDPRESS_MAX_INPUT_TIME:-300}"

configure_php_upload_limits() {
  local ini_dir="${PHP_INI_DIR:-/usr/local/etc/php}/conf.d"
  mkdir -p "${ini_dir}"

  cat > "${ini_dir}/docker-wordpress-upload-limits.ini" <<EOF
upload_max_filesize = ${WORDPRESS_UPLOAD_MAX_FILESIZE}
post_max_size = ${WORDPRESS_POST_MAX_SIZE}
memory_limit = ${WORDPRESS_PHP_MEMORY_LIMIT}
max_execution_time = ${WORDPRESS_MAX_EXECUTION_TIME}
max_input_time = ${WORDPRESS_MAX_INPUT_TIME}
EOF
}

insert_filesystem_constants() {
  local config_file="$1"

  [ -f "${config_file}" ] || return 0
  grep -q "Docker SQLite WordPress filesystem settings" "${config_file}" && return 0

  local block_file tmp_file
  block_file="$(mktemp)"
  tmp_file="$(mktemp)"

  cat > "${block_file}" <<EOF
/* Docker SQLite WordPress filesystem settings. */
if ( ! defined( 'FS_METHOD' ) ) {
	define( 'FS_METHOD', 'direct' );
}
if ( ! defined( 'FS_CHMOD_DIR' ) ) {
	define( 'FS_CHMOD_DIR', ( 0755 & ~ umask() ) );
}
if ( ! defined( 'FS_CHMOD_FILE' ) ) {
	define( 'FS_CHMOD_FILE', ( 0644 & ~ umask() ) );
}
if ( ! defined( 'WP_MEMORY_LIMIT' ) ) {
	define( 'WP_MEMORY_LIMIT', '${WORDPRESS_MEMORY_LIMIT}' );
}
if ( ! defined( 'WP_MAX_MEMORY_LIMIT' ) ) {
	define( 'WP_MAX_MEMORY_LIMIT', '${WORDPRESS_MAX_MEMORY_LIMIT}' );
}
EOF

  awk -v block="$(cat "${block_file}")" '
    index($0, "wp-settings.php") && inserted == 0 { print block; inserted = 1 }
    { print }
    END { if ( inserted == 0 ) { print ""; print block } }
  ' "${config_file}" > "${tmp_file}"

  cat "${tmp_file}" > "${config_file}"
  rm -f "${block_file}" "${tmp_file}"
}

prepare_writable_wp_content() {
  local wp_dir="$1"
  [ -d "${wp_dir}" ] || return 0

  mkdir -p \
    "${wp_dir}/wp-content/plugins" \
    "${wp_dir}/wp-content/themes" \
    "${wp_dir}/wp-content/uploads" \
    "${wp_dir}/wp-content/upgrade" \
    "${wp_dir}/wp-content/database"

  if [ "$(id -u)" = "0" ]; then
    chown -R "${WP_OWNER}" \
      "${wp_dir}/wp-content/plugins" \
      "${wp_dir}/wp-content/themes" \
      "${wp_dir}/wp-content/uploads" \
      "${wp_dir}/wp-content/upgrade" \
      "${wp_dir}/wp-content/database" || true
  fi

  for target in \
    "${wp_dir}/wp-content/plugins" \
    "${wp_dir}/wp-content/themes" \
    "${wp_dir}/wp-content/uploads" \
    "${wp_dir}/wp-content/upgrade" \
    "${wp_dir}/wp-content/database"; do
    [ -d "${target}" ] || continue
    find "${target}" -type d -exec chmod "${WP_DIR_MODE}" {} + || true
    find "${target}" -type f -exec chmod "${WP_FILE_MODE}" {} + || true
  done
}

configure_php_upload_limits
insert_filesystem_constants "${WP_SOURCE_DIR}/wp-config.php"
insert_filesystem_constants "${WP_RUNTIME_DIR}/wp-config.php"
prepare_writable_wp_content "${WP_SOURCE_DIR}"
prepare_writable_wp_content "${WP_RUNTIME_DIR}"

exec docker-entrypoint.sh "$@"
