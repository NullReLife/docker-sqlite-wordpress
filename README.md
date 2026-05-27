# Docker SQLite WordPress Native Parser

简体中文 | [English](README.en.md)

![](.github/about.jpg)

这是一个 WordPress + SQLite Database Integration 的 **native-parser 性能优化版本**，可以在不依赖 MySQL、MariaDB 或 PostgreSQL 的情况下运行 WordPress，并额外编译、加载 SQLite Database Integration 项目的 `wp_mysql_parser` 原生 PHP 扩展。

> `wp_mysql_parser` 是性能优化组件，不是 SQLite 运行必需组件。没有这个原生扩展时，SQLite Database Integration 仍可以使用纯 PHP parser 正常运行。稳定的纯 PHP 版本保留在 `main` 分支；本分支用于原生 parser 实验和性能优化。

该镜像基于官方 WordPress Docker 镜像构建，并将 SQLite Database Integration 插件安装为 MU 插件。SQLite drop-in 文件会被复制为 `wp-content/db.php`，WordPress 会将数据库保存为 SQLite 文件。

## 分支说明

- `main`：稳定纯 PHP 版本，使用 WordPress.org 发布包 `sqlite-database-integration` 2.2.23。
- `native-parser`：性能优化版本，使用多阶段构建编译并加载 `wp_mysql_parser` 原生 PHP 扩展。

如果 native parser 构建失败，不会影响 `main` 分支。

## 版本

- WordPress: 7.0.0
- PHP: 8.5
- 基础镜像：`wordpress:7.0.0-php8.5-apache`
- SQLite Database Integration 源码 commit：`c43113d9e267462a12ecd2b04a73c3b62e5d2c7b`
- 原生扩展：`wp_mysql_parser`
- 容器监听端口：7860

所有版本都已固定，便于可复现构建。本分支不会使用 `wordpress:latest`、浮动 WordPress 标签、`trunk` 或 `latest` 源码引用。

## 为什么不用 2.2.23 发布包

`sqlite-database-integration` 2.2.23 的 WordPress.org 发布包适合纯 PHP 版本，但不包含 `packages/php-ext-wp-mysql-parser` 原生扩展源码。

因此，`native-parser` 分支使用固定的上游源码 commit：

```text
c43113d9e267462a12ecd2b04a73c3b62e5d2c7b
```

这个 commit 引入了可选的 Rust 原生 MySQL parser 扩展，源码位于：

```text
packages/php-ext-wp-mysql-parser
```

## 构建

在本地构建 native-parser 镜像：

```bash
docker build \
  --build-arg WORDPRESS_IMAGE=wordpress:7.0.0-php8.5-apache \
  --build-arg SQLITE_DATABASE_INTEGRATION_COMMIT=c43113d9e267462a12ecd2b04a73c3b62e5d2c7b \
  --build-arg WORDPRESS_HTTP_PORT=7860 \
  -t sqlite-wordpress:7.0.0-php8.5-apache-native-parser \
  .
```

## 多阶段构建说明

builder 阶段会安装构建工具和依赖：

- Rust / cargo
- PHP 开发环境中的 `php-config` / `phpize`
- clang
- libclang-dev
- build-essential
- pkg-config

builder 阶段会从固定 commit 的 SQLite Database Integration 源码中编译：

```text
packages/php-ext-wp-mysql-parser
```

最终运行镜像不会保留 Rust、cargo、clang、build-essential 等编译工具，只会复制编译好的：

```text
wp_mysql_parser.so
```

并通过 PHP ini 加载：

```ini
extension=wp_mysql_parser.so
```

## 使用 Docker Compose 启动

启动 WordPress：

```bash
docker compose up -d
```

然后在浏览器中打开：

```text
http://localhost:7860
```

你应该可以看到 WordPress 安装页面。

## 验证 native parser 是否加载

运行容器后，可以执行：

```bash
docker exec <container-name> php -m | grep -qx wp_mysql_parser && echo "native parser loaded"
```

如果输出：

```text
native parser loaded
```

说明 `wp_mysql_parser` 原生 PHP 扩展已经加载。

## 数据目录

运行时的 WordPress 文件保存在：

```text
./wordpress
```

SQLite 数据库文件位于 WordPress 数据目录中的：

```text
wp-content/database/.ht.sqlite
```

使用默认 Compose 挂载时，对应宿主机路径为：

```text
./wordpress/wp-content/database/.ht.sqlite
```

升级该镜像或修改插件版本前，请务必先备份完整的 `./wordpress` 目录。

## Docker Compose 配置

本项目只使用一个 `wordpress` 服务，不需要额外的数据库容器：

```yaml
services:
  wordpress:
    build:
      context: .
      args:
        WORDPRESS_IMAGE: wordpress:7.0.0-php8.5-apache
        SQLITE_DATABASE_INTEGRATION_COMMIT: c43113d9e267462a12ecd2b04a73c3b62e5d2c7b
        WORDPRESS_HTTP_PORT: 7860
    restart: always
    ports:
      - "7860:7860"
    volumes:
      - ./wordpress:/var/www/html
```

## 快速自检

修改镜像或配置后，可以运行快速自检脚本确认基础功能是否正常。

在 Linux、macOS 或 WSL 中运行：

```bash
bash scripts/smoke-test.sh
```

在 Windows PowerShell 中运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1
```

这个脚本会自动构建镜像，并在本机 `127.0.0.1:18080` 启动一个临时测试容器。容器内部的 WordPress 服务监听 `7860` 端口，脚本会检查 WordPress 安装页面是否可以访问，确认 SQLite 集成文件和数据库目录是否存在，确认 PHP 已启用 SQLite 支持，并检查：

```bash
php -m | grep -qx wp_mysql_parser
```

测试结束后，临时容器会被自动删除。

如果你在 Windows 的 `cmd` 或 PowerShell 中看到类似 `/bin/bash: No such file or directory` 的错误，说明当前环境没有可用的 Bash。请改用上面的 PowerShell 自检命令，或者在 WSL 里运行 Bash 版脚本。

## 相关文章

- [WordPress SQLite Docker image packaging details](https://soulteary.com/2024/04/21/wordpress-sqlite-docker-image-packaging-details.html)
- [WordPress farewell to MySQL: Docker SQLite WordPress](https://soulteary.com/2024/04/17/say-goodbye-to-mysql-docker-sqlite-wordpress.html)

![](.github/ready-to-use.jpg)
