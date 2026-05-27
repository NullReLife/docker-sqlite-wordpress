ARG WORDPRESS_IMAGE=wordpress:7.0.0-php8.5-apache
FROM ${WORDPRESS_IMAGE}
LABEL org.opencontainers.image.authors="soulteary@gmail.com"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV WORDPRESS_PREPARE_DIR=/usr/src/wordpress

# plugin: https://github.com/WordPress/sqlite-database-integration
ARG SQLITE_DATABASE_INTEGRATION_VERSION=2.2.23
# details: https://soulteary.com/2024/04/21/wordpress-sqlite-docker-image-packaging-details.html
RUN set -eux; \
    curl -fsSL -o sqlite-database-integration.tar.gz "https://github.com/WordPress/sqlite-database-integration/archive/refs/tags/v${SQLITE_DATABASE_INTEGRATION_VERSION}.tar.gz"; \
    tar -xzf sqlite-database-integration.tar.gz; \
    plugin_source_dir="sqlite-database-integration-${SQLITE_DATABASE_INTEGRATION_VERSION}/packages/plugin-sqlite-database-integration"; \
    if [ ! -d "${plugin_source_dir}" ]; then \
        plugin_source_dir="sqlite-database-integration-${SQLITE_DATABASE_INTEGRATION_VERSION}"; \
    fi; \
    mkdir -p "${WORDPRESS_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration"; \
    cp -r "${plugin_source_dir}/." "${WORDPRESS_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration/"; \
    rm -rf "sqlite-database-integration-${SQLITE_DATABASE_INTEGRATION_VERSION}" sqlite-database-integration.tar.gz; \
    mv "${WORDPRESS_PREPARE_DIR}/wp-content/mu-plugins/sqlite-database-integration/db.copy" "${WORDPRESS_PREPARE_DIR}/wp-content/db.php"; \
    sed -i 's#{SQLITE_IMPLEMENTATION_FOLDER_PATH}#/var/www/html/wp-content/mu-plugins/sqlite-database-integration#' "${WORDPRESS_PREPARE_DIR}/wp-content/db.php"; \
    sed -i 's#{SQLITE_PLUGIN}#sqlite-database-integration/load.php#' "${WORDPRESS_PREPARE_DIR}/wp-content/db.php"; \
    mkdir -p "${WORDPRESS_PREPARE_DIR}/wp-content/database"; \
    touch "${WORDPRESS_PREPARE_DIR}/wp-content/database/.ht.sqlite"; \
    chown -R www-data:www-data "${WORDPRESS_PREPARE_DIR}/wp-content/database"; \
    chmod 640 "${WORDPRESS_PREPARE_DIR}/wp-content/database/.ht.sqlite"
