param(
  [string]$DevEcoHome = $env:DEVECO_STUDIO_HOME,
  [ValidateSet('default','store')][string]$Product = 'default',
  [ValidateSet('debug','release')][string]$BuildMode = 'debug',
  [switch]$AssembleApp
)
$ErrorActionPreference = 'Stop'
if (-not $DevEcoHome) { throw 'Set DEVECO_STUDIO_HOME or pass -DevEcoHome.' }
$ide = (Resolve-Path -LiteralPath $DevEcoHome).Path
$project = (Resolve-Path (Join-Path $PSScriptRoot '../harmony')).Path
$profile = Join-Path $project 'build-profile.json5'
$manifest = Join-Path $project 'entry/src/main/module.json5'
$storeManifest = Join-Path $project 'variants/store/module.json5'
if (-not (Test-Path -LiteralPath $profile)) {
  Copy-Item -LiteralPath (Join-Path $project 'build-profile.example.json5') -Destination $profile
}
$restoreManifest = $null
if ($Product -eq 'store') {
  $restoreManifest = [IO.File]::ReadAllBytes($manifest)
  Copy-Item -LiteralPath $storeManifest -Destination $manifest -Force
}
$savedNode = $env:NODE_HOME
$savedJava = $env:JAVA_HOME
$savedSdk = $env:DEVECO_SDK_HOME
$savedCli = $env:DEVECO_CLI_STUDIO_PATH
$savedPath = $env:Path
Push-Location -LiteralPath $project
try {
  $env:NODE_HOME = Join-Path $ide 'tools/node'
  $env:JAVA_HOME = Join-Path $ide 'jbr'
  $env:DEVECO_SDK_HOME = Join-Path $ide 'sdk'
  $env:Path = "$env:NODE_HOME;$env:JAVA_HOME/bin;$savedPath"
  & (Join-Path $ide 'tools/ohpm/bin/ohpm.bat') install
  if ($LASTEXITCODE -ne 0) { throw 'ohpm install failed' }
  if ($AssembleApp) {
    $env:DEVECO_CLI_STUDIO_PATH = $ide
    & devecocli build --product $Product --build-mode $BuildMode
  } else {
    & (Join-Path $env:NODE_HOME 'node.exe') (Join-Path $ide 'tools/hvigor/bin/hvigorw.js') --mode module -p "product=$Product" -p "module=entry@$Product" -p "buildMode=$BuildMode" assembleHap --no-daemon
  }
  if ($LASTEXITCODE -ne 0) { throw "HarmonyOS build failed: $LASTEXITCODE" }
} finally {
  Pop-Location
  if ($null -ne $restoreManifest) {
    [IO.File]::WriteAllBytes($manifest, $restoreManifest)
  }
  $env:NODE_HOME = $savedNode
  $env:JAVA_HOME = $savedJava
  $env:DEVECO_SDK_HOME = $savedSdk
  $env:DEVECO_CLI_STUDIO_PATH = $savedCli
  $env:Path = $savedPath
}
