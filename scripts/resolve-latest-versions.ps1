param(
    [string]$Output = '',
    [ValidateSet('DotEnv', 'PowerShell', 'GitHubOutput')]
    [string]$Format = 'DotEnv'
)

$ErrorActionPreference = 'Stop'

$WordPressCoreApi = if ($env:WORDPRESS_CORE_API) { $env:WORDPRESS_CORE_API } else { 'https://api.wordpress.org/core/version-check/1.7/' }
$DockerWordPressLibraryUrl = if ($env:DOCKER_WORDPRESS_LIBRARY_URL) { $env:DOCKER_WORDPRESS_LIBRARY_URL } else { 'https://raw.githubusercontent.com/docker-library/official-images/master/library/wordpress' }
$SQLiteCommitsApi = if ($env:SQLITE_DATABASE_INTEGRATION_COMMITS_API) { $env:SQLITE_DATABASE_INTEGRATION_COMMITS_API } else { 'https://api.github.com/repos/WordPress/sqlite-database-integration/commits?per_page=1' }
$WordPressHttpPort = if ($env:WORDPRESS_HTTP_PORT) { $env:WORDPRESS_HTTP_PORT } else { '7860' }

function Convert-ToVersionTuple {
    param([string]$Value)
    $Parts = $Value.Split('.') | ForEach-Object { [int]$_ }
    while ($Parts.Count -lt 3) {
        $Parts += 0
    }
    return ,$Parts[0..2]
}

function Compare-VersionTuple {
    param([int[]]$Left, [int[]]$Right)
    for ($i = 0; $i -lt 3; $i++) {
        if ($Left[$i] -gt $Right[$i]) { return 1 }
        if ($Left[$i] -lt $Right[$i]) { return -1 }
    }
    return 0
}

$Core = Invoke-RestMethod -Uri $WordPressCoreApi
$Offers = @($Core.offers)
if ($Offers.Count -eq 0) {
    throw 'WordPress core API returned no offers'
}

$LatestOffer = $Offers | Where-Object { $_.response -eq 'upgrade' } | Select-Object -First 1
if (-not $LatestOffer) {
    $LatestOffer = $Offers[0]
}

$WordPressVersion = if ($LatestOffer.current) { [string]$LatestOffer.current } else { [string]$LatestOffer.version }
if (-not $WordPressVersion) {
    throw 'Could not resolve latest WordPress version'
}

$WordPressTuple = Convert-ToVersionTuple $WordPressVersion

$DockerLibrary = (Invoke-WebRequest -UseBasicParsing -Uri $DockerWordPressLibraryUrl).Content
$Tags = New-Object System.Collections.Generic.List[string]

foreach ($Line in ($DockerLibrary -split "`n")) {
    if ($Line.StartsWith('Tags:')) {
        foreach ($Tag in $Line.Substring(5).Split(',')) {
            $Trimmed = $Tag.Trim()
            if ($Trimmed) {
                $Tags.Add($Trimmed)
            }
        }
    }
}

$Candidates = New-Object System.Collections.Generic.List[object]

foreach ($Tag in $Tags) {
    $Match = [regex]::Match($Tag, '^(\d+(?:\.\d+){1,2})-php(\d+\.\d+)-apache$')
    if (-not $Match.Success) {
        continue
    }

    $TagWordPressVersion = $Match.Groups[1].Value
    $PhpVersion = $Match.Groups[2].Value

    if ((Compare-VersionTuple (Convert-ToVersionTuple $TagWordPressVersion) $WordPressTuple) -ne 0) {
        continue
    }

    $PhpParts = $PhpVersion.Split('.') | ForEach-Object { [int]$_ }
    $Specificity = $TagWordPressVersion.Split('.').Count

    $Candidates.Add([PSCustomObject]@{
        Tag = $Tag
        WordPressVersion = $TagWordPressVersion
        PhpVersion = $PhpVersion
        PhpMajor = $PhpParts[0]
        PhpMinor = $PhpParts[1]
        Specificity = $Specificity
    })
}

if ($Candidates.Count -eq 0) {
    throw "No official wordpress:*php*-apache Docker tag found for WordPress $WordPressVersion"
}

$Selected = $Candidates |
    Sort-Object -Property @{ Expression = 'PhpMajor'; Descending = $true },
                          @{ Expression = 'PhpMinor'; Descending = $true },
                          @{ Expression = 'Specificity'; Descending = $true },
                          @{ Expression = 'Tag'; Descending = $true } |
    Select-Object -First 1

$Headers = @{ Accept = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) {
    $Headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
}

$SQLiteData = Invoke-RestMethod -Uri $SQLiteCommitsApi -Headers $Headers
$SQLiteCommit = if ($SQLiteData -is [array]) { [string]$SQLiteData[0].sha } else { [string]$SQLiteData.sha }

if ($SQLiteCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'Could not resolve latest sqlite-database-integration commit SHA'
}

$Values = [ordered]@{
    WORDPRESS_VERSION = $WordPressVersion
    WORDPRESS_IMAGE = "wordpress:$($Selected.Tag)"
    WORDPRESS_PHP_VERSION = $Selected.PhpVersion
    SQLITE_DATABASE_INTEGRATION_COMMIT = $SQLiteCommit
    SQLITE_DATABASE_INTEGRATION_SHORT_COMMIT = $SQLiteCommit.Substring(0, 12)
    WORDPRESS_HTTP_PORT = $WordPressHttpPort
    UPDATE_CACHE_BUST = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
}

$Lines = foreach ($Entry in $Values.GetEnumerator()) {
    if ($Format -eq 'PowerShell') {
        "`$env:$($Entry.Key) = '$($Entry.Value)'"
    } else {
        "$($Entry.Key)=$($Entry.Value)"
    }
}

if ($Output) {
    $Lines | Set-Content -Encoding UTF8 -Path $Output
} else {
    $Lines
}
