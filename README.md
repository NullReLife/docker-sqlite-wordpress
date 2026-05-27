# Docker SQLite WordPress

简体中文 | [English](README.en.md)

![](.github/about.jpg)

这是一个 WordPress + SQLite Database Integration 镜像，可以在不依赖 MySQL、MariaDB 或 PostgreSQL 的情况下运行 WordPress。

该镜像基于官方 WordPress Docker 镜像构建，并将 WordPress SQLite Database Integration 插件安装为 MU 插件。SQLite drop-in 文件会被复制为 `wp-content/db.php`，WordPress 会将数据库保存为 SQLite 文件。

## 版本

- WordPress: 7.0.0
- PHP: 8.5
- SQLite Database Integration: 2.2.23
- 基础镜像：`wordpress:7.0.0-php8.5-apache`

所有版本都已固定，便于可复现构建。本项目不会使用 `wordpress:latest`、浮动 WordPress 标签或 SQLite Database Integration 的 RC 候选版本。

## 构建

在本地构建 Docker 镜像：

```bash
docker build \
  --build-arg WORDPRESS_IMAGE=wordpress:7.0.0-php8.5-apache \
  --build-arg SQLITE_DATABASE_INTEGRATION_VERSION=2.2.23 \
  -t sqlite-wordpress:7.0.0-php8.5-apache-sqlite-2.2.23 \
  .
```

## 使用 Docker Compose 启动

启动 WordPress：

```bash
docker compose up -d
```

然后在浏览器中打开：

```text
http://localhost:8080
```

你应该可以看到 WordPress 安装页面。

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
        SQLITE_DATABASE_INTEGRATION_VERSION: 2.2.23
    restart: always
    ports:
      - "8080:80"
    volumes:
      - ./wordpress:/var/www/html
```

## 冒烟测试

修改后可以运行冒烟测试：

```bash
bash scripts/smoke-test.sh
```

该测试会构建镜像，在 `127.0.0.1:18080` 启动一个临时容器，检查 `wp-admin/install.php` 是否可访问，验证 SQLite 集成文件和数据库目录是否存在，确认 PHP 已启用 SQLite 支持，并在测试结束后自动删除测试容器。

## 相关文章

- [WordPress SQLite Docker image packaging details](https://soulteary.com/2024/04/21/wordpress-sqlite-docker-image-packaging-details.html)
- [WordPress farewell to MySQL: Docker SQLite WordPress](https://soulteary.com/2024/04/17/say-goodbye-to-mysql-docker-sqlite-wordpress.html)

![](.github/ready-to-use.jpg)
