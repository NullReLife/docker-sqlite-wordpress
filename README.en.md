# Docker SQLite WordPress Realtime Native Parser

[简体中文](README.md) | English

![](.github/about.jpg)

This is the **realtime native-parser performance-optimized variant** of WordPress + SQLite Database Integration. It runs WordPress without MySQL, MariaDB, or PostgreSQL, resolves the latest upstream versions at build time, and compiles and loads the SQLite Database Integration project's native PHP extension, `wp_mysql_parser`.

> `wp_mysql_parser` is a performance optimization component. It is not required for SQLite support. Without this native extension, SQLite Database Integration can still run normally with the pure PHP parser. The stable pure PHP version stays on the `main` branch; the pinned native parser version stays on the `native-parser` branch; this branch tracks upstream automatically.

This image is based on the official WordPress Docker image and installs SQLite Database Integration source as an MU plugin. The SQLite drop-in is copied to `wp-content/db.php`, and WordPress stores its database in a SQLite file.

## Branches

- `main`: stable pure PHP version, using the WordPress.org release package.
- `native-parser`: performance-optimized version, using a pinned WordPress image and a pinned SQLite Database Integration source commit.
- `realtime-update`: realtime update version, resolving the latest official WordPress Docker image tag and the latest SQLite Database Integration source commit before each build.

## Realtime update strategy

This branch no longer requires manually editing fixed WordPress / PHP / SQLite source versions. The resolver script does this dynamically:

1. Reads the latest stable WordPress version from the official WordPress Core API.
2. Reads the official Docker `wordpress` image manifest and filters `phpX.Y-apache` tags for that WordPress version.
3. Chooses the highest PHP Apache tag, for example `wordpress:7.0.0-php8.5-apache`.
4. Reads the latest source commit from the `WordPress/sqlite-database-integration` GitHub repository.
5. Uses the same SQLite Database Integration source tree both as the MU plugin source and as the native `wp_mysql_parser` build source, avoiding mismatches between the plugin package and native parser source.

To inspect the versions that would be used right now, run:

```bash
bash scripts/resolve-latest-versions.sh
```

Example output:

```env
WORDPRESS_VERSION=7.0
WORDPRESS_IMAGE=wordpress:7.0.0-php8.5-apache
WORDPRESS_PHP_VERSION=8.5
SQLITE_DATABASE_INTEGRATION_COMMIT=<latest-upstream-commit>
SQLITE_DATABASE_INTEGRATION_SHORT_COMMIT=<short-sha>
WORDPRESS_HTTP_PORT=7860
UPDATE_CACHE_BUST=<utc-timestamp>
```

## Build

Recommended:

```bash
bash scripts/build-latest.sh
```

The script resolves the latest upstream versions first, then runs:

```bash
docker build \
  --pull \
  --no-cache \
  --build-arg WORDPRESS_IMAGE="<resolved-wordpress-image>" \
  --build-arg SQLITE_DATABASE_INTEGRATION_COMMIT="<resolved-sqlite-commit>" \
  --build-arg WORDPRESS_HTTP_PORT=7860 \
  --build-arg UPDATE_CACHE_BUST="<utc-timestamp>" \
  .
```

You can also build manually and let the Dockerfile use its realtime defaults:

```bash
docker build --pull --no-cache -t sqlite-wordpress:realtime-native-parser .
```

Default build args:

```dockerfile
WORDPRESS_IMAGE=wordpress:apache
SQLITE_DATABASE_INTEGRATION_COMMIT=latest
WORDPRESS_HTTP_PORT=7860
```

Use `scripts/build-latest.sh` when you specifically want the resolver to pick the latest WordPress version plus the highest official PHP Apache tag.

## Run with Docker Compose

Recommended:

```bash
bash scripts/compose-up-latest.sh
```

The script writes `.env.latest`, then runs:

```bash
docker compose --env-file .env.latest build --pull --no-cache
docker compose --env-file .env.latest up -d
```

Then open:

```text
http://localhost:7860
```

The WordPress installation page should appear.

## Docker Compose configuration

`docker-compose.yml` reads environment variables and provides realtime defaults:

```yaml
services:
  wordpress:
    build:
      context: .
      args:
        WORDPRESS_IMAGE: ${WORDPRESS_IMAGE:-wordpress:apache}
        SQLITE_DATABASE_INTEGRATION_COMMIT: ${SQLITE_DATABASE_INTEGRATION_COMMIT:-latest}
        WORDPRESS_HTTP_PORT: ${WORDPRESS_HTTP_PORT:-7860}
        UPDATE_CACHE_BUST: ${UPDATE_CACHE_BUST:-manual}
    restart: always
    ports:
      - "${WORDPRESS_HTTP_PORT:-7860}:${WORDPRESS_HTTP_PORT:-7860}"
    volumes:
      - ./wordpress:/var/www/html
```

## Multi-stage build

The builder stage installs build tools and dependencies:

- Rust / cargo
- PHP development environment with `php-config` / `phpize`
- clang
- libclang-dev
- build-essential
- pkg-config

The builder stage compiles this package from the resolved SQLite Database Integration source commit:

```text
packages/php-ext-wp-mysql-parser
```

The final runtime image does not keep Rust, cargo, clang, build-essential, or other compiler toolchains. It only copies the compiled extension:

```text
wp_mysql_parser.so
```

The extension is loaded through a PHP ini file:

```ini
extension=wp_mysql_parser.so
```

## Verify that the native parser is loaded

After the container starts, run:

```bash
docker exec <container-name> php -m | grep -qx wp_mysql_parser && echo "native parser loaded"
```

If it prints:

```text
native parser loaded
```

then the native `wp_mysql_parser` PHP extension is loaded.

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

Before upgrading this image or changing upstream source versions, always back up the full `./wordpress` directory.

## Self-check

After changing the image or configuration, run the self-check script to verify the basic runtime behavior.

On Linux, macOS, or WSL, run:

```bash
bash scripts/smoke-test.sh
```

On Windows PowerShell, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1
```

The script resolves the latest upstream versions, builds the image, and starts a temporary test container on `127.0.0.1:18080`. Inside the container, WordPress listens on port `7860`. The script checks that the WordPress installation page is reachable, verifies the SQLite integration files and database directory, confirms PHP has SQLite support, and checks:

```bash
php -m | grep -qx wp_mysql_parser
```

The temporary container is removed automatically when the test finishes.

## GHCR publishing

`.github/workflows/docker-ghcr.yml` now supports the `realtime-update` branch. On this branch, the workflow runs `scripts/resolve-latest-versions.sh` first and then publishes tags like:

```text
<wordpress-tag>-sqlite-<sqlite-short-sha>-native-parser
realtime-update
```

Note: GitHub Actions scheduled workflows only run from the default branch. To publish `realtime-update` automatically on a schedule, put the scheduler workflow on the default branch, or trigger this branch manually with `workflow_dispatch`.

## Articles

- [WordPress SQLite Docker image packaging details](https://soulteary.com/2024/04/21/wordpress-sqlite-docker-image-packaging-details.html)
- [WordPress farewell to MySQL: Docker SQLite WordPress](https://soulteary.com/2024/04/17/say-goodbye-to-mysql-docker-sqlite-wordpress.html)

![](.github/ready-to-use.jpg)
