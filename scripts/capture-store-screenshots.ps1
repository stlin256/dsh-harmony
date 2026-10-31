param(
  [string]$DevEcoHome = 'C:\Users\yjzlx\AppData\Local\Programs\Huawei\DevEcoStudio-26.0.0',
  [string]$HapPath = '',
  [string]$Device = '',
  [string]$OutputDir = '',
  [switch]$SkipBuild,
  [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $HapPath) {
  $HapPath = Join-Path $repo 'harmony\entry\build\store\outputs\store\entry-store-signed.hap'
}
if (-not $OutputDir) {
  $OutputDir = Join-Path $repo 'artifacts\store-screenshots'
}
$rawDir = Join-Path $OutputDir 'raw'
$finalDir = Join-Path $OutputDir 'final'
New-Item -ItemType Directory -Force -Path $rawDir, $finalDir | Out-Null

$hdc = Join-Path $DevEcoHome 'sdk\default\openharmony\toolchains\hdc.exe'
if (-not (Test-Path -LiteralPath $hdc)) {
  throw "HDC not found: $hdc"
}

function Get-ReadyDevice {
  $lines = & $hdc list targets -v
  $ready = @($lines | Where-Object {
    $_ -match '\tUSB\t(?:Ready|Connected)\t' -and $_ -notmatch '\tOffline\t'
  })
  if ($ready.Count -eq 0) {
    throw 'No unlocked USB device is ready. Connect the HarmonyOS device and enable USB debugging.'
  }
  return ($ready[0] -split "`t")[0]
}

if (-not $Device) {
  $Device = Get-ReadyDevice
}

$env:DEVECO_CLI_STUDIO_PATH = $DevEcoHome
if (-not $SkipBuild) {
  Push-Location (Join-Path $repo 'harmony')
  try {
    devecocli build --product store --build-mode release
    if ($LASTEXITCODE -ne 0) {
      throw "Store Release build failed: $LASTEXITCODE"
    }
  }
  finally {
    Pop-Location
  }
}
$hap = (Resolve-Path -LiteralPath $HapPath).Path

if (-not $SkipInstall) {
  & $hdc -t $Device install -r $hap
  if ($LASTEXITCODE -ne 0) {
    throw "HAP installation failed: $LASTEXITCODE"
  }
}

$bundle = 'io.github.stlin256.dshharmony'

function Capture([string]$fileName, [string]$screen, [string]$theme) {
  $path = Join-Path $rawDir $fileName
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  & $hdc -t $Device shell "aa force-stop $bundle" | Out-Null
  & $hdc -t $Device shell "aa start -a EntryAbility -b $bundle -m entry --ps storeShowcase true --ps showcaseScreen $screen --ps showcaseTheme $theme"
  if ($LASTEXITCODE -ne 0) {
    throw "Launch failed for $screen/$theme"
  }
  Start-Sleep -Seconds 4
  devecocli ui screenshot --device $Device --path $path
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $path)) {
    throw "Screenshot failed: $fileName"
  }
}

Capture '01-conversation-light.png' 'conversation' 'light'
Capture '02-process-light.png' 'process' 'light'
Capture '03-sidebar-light.png' 'sidebar' 'light'
Capture '04-browser-light.png' 'browser' 'light'
Capture '05-settings-light.png' 'settings' 'light'
Capture '06-conversation-dark.png' 'conversation' 'dark'
Capture '07-process-dark.png' 'process' 'dark'
Capture '08-sidebar-dark.png' 'sidebar' 'dark'
Capture '09-browser-dark.png' 'browser' 'dark'
Capture '10-settings-dark.png' 'settings' 'dark'

python (Join-Path $PSScriptRoot 'compose-store-screenshots.py') --raw $rawDir --out $finalDir
if ($LASTEXITCODE -ne 0) {
  throw "Screenshot composition failed: $LASTEXITCODE"
}

$manifest = [ordered]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  device = 'connected-device'
  bundleName = $bundle
  product = 'store'
  hap = 'harmony/entry/build/store/outputs/store/entry-store-signed.hap'
  rawDirectory = 'artifacts/store-screenshots/raw'
  finalDirectory = 'artifacts/store-screenshots/final'
  model = 'DeepSeek-V4-Pro'
  reasoningEffort = 'max'
  artifactCount = @(Get-ChildItem -LiteralPath $finalDir -Filter '*.png').Count
  appGalleryLandscapeCount = @(Get-ChildItem -LiteralPath (Join-Path $finalDir 'appgallery-landscape') -Filter '*.png').Count
  appGalleryPortraitCount = @(Get-ChildItem -LiteralPath (Join-Path $finalDir 'appgallery-portrait') -Filter '*.png').Count
}
$manifest |
  ConvertTo-Json -Depth 4 |
  Set-Content -LiteralPath (Join-Path $OutputDir 'manifest.json') -Encoding utf8

Get-ChildItem -LiteralPath $finalDir -Filter '*.png' |
  Select-Object FullName, Length, LastWriteTime
