<#
  ZAM installer — Windows

      irm https://zam-os.org/install.ps1 | iex

  Installs the ZAM desktop app (right build for your CPU) and the `zam` CLI.
  Fetching with Invoke-WebRequest instead of a browser avoids the Mark-of-the-Web
  that triggers SmartScreen; the script also clears it defensively (Unblock-File)
  and installs silently and per-user (no admin / UAC prompt).

  Options — set as environment variables before piping, e.g.:
      $env:ZAM_DRY_RUN=1;  irm https://zam-os.org/install.ps1 | iex

      ZAM_VERSION=0.16.1   pin a version
      ZAM_SKIP_APP=1       skip the desktop app
      ZAM_SKIP_CLI=1       skip the `zam` CLI
      ZAM_DRY_RUN=1        print actions, do nothing
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # faster Invoke-WebRequest downloads

$Repo        = 'zam-os/zam'
$ReleasesUrl = "https://github.com/$Repo/releases"
$DryRun      = $env:ZAM_DRY_RUN -eq '1'

function Say  ($m) { Write-Host "zam " -NoNewline -ForegroundColor Cyan; Write-Host $m }
function Info ($m) { Write-Host "  $m" -ForegroundColor DarkGray }
function Ok   ($m) { Write-Host "  " -NoNewline; Write-Host "OK " -NoNewline -ForegroundColor Green; Write-Host $m }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "zam: $m" -ForegroundColor Red; exit 1 }
function Run  ([scriptblock]$b, $desc) {
  if ($DryRun) { Info "would run: $desc"; return }
  & $b
}

function Resolve-Version {
  if ($env:ZAM_VERSION) { return ($env:ZAM_VERSION -replace '^v','') }
  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
      -Headers @{ 'User-Agent' = 'zam-installer' }
    return ($rel.tag_name -replace '^v','')
  } catch {
    Die "could not resolve the latest version (GitHub API unreachable or rate-limited). Retry, or set `$env:ZAM_VERSION."
  }
}

function Get-Arch {
  $a = $env:PROCESSOR_ARCHITEW6432
  if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
  switch ($a) {
    'AMD64' { 'x64' }
    'ARM64' { 'arm64' }
    'x86'   { Die "32-bit Windows is not supported. See $ReleasesUrl" }
    default { Die "unknown CPU architecture '$a'. See $ReleasesUrl" }
  }
}

function Install-App ($version, $arch) {
  $asset = "ZAM_${version}_${arch}-setup.exe"
  $url   = "$ReleasesUrl/download/v$version/$asset"
  $dest  = Join-Path $env:TEMP $asset
  Info "downloading $asset"
  if ($DryRun) { Info "would fetch: $url"; Info "would run: $asset /S"; Ok "(dry run) app step complete"; return }
  try { Invoke-WebRequest -Uri $url -OutFile $dest -Headers @{ 'User-Agent' = 'zam-installer' } }
  catch { Die "download failed: $url" }
  Unblock-File -Path $dest   # clear Mark-of-the-Web so SmartScreen stays quiet
  Info "installing silently (per-user, no admin needed)"
  $p = Start-Process -FilePath $dest -ArgumentList '/S' -Wait -PassThru
  if ($p.ExitCode -ne 0) { Die "installer exited with code $($p.ExitCode)" }
  Remove-Item $dest -ErrorAction SilentlyContinue
  Ok "ZAM desktop app installed"
}

function Install-Cli ($version) {
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Warn "npm not found — skipping the ``zam`` CLI."
    Warn "Install Node.js 22+ from https://nodejs.org then run: npm install -g zam-core@$version"
    return
  }
  $nodeMajor = 0
  try { $nodeMajor = [int]((node -p 'process.versions.node.split(".")[0]') 2>$null) } catch {}
  if ($nodeMajor -lt 22) {
    Warn "Node.js 22+ required for the CLI (found v$nodeMajor). Upgrade at https://nodejs.org, then: npm install -g zam-core@$version"
    return
  }
  Info "installing the ``zam`` CLI (zam-core@$version)"
  Run { npm install -g "zam-core@$version" } "npm install -g zam-core@$version"
  Ok "``zam`` CLI installed"
}

# ---------- main ----------
Say "installer"
$version = Resolve-Version
$arch    = Get-Arch
Info "target version: v$version   (Windows $arch)"

if ($env:ZAM_SKIP_APP -ne '1') { Install-App $version $arch } else { Info "skipping desktop app (ZAM_SKIP_APP)" }
if ($env:ZAM_SKIP_CLI -ne '1') { Install-Cli $version }        else { Info "skipping CLI (ZAM_SKIP_CLI)" }

Write-Host ""
if ($DryRun) {
  Ok "done (dry run)"
} elseif (Get-Command zam -ErrorAction SilentlyContinue) {
  Ok ("done — " + (zam --version 2>$null))
} else {
  Ok "done"
  Info "open a new terminal so PATH picks up ``zam``, then run: zam init"
}
