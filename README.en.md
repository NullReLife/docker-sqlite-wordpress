# Docker SQLite WordPress Native Parser

[简体中文](README.md) | English

![](.github/about.jpg)

This is the **native-parser performance-optimized variant** of WordPress + SQLite Database Integration. It runs WordPress without MySQL, MariaDB, or PostgreSQL, and additionally compiles and loads the SQLite Database Integration project's native PHP extension, `wp_mysql_parser`.

> `wp_mysql_parser` is a performance optimization component. It is not required for SQLite support. Without this native extension, SQLite Database Integration can still run normally with the pure PHP parser. The stable pure PHP version stays on the `main` branch; this branch is for native parser experiments and performance optimization.

This image is based on the official WordPress Docker image and installs SQLite Database Integration as an MU plugin. The SQLite drop-in is copied to `wp-content/db.php`, and WordPress stores its database in a SQLite file.

## Branches

- `main`: stable pure PHP version, using the WordPress.org `sqlite-database-integration` 2.2.23 release package.
- `native-parser`: performance-optimized version, using a multi-stage build to compile and load the native `wp_mysql_parser` PHP extension.

If the native parser build fails, it does not affect the `main` branch.

## Versions

- WordPress: 7.0.0
- PHP: 8.5
- Base image: `wordpress:7.0.0-php8.5-apache`
- SQLite Database Integration source commit: `e5513936c800f14b6795e7fce71505afad331b11`
- Native extension: `wp_mysql_parser`
- Container listen port: 7860

All versions are pinned for reproducible builds. This branch does not use `wordpress:latest`, floating WordPress tags, `trunk`, or `latest` source references.

## Why this branch does not use the 2.2.23 release package

The WordPress.org `sqlite-database-integration` 2.2.23 release package is suitable for the pure PHP version, but it does not include the `packages/php-ext-wp-mysql-parser` native extension source.

Therefore, the `native-parser` branch uses this fixed upstream source commit:

```text
e5513936c800f14b6795e7fce71505afad331b11
```

That commit includes the optional Rust-based native MySQL parser extension. Its source lives in:

```text
packages/php-ext-wp-mysql-parser
```

## Build

Build the native-parser image locally:

```bash
docker build \
  --build-arg WORDPRESS_IMAGE=wordpress:7.0.0-php8.5-apache \
  --build-arg SQLITE_DATABASE_INTEGRATION_COMMIT=e5513936c800f14b6795e7fce71505afad331b11 \
  --build-arg WORDPRESS_HTTP_PORT=7860 \
  -t sqlite-wordpress:7.0.0-php8.5-apache-native-parser \
  .
```

## Multi-stage build

The builder stage installs build tools and dependencies:

- Rust / cargo
- PHP development environment with `php-config` / `phpize`
- clang
- libclang-dev
- build-essential
- pkg-config

The builder stage compiles this package from the pinned SQLite Database Integration source:

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

## Run with Docker Compose

Start WordPress:

```bash
docker compose up -d
```

Then open:

```text
http://localhost:7860
```

The WordPress installation page should appear.

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
        SQLITE_DATABASE_INTEGRATION_COMMIT: e5513936c800f14b6795e7fce71505afad331b11
        WORDPRESS_HTTP_PORT: 7860
    restart: always
    ports:
      - "7860:7860"
    volumes:
      - ./wordpress:/var/www/html
```

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

The script builds the image and starts a temporary test container on `127.0.0.1:18080`. Inside the container, WordPress listens on port `7860`. The script checks that the WordPress installation page is reachable, verifies the SQLite integration files and database directory, confirms PHP has SQLite support, and checks:

```bash
php -m | grep -qx wp_mysql_parser
```

The temporary container is removed automatically when the test finishes.

If you see an error like `/bin/bash: No such file or directory` in Windows `cmd` or PowerShell, it means Bash is not available in the current environment. Use the PowerShell self-check command above, or run the Bash script inside WSL.

## Articles

- [WordPress SQLite Docker image packaging details](https://soulteary.com/2024/04/21/wordpress-sqlite-docker-image-packaging-details.html)
- [WordPress farewell to MySQL: Docker SQLite WordPress](https://soulteary.com/2024/04/17/say-goodbye-to-mysql-docker-sqlite-wordpress.html)

![](.github/ready-to-use.jpg)
