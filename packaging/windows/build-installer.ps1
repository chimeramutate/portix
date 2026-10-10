<#
.SYNOPSIS
  Builds the Portix setup .exe from a Flutter Windows release folder.

.DESCRIPTION
  Expects `flutter build windows --release` to have run and portix_serv.dll
  and portix_rdp.dll to be copied into the release folder. Adds the VC++
  runtime DLLs (app-local, so a clean Windows needs no separate VC++
  Redistributable) and runs makensis on portix.nsi.

.EXAMPLE
  ./packaging/windows/build-installer.ps1 -Version 1.2.3
#>
param(
  [Parameter(Mandatory = $true)] [string] $Version,
  [string] $ReleaseName = $Version,
  [string] $SourceDir = "portix_app/build/windows/x64/runner/Release",
  [string] $OutFile = "portix-windows-$ReleaseName.exe"
)

$ErrorActionPreference = "Stop"

$source = (Resolve-Path $SourceDir).Path
foreach ($file in @("portix.exe", "portix_serv.dll", "portix_rdp.dll")) {
  if (-not (Test-Path (Join-Path $source $file))) {
    throw "Missing $file in $source"
  }
}

# Flutter and the Rust libraries are built with MSVC and need its runtime.
$system32 = Join-Path $env:SystemRoot "System32"
foreach ($dll in @("vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll")) {
  $from = Join-Path $system32 $dll
  if (-not (Test-Path $from)) { throw "VC++ runtime not found: $from" }
  Copy-Item $from -Destination $source -Force
}

# Windows file versions are four numbers; drop suffixes like -beta.1 and
# pad 1.2 to 1.2.0.0.
$numericVersion = ($Version -replace '^v', '') -replace '[^0-9.].*$', ''
if ($numericVersion -notmatch '^\d+(\.\d+){0,3}$') {
  throw "Version must start with a number like 1.2.3, got '$Version'"
}
$parts = @($numericVersion.Split('.'))
while ($parts.Count -lt 4) { $parts += '0' }
$productVersion = $parts -join '.'

$makensis = (Get-Command makensis -ErrorAction SilentlyContinue).Source
if (-not $makensis) { $makensis = "${env:ProgramFiles(x86)}\NSIS\makensis.exe" }
if (-not (Test-Path $makensis)) { throw "makensis not found; install NSIS" }

$out = [System.IO.Path]::GetFullPath($OutFile)
& $makensis `
  "/DAPP_VERSION=$numericVersion" `
  "/DPRODUCT_VERSION=$productVersion" `
  "/DSOURCE_DIR=$source" `
  "/DOUT_FILE=$out" `
  (Join-Path $PSScriptRoot "portix.nsi")
if ($LASTEXITCODE -ne 0) { throw "makensis failed ($LASTEXITCODE)" }

Get-Item $out | Format-List Name, Length, FullName
