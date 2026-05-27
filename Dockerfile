ARG WORDPRESS_IMAGE=wordpress:7.0.0-php8.5-apache

FROM ${WORDPRESS_IMAGE} AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG SQLITE_DATABASE_INTEGRATION_COMMIT=e5513936c800f14b6795e7fce71505afad331b11
ENV SQLITE_DATABASE_INTEGRATION_SOURCE_DIR=/usr/src/sqlite-database-integration
ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
ENV PATH=/usr/local/cargo/bin:${PATH}

RUN set -eux; \
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
    git clone --filter=blob:none --no-checkout https://github.com/WordPress/sqlite-database-integration.git "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}"; \
    git -C "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}" checkout --detach "${SQLITE_DATABASE_INTEGRATION_COMMIT}"; \
    test -d "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/php-ext-wp-mysql-parser"; \
    test -f "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/plugin-sqlite-database-integration/db.copy"; \
    rm -rf "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/.git"; \
    export LIBCLANG_PATH="$(dirname "$(find /usr/lib -name 'libclang.so*' -print -quit)")"; \
    export PHP_CONFIG="$(command -v php-config)"; \
    cargo build --release --manifest-path "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/php-ext-wp-mysql-parser/Cargo.toml"; \
    test -f "${SQLITE_DATABASE_INTEGRATION_SOURCE_DIR}/packages/php-ext-wp-mysql-parser/target/release/libwp_mysql_parser.so"

FROM ${WORDPRESS_IMAGE}
LABEL org.opencontainers.image.authors="soulteary@gmail.com"
LABEL org.opencontainers.image.description="WordPress with SQLite Database Integration and native wp_mysql_parser extension"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV WP_PREPARE_DIR=/usr/src/wordpress
ARG WORDPRESS_HTTP_PORT=7860

COPY --from=builder /usr/src/sqlite-database-integration/packages/php-ext-wp-mysql-parser/target/release/libwp_mysql_parser.so /tmp/libwp_mysql_parser.so
COPY --from=builder /usr/src/sqlite-database-integration/packages/plugin-sqlite-database-integration /tmp/sqlite-database-integration

RUN set -eux; \
    sed -ri 's!^Listen 80$!Listen '"${WORDPRESS_HTTP_PORT}"'!' /etc/apache2/ports.conf; \
    sed -ri "s!<VirtualHost \\*:80>!<VirtualHost *:${WORDPRESS_HTTP_PORT}>!" /etc/apache2/sites-available/000-default.conf; \
    php -m | grep -Eiq '^(sqlite3|pdo_sqlite)$'; \
    extension_dir="$(php-config --extension-dir)"; \
    cp /tmp/libwp_mysql_parser.so "${extension_dir}/wp_mysql_parser.so"; \
    echo 'extension=wp_mysql_parser.so' > /usr/local/etc/php/conf.d/docker-php-ext-wp-mysql-parser.ini; \
    php -m | grep -qx wp_mysql_parser; \
    test -f "${WP_PREPARE_DIR}/wp-config-docker.php"; \
    cp "${WP_PREPARE_DIR}/wp-config-docker.php" "${WP_PREPARE_DIR}/wp-config.php"; \
    mkdir -p "${WP_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration"; \
    cp -r /tmp/sqlite-database-integration/. "${WP_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration/"; \
    rm -rf /tmp/libwp_mysql_parser.so /tmp/sqlite-database-integration; \
    mv "${WP_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration/db.copy" "${WP_PREPARE_DIR}/wp-content/db.php"; \
    sed -i 's#{SQLITE_IMPLEMENTATION_FOLDER_PATH}#/var/www/html/wp-content/mu-plugins/sqlite-database-integration#' "${WP_PREPARE_DIR}/wp-content/db.php"; \
    sed -i 's#{SQLITE_PLUGIN}#sqlite-database-integration/load.php#' "${WP_PREPARE_DIR}/wp-content/db.php"; \
    mkdir -p "${WP_PREPARE_DIR}/wp-content/database"; \
    touch "${WP_PREPARE_DIR}/wp-content/database/.ht.sqlite"; \
    chown -R www-data:www-data "${WP_PREPARE_DIR}/wp-content/database"; \
    chmod 640 "${WP_PREPARE_DIR}/wp-content/database/.ht.sqlite"

EXPOSE ${WORDPRESS_HTTP_PORT}
