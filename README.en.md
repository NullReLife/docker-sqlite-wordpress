# Docker SQLite WordPress

[简体中文](README.md) | English

![](.github/about.jpg)

WordPress + SQLite Database Integration, ready to run without MySQL, MariaDB, or PostgreSQL.

This image is based on the official WordPress Docker image and installs the WordPress SQLite Database Integration plugin as an MU plugin. The SQLite drop-in is copied to `wp-content/db.php`, and WordPress stores its database in a SQLite file.

## Versions

- WordPress: 7.0.0
- PHP: 8.5
- SQLite Database Integration: 2.2.23
- Base image: `wordpress:7.0.0-php8.5-apache`

All versions are pinned for reproducible builds. This project does not use `wordpress:latest`, floating WordPress tags, or SQLite Database Integration release candidates.

## Build

Build the Docker image locally:

```bash
docker build \
  --build-arg WORDPRESS_IMAGE=wordpress:7.0.0-php8.5-apache \
  --build-arg SQLITE_DATABASE_INTEGRATION_VERSION=2.2.23 \
  -t sqlite-wordpress:7.0.0-php8.5-apache-sqlite-2.2.23 \
  .
```

## Run with Docker Compose

Start WordPress:

```bash
docker compose up -d
```

Then open:

```text
http://localhost:8080
```

The WordPress installation page should appear.

## Data Directory

Runtime WordPress files are stored in:

```text
./wordpress
```

The SQLite database file is stored inside the WordPress data directory at:

```text
wp-content/database/.ht.sqlite
```

With the default Compose volume, that resolves to:

```text
./wordpress/wp-content/database/.ht.sqlite
```

Before upgrading this image or changing plugin versions, always back up the full `./wordpress` directory.

## Docker Compose Configuration

The project uses a single `wordpress` service and does not require a separate database container:

```yaml
services:
  wordpress:
    build:
      context: .
      args:
        WORDPRESS_IMAGE: wordpress:7.0.0-php8.5-apache
        SQLITE_DATABASE_INTEGRATION_VERSION: 2.2.23
    restart: always
    ports:
      - "8080:80"
    volumes:
      - ./wordpress:/var/www/html
```

## Smoke Test

Run the smoke test after making changes:

```bash
bash scripts/smoke-test.sh
```

The test builds the image, starts a temporary container on `127.0.0.1:18080`, checks that `wp-admin/install.php` is reachable, verifies the SQLite integration files and database directory, confirms PHP has SQLite support, and removes the test container automatically.

## Articles

- [WordPress SQLite Docker image packaging details](https://soulteary.com/2024/04/21/wordpress-sqlite-docker-image-packaging-details.html)
- [WordPress farewell to MySQL: Docker SQLite WordPress](https://soulteary.com/2024/04/17/say-goodbye-to-mysql-docker-sqlite-wordpress.html)

![](.github/ready-to-use.jpg)
