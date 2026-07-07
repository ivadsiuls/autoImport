$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$luneCommand = Get-Command lune -ErrorAction SilentlyContinue
$rojoCommand = Get-Command rojo -ErrorAction SilentlyContinue
$lune = if ($null -eq $luneCommand) { Join-Path $env:USERPROFILE ".rokit\bin\lune.exe" } else { $luneCommand.Source }
$rojo = if ($null -eq $rojoCommand) { Join-Path $env:USERPROFILE ".rokit\bin\rojo.exe" } else { $rojoCommand.Source }
if (-not (Test-Path $lune)) {
	throw "Lune was not found in PATH or the Rokit bin directory."
}
if (-not (Test-Path $rojo)) {
	throw "Rojo was not found in PATH or the Rokit bin directory."
}

& "$PSScriptRoot\clean.ps1"
New-Item -ItemType Directory -Path "$projectRoot\build" -Force | Out-Null

Push-Location $projectRoot
try {
	& $lune run scripts/dump-services.luau
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}

	& $rojo build -o build/import-plugin.rbxm default.project.json
	exit $LASTEXITCODE
} finally {
	Pop-Location
}
