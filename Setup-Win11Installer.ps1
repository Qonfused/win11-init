<#
.SYNOPSIS
    One-click setup: Downloads ADK, Windows 11 ISO, and creates custom installer.

.DESCRIPTION
    This script automates the entire setup process:
    1. Downloads and installs Windows ADK (Deployment Tools only)
    2. Downloads Windows 11 ISO from Microsoft
    3. Creates custom ISO with autounattend.xml embedded

.PARAMETER OutputISO
    Path for the final custom ISO. Default: Win11_Custom.iso in current directory.

.PARAMETER SkipADK
    Skip ADK installation if already installed.

.PARAMETER SkipDownload
    Skip ISO download, use existing ISO specified by -SourceISO.

.PARAMETER SourceISO
    Path to existing Windows 11 ISO (use with -SkipDownload).

.EXAMPLE
    .\Setup-Win11Installer.ps1

.EXAMPLE
    .\Setup-Win11Installer.ps1 -SkipADK -SourceISO "C:\ISOs\Win11.iso"

.NOTES
    Must be run as Administrator for ADK installation.
#>

[CmdletBinding()]
param(
    [string]$OutputISO,
    [switch]$SkipADK,
    [switch]$SkipDownload,
    [string]$SourceISO
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

# Default output to script directory
if (-not $OutputISO) {
    $OutputISO = Join-Path $scriptDir "Win11_Custom.iso"
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Windows 11 Custom Installer Setup                        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Step 1: Check/Install Windows ADK
# ============================================================================

function Test-OscdimgInstalled {
    $paths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        "${env:ProgramFiles(x86)}\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { return $true }
    }
    return $false
}

if (-not $SkipADK) {
    Write-Host "[1/3] Checking Windows ADK..." -ForegroundColor Yellow
    
    if (Test-OscdimgInstalled) {
        Write-Host "      Windows ADK already installed ✓" -ForegroundColor Green
    }
    else {
        Write-Host "      Downloading Windows ADK installer..." -ForegroundColor DarkGray
        
        # ADK download URL (Windows 11 24H2 ADK)
        $adkUrl = "https://go.microsoft.com/fwlink/?linkid=2271337"
        $adkSetup = Join-Path $env:TEMP "adksetup.exe"
        
        try {
            Invoke-WebRequest -Uri $adkUrl -OutFile $adkSetup -UseBasicParsing
            
            Write-Host "      Installing ADK Deployment Tools (this may take 5-10 minutes)..." -ForegroundColor DarkGray
            
            # Silent install of Deployment Tools only
            $process = Start-Process -FilePath $adkSetup -ArgumentList "/quiet /features OptionId.DeploymentTools" -Wait -PassThru
            
            if ($process.ExitCode -ne 0) {
                throw "ADK installation failed with exit code $($process.ExitCode)"
            }
            
            Write-Host "      Windows ADK installed ✓" -ForegroundColor Green
        }
        catch {
            Write-Host "      ERROR: Failed to install ADK: $_" -ForegroundColor Red
            Write-Host "      Please install manually from: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -ForegroundColor Yellow
            exit 1
        }
        finally {
            Remove-Item -Path $adkSetup -Force -ErrorAction SilentlyContinue
        }
    }
}
else {
    Write-Host "[1/3] Skipping ADK check (--SkipADK)" -ForegroundColor DarkGray
}

# ============================================================================
# Step 2: Download Windows 11 ISO
# ============================================================================

if (-not $SkipDownload) {
    Write-Host ""
    Write-Host "[2/3] Downloading Windows 11 ISO..." -ForegroundColor Yellow
    
    $getIsoScript = Join-Path $scriptDir "Get-Win11ISO.ps1"
    
    if (-not (Test-Path $getIsoScript)) {
        Write-Host "      ERROR: Get-Win11ISO.ps1 not found in script directory" -ForegroundColor Red
        exit 1
    }
    
    try {
        # Run download script and capture exit code
        $downloadResult = & $getIsoScript -OutputPath $scriptDir
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "Get-Win11ISO.ps1 failed with exit code $LASTEXITCODE"
        }
        
        # Find the downloaded ISO
        $downloadedISO = Get-ChildItem -Path $scriptDir -Filter "Win11_*.iso" -ErrorAction SilentlyContinue | 
                         Sort-Object LastWriteTime -Descending | 
                         Select-Object -First 1
        
        if (-not $downloadedISO) {
            throw "ISO download completed but file not found in $scriptDir"
        }
        
        $SourceISO = $downloadedISO.FullName
        Write-Host "      Windows 11 ISO downloaded ✓" -ForegroundColor Green
    }
    catch {
        Write-Host "      ERROR: Failed to download ISO: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host ""
    Write-Host "[2/3] Skipping ISO download (--SkipDownload)" -ForegroundColor DarkGray
    
    if (-not $SourceISO) {
        Write-Host "      ERROR: -SourceISO required when using -SkipDownload" -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path $SourceISO)) {
        Write-Host "      ERROR: Source ISO not found: $SourceISO" -ForegroundColor Red
        exit 1
    }
}

# ============================================================================
# Step 3: Create Custom ISO
# ============================================================================

Write-Host ""
Write-Host "[3/3] Creating custom ISO with autounattend.xml..." -ForegroundColor Yellow

$newIsoScript = Join-Path $scriptDir "New-Win11ISO.ps1"

if (-not (Test-Path $newIsoScript)) {
    Write-Host "      ERROR: New-Win11ISO.ps1 not found in script directory" -ForegroundColor Red
    exit 1
}

try {
    & $newIsoScript -SourceISO $SourceISO -OutputISO $OutputISO
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║     Setup Complete!                                          ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "Custom ISO created: $OutputISO" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host "  1. Write ISO to USB with Rufus: https://rufus.ie/" -ForegroundColor DarkGray
    Write-Host "  2. Boot target PC from USB" -ForegroundColor DarkGray
    Write-Host "  3. Select disk/partition, then let automation handle the rest" -ForegroundColor DarkGray
}
catch {
    Write-Host "      ERROR: Failed to create custom ISO: $_" -ForegroundColor Red
    exit 1
}
