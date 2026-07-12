$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot

Remove-Item -LiteralPath "$projectRoot\services.json" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$projectRoot\codekit-plugin.rbxm" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$projectRoot\codekit-plugin-dev.rbxm" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$projectRoot\build\codekit-plugin.rbxm" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$projectRoot\build\codekit-plugin-dev.rbxm" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$projectRoot\src\Version.luau" -Force -ErrorAction SilentlyContinue
