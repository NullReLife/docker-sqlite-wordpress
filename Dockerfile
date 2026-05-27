ARG WORDPRESS_IMAGE=wordpress:7.0.0-php8.5-apache
FROM ${WORDPRESS_IMAGE}
LABEL org.opencontainers.image.authors="soulteary@gmail.com"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV WORDPRESS_PREPARE_DIR=/usr/src/wordpress
ARG WORDPRESS_HTTP_PORT=7860
ENV WORDPRESS_HTTP_PORT=${WORDPRESS_HTTP_PORT}

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends unzip; \
    sed -ri 's!^Listen 80$!Listen '"${WORDPRESS_HTTP_PORT}"'!' /etc/apache2/ports.conf; \
    sed -ri "s!<VirtualHost \\*:80>!<VirtualHost *:${WORDPRESS_HTTP_PORT}>!" /etc/apache2/sites-available/000-default.conf; \
    php -m | grep -Eiq '^(sqlite3|pdo_sqlite)$'; \
    rm -rf /var/lib/apt/lists/*

EXPOSE ${WORDPRESS_HTTP_PORT}

# plugin: https://github.com/WordPress/sqlite-database-integration
ARG SQLITE_DATABASE_INTEGRATION_VERSION=2.2.23
# details: https://soulteary.com/2024/04/21/wordpress-sqlite-docker-image-packaging-details.html
RUN set -eux; \
    curl -fsSL -o sqlite-database-integration.zip "https://downloads.wordpress.org/plugin/sqlite-database-integration.${SQLITE_DATABASE_INTEGRATION_VERSION}.zip"; \
    unzip -q sqlite-database-integration.zip; \
    plugin_source_dir="sqlite-database-integration"; \
    test -f "${plugin_source_dir}/db.copy"; \
    mkdir -p "${WORDPRESS_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration"; \
    cp -r "${plugin_source_dir}/." "${WORDPRESS_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration/"; \
    rm -rf "${plugin_source_dir}" sqlite-database-integration.zip; \
    mv "${WORDPRESS_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration/db.copy" "${WORDPRESS_PREPARE_DIR}/wp-content/db.php"; \
    sed -i 's#{SQLITE_IMPLEMENTATION_FOLDER_PATH}#/var/www/html/wp-content/mu-plugins/sqlite-database-integration#' "${WORDPRESS_PREPARE_DIR}/wp-content/db.php"; \
    sed -i 's#{SQLITE_PLUGIN}#sqlite-database-integration/load.php#' "${WORDPRESS_PREPARE_DIR}/wp-content/db.php"; \
    mkdir -p "${WORDPRESS_PREPARE_DIR}/wp-content/database"; \
    touch "${WORDPRESS_PREPARE_DIR}/wp-content/database/.ht.sqlite"; \
    chown -R www-data:www-data "${WORDPRESS_PREPARE_DIR}/wp-content/database"; \
    chmod 640 "${WORDPRESS_PREPARE_DIR}/wp-content/database/.ht.sqlite"
