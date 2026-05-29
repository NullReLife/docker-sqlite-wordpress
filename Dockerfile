ARG WORDPRESS_IMAGE=wordpress:apache

FROM ${WORDPRESS_IMAGE} AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG SQLITE_DATABASE_INTEGRATION_COMMIT=latest
ARG UPDATE_CACHE_BUST=manual
ENV SQLITE_DATABASE_INTEGRATION_SOURCE_DIR=/usr/src/sqlite-database-integration
ENV SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR=/tmp/sqlite-database-integration-plugin
ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
ENV PATH=/usr/local/cargo/bin:${PATH}

RUN set -eux; \
    echo "Update cache bust: ${UPDATE_CACHE_BUST}"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        clang \
        curl \
        git \
        libclang-dev \
        pkg-config; \
    command -v php-config; \
    command -v phpize; \
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable; \
    rustc --version; \
    cargo --version; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    git clone --filter=blob:none https://github.com/WordPress/sqlite-database-integration.git "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}"; \
    if [ -n "${SQLITE_DATABASE_INTEGRATION_COMMIT}" ] && [ "${SQLITE_DATABASE_INTEGRATION_COMMIT}" != "latest" ]; then \
        git -C "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}" checkout --detach "${SQLITE_DATABASE_INTEGRATION_COMMIT}"; \
    fi; \
    resolved_commit="$(git -C "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}" rev-parse HEAD)"; \
    echo "${resolved_commit}" > "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/.source-commit"; \
    test -d "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/php-ext-wp-mysql-parser"; \
    test -d "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/plugin-sqlite-database-integration"; \
    test -d "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/mysql-on-sqlite/src"; \
    export LIBCLANG_PATH="$(dirname "$(find /usr/lib -name 'libclang.so*' -print -quit)")"; \
    export PHP_CONFIG="$(command -v php-config)"; \
    cargo build --release --manifest-path "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/php-ext-wp-mysql-parser/Cargo.toml"; \
    test -f "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/php-ext-wp-mysql-parser/target/release/libwp_mysql_parser.so"; \
    cp "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/php-ext-wp-mysql-parser/target/release/libwp_mysql_parser.so" /tmp/libwp_mysql_parser.so; \
    cp -R "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/plugin-sqlite-database-integration" "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}"; \
    rm -rf "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}/wp-includes/database"; \
    cp -R "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/mysql-on-sqlite/src" "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}/wp-includes/database"; \
    rm -rf "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}/composer.json" \
           "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}/vendor" \
           "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}/node_modules"; \
    test -f "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}/db.copy"; \
    test -f "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}/load.php"; \
    test -f "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}/wp-includes/sqlite/db.php"; \
    test -f "${SQLITE_DATABASE_INTEGRATION_PLUGIN_DIR}/wp-includes/database/version.php"; \
    rm -rf "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/.git" \
           "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/php-ext-wp-mysql-parser/target"; \
    test -f /tmp/libwp_mysql_parser.so

FROM ${WORDPRESS_IMAGE}
LABEL org.opencontainers.image.authors="soulteary@gmail.com"
LABEL org.opencontainers.image.description="WordPress with latest SQLite Database Integration source and native wp_mysql_parser extension"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV WP_PREPARE_DIR=/usr/src/wordpress
ARG WORDPRESS_HTTP_PORT=7860
ARG SQLITE_DATABASE_INTEGRATION_COMMIT=latest
ARG UPDATE_CACHE_BUST=manual

COPY --from=builder /tmp/libwp_mysql_parser.so /tmp/libwp_mysql_parser.so
COPY --from=builder /tmp/sqlite-database-integration-plugin /tmp/sqlite-database-integration-plugin
COPY scripts/docker-sqlite-entrypoint.sh /usr/local/bin/docker-sqlite-entrypoint.sh

RUN set -eux; \
    echo "Update cache bust: ${UPDATE_CACHE_BUST}"; \
    sed -ri 's!^Listen 80$!Listen '"${WORDPRESS_HTTP_PORT}"'!' /etc/apache2/ports.conf; \
    sed -ri "s!<VirtualHost \\*:80>!<VirtualHost *:${WORDPRESS_HTTP_PORT}>!" /etc/apache2/sites-available/000-default.conf; \
    php -m | grep -Eiq '^(sqlite3|pdo_sqlite)$'; \
    extension_dir="$(php-config --extension-dir)"; \
    cp /tmp/libwp_mysql_parser.so "${extension_dir}/wp_mysql_parser.so"; \
    echo 'extension=wp_mysql_parser.so' > /usr/local/etc/php/conf.d/docker-php-ext-wp-mysql-parser.ini; \
    php -m | grep -qx wp_mysql_parser; \
    plugin_source_dir="/tmp/sqlite-database-integration-plugin"; \
    test -f "${plugin_source_dir}/db.copy"; \
    test -f "${plugin_source_dir}/wp-includes/sqlite/db.php"; \
    test -f "${plugin_source_dir}/wp-includes/database/version.php"; \
    test -f "${WP_PREPARE_DIR}/wp-config-docker.php"; \
    cp "${WP_PREPARE_DIR}/wp-config-docker.php" "${WP_PREPARE_DIR}/wp-config.php"; \
    mkdir -p "${WP_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration"; \
    cp -r "${plugin_source_dir}/." "${WP_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration/"; \
    rm -rf /tmp/libwp_mysql_parser.so "${plugin_source_dir}"; \
    mv "${WP_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration/db.copy" "${WP_PREPARE_DIR}/wp-content/db.php"; \
    sed -i 's#{SQLITE_IMPLEMENTATION_FOLDER_PATH}#/var/www/html/wp-content/mu-plugins/sqlite-database-integration#' "${WP_PREPARE_DIR}/wp-content/db.php"; \
    mkdir -p "${WP_PREPARE_DIR}/wp-content/database"; \
    touch "${WP_PREPARE_DIR}/wp-content/database/.ht.sqlite"; \
    chown -R www-data:www-data "${WP_PREPARE_DIR}/wp-content/database"; \
    chmod 640 "${WP_PREPARE_DIR}/wp-content/database/.ht.sqlite"; \
    chmod +x /usr/local/bin/docker-sqlite-entrypoint.sh

EXPOSE ${WORDPRESS_HTTP_PORT}
ENTRYPOINT ["docker-sqlite-entrypoint.sh"]
CMD ["apache2-foreground"]
