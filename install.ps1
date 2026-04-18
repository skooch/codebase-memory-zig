param(
    [string]$InstallDir,
    [switch]$SkipConfig,
    [string]$BaseUrl,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$Repo = "skooch/codebase-memory-zig"

if ($Help) {
    Write-Host "Usage: ./install.ps1 [-InstallDir <path>] [-SkipConfig] [-BaseUrl <url-or-path>]"
    Write-Host ""
    Write-Host "Downloads a packaged cbm release archive, verifies checksums when available,"
    Write-Host "installs the binary, and optionally runs 'cbm install -y'."
    exit 0
}

function Get-DefaultInstallDir {
    if ($IsWindows) {
        return Join-Path $env:LOCALAPPDATA "Programs\cbm"
    }
    return Join-Path $HOME ".local/bin"
}

function Get-ArchiveInfo {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    if ($IsWindows) {
        return @{
            Archive = "cbm-windows-amd64.zip"
            Binary = "cbm.exe"
            ArchiveType = "zip"
        }
    }
    if ($IsMacOS) {
        if ($arch -eq "arm64") {
            return @{ Archive = "cbm-darwin-arm64.tar.gz"; Binary = "cbm"; ArchiveType = "tar.gz" }
        }
        return @{ Archive = "cbm-darwin-amd64.tar.gz"; Binary = "cbm"; ArchiveType = "tar.gz" }
    }
    if ($IsLinux) {
        if ($arch -eq "arm64") {
            return @{ Archive = "cbm-linux-arm64.tar.gz"; Binary = "cbm"; ArchiveType = "tar.gz" }
        }
        return @{ Archive = "cbm-linux-amd64.tar.gz"; Binary = "cbm"; ArchiveType = "tar.gz" }
    }
    throw "Unsupported platform"
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-BaseUrl {
    param([string]$Value)
    if ($Value) {
        return $Value.TrimEnd('/', '\')
    }
    return "https://github.com/$Repo/releases/latest/download"
}

function Copy-Or-Download {
    param(
        [string]$Base,
        [string]$Name,
        [string]$OutputPath
    )

    if ($Base.StartsWith("file://")) {
        $uri = [System.Uri]::new(($Base.TrimEnd('/') + "/" + $Name))
        Copy-Item -LiteralPath $uri.LocalPath -Destination $OutputPath -Force
        return
    }

    if (Test-Path -LiteralPath $Base) {
        Copy-Item -LiteralPath (Join-Path $Base $Name) -Destination $OutputPath -Force
        return
    }

    Invoke-WebRequest -Uri ($Base.TrimEnd('/') + "/" + $Name) -OutFile $OutputPath -UseBasicParsing
}

if (-not $InstallDir) {
    $InstallDir = Get-DefaultInstallDir
}

$BaseUrl = Resolve-BaseUrl $BaseUrl
$archiveInfo = Get-ArchiveInfo
$archiveName = $archiveInfo.Archive
$binaryName = $archiveInfo.Binary
$archiveType = $archiveInfo.ArchiveType

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cbm-install-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

try {
    $archivePath = Join-Path $tmpDir $archiveName
    Write-Host "Downloading $archiveName..."
    Copy-Or-Download -Base $BaseUrl -Name $archiveName -OutputPath $archivePath

    $checksumsPath = Join-Path $tmpDir "checksums.txt"
    try {
        Copy-Or-Download -Base $BaseUrl -Name "checksums.txt" -OutputPath $checksumsPath
    } catch {
        $checksumsPath = $null
    }

    if ($checksumsPath -and (Test-Path $checksumsPath)) {
        $line = Get-Content $checksumsPath | Where-Object { $_ -match ("  " + [regex]::Escape($archiveName) + "$") }
        if ($line) {
            $expected = ($line -split '\s+')[0].ToLowerInvariant()
            $actual = Get-Sha256 $archivePath
            if ($expected -ne $actual) {
                throw "Checksum mismatch for $archiveName"
            }
            Write-Host "Checksum verified."
        }
    }

    if ($archiveType -eq "zip") {
        Expand-Archive -Path $archivePath -DestinationPath $tmpDir -Force
    } else {
        & tar -xzf $archivePath -C $tmpDir
        if ($LASTEXITCODE -ne 0) {
            throw "tar extraction failed"
        }
    }

    $downloadedBinary = Join-Path $tmpDir $binaryName
    if (-not (Test-Path $downloadedBinary)) {
        throw "Archive did not contain $binaryName"
    }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $dest = Join-Path $InstallDir $binaryName
    Copy-Item -LiteralPath $downloadedBinary -Destination $dest -Force

    $version = & $dest --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Installed binary failed to run"
    }
    Write-Host "Installed: $version"

    if ($SkipConfig) {
        Write-Host "Skipping agent configuration (-SkipConfig)"
    } else {
        Write-Host "Configuring coding agents..."
        try {
            & $dest install -y
        } catch {
            Write-Warning "Agent configuration failed; run 'cbm install -y' manually"
        }
    }

    Write-Host "Done."
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
