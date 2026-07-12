$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$wallyPath = Join-Path $projectRoot "wally.toml"
$versionSourcePath = Join-Path $projectRoot "src\Version.luau"
$wallyToml = Get-Content -Raw -LiteralPath $wallyPath

if ($wallyToml -notmatch '(?m)^\s*version\s*=\s*"(?<version>\d+\.\d+\.\d+)"') {
	throw "wally.toml must contain a semver package version like version = `"2.0.0`"."
}

$version = $Matches.version
$source = "return `"$version`"`n"
[System.IO.File]::WriteAllText($versionSourcePath, $source, [System.Text.UTF8Encoding]::new($false))
Write-Output "Generated src/Version.luau for CodeKit v$version"
