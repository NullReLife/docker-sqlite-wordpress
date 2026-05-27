$ErrorActionPreference = 'Stop'

$RootDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$ImageName = 'sqlite-wordpress-native-parser-smoke:local'
$ContainerName = 'sqlite-wordpress-native-parser-smoke-test'
$HostPort = '18080'
$ContainerPort = '7860'
$SQLiteDatabaseIntegrationCommit = 'c43113d9e267462a12ecd2b04a73c3b62e5d2c7b'
$TestVolume = Join-Path ([System.IO.Path]::GetTempPath()) ("sqlite-wordpress-native-parser-smoke-" + [System.Guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $TestVolume | Out-Null

function Cleanup {
    docker rm -f $ContainerName *> $null
    Remove-Item -Recurse -Force $TestVolume -ErrorAction SilentlyContinue
}

try {
    Set-Location $RootDir

    docker build `
        --build-arg WORDPRESS_IMAGE=wordpress:7.0.0-php8.5-apache `
        --build-arg SQLITE_DATABASE_INTEGRATION_COMMIT=$SQLiteDatabaseIntegrationCommit `
        --build-arg WORDPRESS_HTTP_PORT=$ContainerPort `
        -t $ImageName `
        .

    docker rm -f $ContainerName *> $null

    docker run -d `
        --name $ContainerName `
        -p "${HostPort}:${ContainerPort}" `
        -v "${TestVolume}:/var/www/html" `
        $ImageName | Out-Null

    $Ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:${HostPort}/wp-admin/install.php" | Out-Null
            $Ready = $true
            break
        } catch {
            Start-Sleep -Seconds 1
        }
    }

    if (-not $Ready) {
        throw "WordPress install page is not reachable at http://127.0.0.1:${HostPort}/wp-admin/install.php"
    }

    docker exec $ContainerName test -f /var/www/html/wp-content/db.php
    docker exec $ContainerName test -d /var/www/html/wp-content/mu-plugins/sqlite-database-integration
    docker exec $ContainerName test -d /var/www/html/wp-content/database
    docker exec $ContainerName sh -c "php -m | grep -Eiq '^(sqlite3|pdo_sqlite)$'"
    docker exec $ContainerName sh -c "php -m | grep -qx wp_mysql_parser"

    Write-Host 'Native parser self-check passed.'
} finally {
    Cleanup
}
