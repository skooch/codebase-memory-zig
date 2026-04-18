param(
    [switch]$FromSource,
    [string]$InstallDir,
    [switch]$SkipConfig,
    [string]$BaseUrl,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host "Usage: ./scripts/setup-windows.ps1 [-FromSource] [-InstallDir <path>] [-SkipConfig] [-BaseUrl <url-or-path>]"
    Write-Host ""
    Write-Host "Default behavior installs from the latest packaged release via ./install.ps1."
    Write-Host "Use -FromSource to build the current checkout with zig and install the local binary."
    exit 0
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir

if (-not $InstallDir) {
    if ($IsWindows) {
        $InstallDir = Join-Path $env:LOCALAPPDATA "Programs\cbm"
    } else {
        $InstallDir = Join-Path $HOME ".local/bin"
    }
}

if (-not $FromSource) {
    & (Join-Path $rootDir "install.ps1") -InstallDir $InstallDir -SkipConfig:$SkipConfig -BaseUrl $BaseUrl
    exit $LASTEXITCODE
}

$zig = Get-Command zig -ErrorAction SilentlyContinue
if (-not $zig) {
    throw "zig is required for -FromSource"
}

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("cbm-setup-" + [System.Guid]::NewGuid().ToString("N"))
$prefixDir = Join-Path $tmpRoot "prefix"
New-Item -ItemType Directory -Path $prefixDir -Force | Out-Null

try {
    Push-Location $rootDir
    & zig build release --prefix $prefixDir
    if ($LASTEXITCODE -ne 0) {
        throw "zig build release failed"
    }
    Pop-Location

    $binaryName = if ($IsWindows) { "cbm.exe" } else { "cbm" }
    $binaryPath = Join-Path (Join-Path $prefixDir "bin") $binaryName
    if (-not (Test-Path $binaryPath)) {
        throw "Release build did not produce $binaryName"
    }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $dest = Join-Path $InstallDir $binaryName
    Copy-Item -LiteralPath $binaryPath -Destination $dest -Force

    $version = & $dest --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Installed binary failed to run"
    }
    Write-Host "Installed from source: $version"

    if (-not $SkipConfig) {
        try {
            & $dest install -y
        } catch {
            Write-Warning "Agent configuration failed; run 'cbm install -y' manually"
        }
    }

    Write-Host "Done."
} finally {
    if (Get-Location) {
        try { Pop-Location } catch {}
    }
    Remove-Item -Recurse -Force $tmpRoot -ErrorAction SilentlyContinue
}
