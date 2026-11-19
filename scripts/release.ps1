<#
.SYNOPSIS
  Builds a signed release APK and publishes it as a GitHub release.
.EXAMPLE
  .\scripts\release.ps1 -Version 1.0.0
  .\scripts\release.ps1 -Version 1.0.0 -DryRun   # everything except commit/push/release
#>
param(
  [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Repo = 'Smoogi/Meal-planner'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $Root
$env:PATH = "$env:LOCALAPPDATA\Programs\gh\bin;$env:PATH"

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# Run a native command; judge success by exit code only (git/gradle write progress to stderr).
function Run {
  param([string]$Exe, [string[]]$Arguments)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $Exe @Arguments 2>&1 | ForEach-Object { Write-Host "$_" }
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  if ($code -ne 0) { Fail "'$Exe $($Arguments -join ' ')' failed (exit $code)" }
}
function Capture {
  param([string]$Exe, [string[]]$Arguments)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & $Exe @Arguments 2>$null
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  return @{ Code = $code; Out = ($out -join "`n").Trim() }
}

$tag = "v$Version"

Step 'Checking git state'
if ((Capture git @('rev-parse', '--abbrev-ref', 'HEAD')).Out -ne 'main') { Fail 'Must be on branch main.' }
if ((Capture git @('status', '--porcelain')).Out) { Fail 'Working tree is not clean. Commit or stash changes first.' }
$remote = (Capture git @('remote', 'get-url', 'origin')).Out
if ($remote -notmatch [regex]::Escape($Repo)) { Fail "origin is '$remote', expected $Repo." }
Run git @('fetch', 'origin', 'main')
$behind = (Capture git @('rev-list', '--count', 'HEAD..origin/main')).Out
if ($behind -ne '0') { Fail "Local main is $behind commit(s) behind origin/main. Pull first." }

Step 'Checking GitHub CLI'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail 'gh not found.' }
if ((Capture gh @('auth', 'status')).Code -ne 0) { Fail 'gh is not authenticated. Run: gh auth login' }
if ((Capture gh @('release', 'view', $tag, '--repo', $Repo)).Code -eq 0) { Fail "GitHub release $tag already exists." }
if ((Capture git @('rev-parse', '-q', '--verify', "refs/tags/$tag")).Code -eq 0) { Fail "Local tag $tag already exists." }

Step 'Checking Flutter / Android toolchain'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { Fail 'flutter not found on PATH.' }
if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
  $candidates = @(
    "$env:ProgramFiles\Android\Android Studio\jbr",
    "$env:LOCALAPPDATA\Programs\Android Studio\jbr"
  )
  $jbr = $candidates | Where-Object { Test-Path "$_\bin\java.exe" } | Select-Object -First 1
  if (-not $jbr) { Fail 'JAVA_HOME not set and Android Studio JBR not found.' }
  $env:JAVA_HOME = $jbr
}
Write-Host "JAVA_HOME=$env:JAVA_HOME"

Step 'Validating release signing'
$keyProps = Join-Path $Root 'android\key.properties'
if (-not (Test-Path $keyProps)) { Fail 'android/key.properties missing. See CLAUDE.md > Android signing.' }
$props = @{}
Get-Content $keyProps | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
  $k, $v = $_ -split '=', 2; $props[$k.Trim()] = $v.Trim()
}
foreach ($k in 'storeFile', 'storePassword', 'keyAlias', 'keyPassword') {
  if (-not $props[$k]) { Fail "key.properties is missing '$k'." }
}
if (-not (Test-Path $props['storeFile'])) { Fail "Keystore not found: $($props['storeFile'])" }

Step 'flutter pub get / analyze / test'
Run flutter @('pub', 'get')
Run flutter @('analyze')
Run flutter @('test')

Step 'Computing version'
$pubspec = Join-Path $Root 'pubspec.yaml'
$text = Get-Content $pubspec -Raw
if ($text -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { Fail 'pubspec.yaml version must look like X.Y.Z+N' }
$curName = $Matches[1]; $curCode = [int]$Matches[2]
if ([version]$Version -le [version]$curName -and $curName -ne '1.0.0') {
  Fail "Requested $Version is not greater than current $curName."
}
$newCode = $curCode + 1
Write-Host "versionName $curName -> $Version ; versionCode $curCode -> $newCode"

if ($DryRun) { Write-Host 'DryRun: stopping before any file changes or publishing.' -ForegroundColor Yellow; exit 0 }

$answer = Read-Host "Publish Meal Planner $Version (versionCode $newCode) to $Repo? Type the version to confirm"
if ($answer -ne $Version) { Fail 'Not confirmed. Nothing was changed.' }

Step 'Updating pubspec.yaml'
$updated = $text -replace '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', "version: $Version+$newCode"
[IO.File]::WriteAllText($pubspec, $updated)

Step 'Building signed release APK'
Run flutter @('build', 'apk', '--release')
$built = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $built)) { Fail 'APK was not produced.' }

$out = Join-Path $Root 'release-out'
New-Item -ItemType Directory -Force $out | Out-Null
$apk = Join-Path $out "meal-planner-$Version.apk"
Copy-Item $built $apk -Force
$hash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
$sha = "$apk.sha256"
[IO.File]::WriteAllText($sha, "$hash  meal-planner-$Version.apk`n")

Step 'Generating release notes'
$lastTag = (Capture git @('describe', '--tags', '--abbrev=0')).Out
$range = if ($lastTag) { "$lastTag..HEAD" } else { 'HEAD' }
$log = (Capture git @('log', $range, '--pretty=format:- %s')).Out
$notes = Join-Path $out 'notes.md'
@"
## Meal Planner $Version

$log

**SHA-256:** ``$hash``
"@ | Set-Content $notes -Encoding utf8

Step 'Committing and pushing'
Run git @('add', 'pubspec.yaml')
Run git @('commit', '-m', "Release $Version")
Run git @('push', 'origin', 'main')
$localHead = (Capture git @('rev-parse', 'HEAD')).Out
$remoteHead = (Capture git @('rev-parse', 'origin/main')).Out
if ($localHead -ne $remoteHead) { Fail 'Push did not update origin/main.' }

Step 'Creating GitHub release'
Run gh @('release', 'create', $tag, $apk, $sha, '--repo', $Repo,
  '--title', "Meal Planner $Version", '--notes-file', $notes, '--target', 'main')

Step 'Verifying release'
$v = Capture gh @('release', 'view', $tag, '--repo', $Repo, '--json', 'assets', '--jq', '.assets[].name')
if ($v.Code -ne 0 -or $v.Out -notmatch "meal-planner-$([regex]::Escape($Version)).apk") { Fail 'Release not found or APK asset missing on GitHub.' }
Write-Host "SUCCESS: https://github.com/$Repo/releases/tag/$tag" -ForegroundColor Green
