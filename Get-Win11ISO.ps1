<#
.SYNOPSIS
    Downloads the latest Windows 11 ISO from Microsoft.

.DESCRIPTION
    This script downloads the Fido PowerShell script and uses it to obtain
    official Windows 11 ISO download links from Microsoft, then downloads the ISO.

.PARAMETER Language
    Language for the Windows ISO. Default is "English (United States)".

.PARAMETER OutputPath
    Directory where the ISO will be saved. Default is current directory.

.EXAMPLE
    .\Get-Win11ISO.ps1

.EXAMPLE
    .\Get-Win11ISO.ps1 -Language "English (United States)" -OutputPath "C:\ISOs"

.NOTES
    Uses the Fido script (https://github.com/pbatard/Fido) to obtain official Microsoft download links.
    Requires internet connection.
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Language for the Windows ISO")]
    [string]$Language = "English (United States)",

    [Parameter(HelpMessage = "Output directory for the ISO file")]
    [string]$OutputPath = "."
)

$ErrorActionPreference = 'Stop'

# Fido script URL
$fidoUrl = "https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1"

Write-Host "Windows 11 ISO Downloader" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan
Write-Host ""

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}
$OutputPath = Resolve-Path $OutputPath

# Download Fido script
Write-Host "Downloading Fido script..." -ForegroundColor Yellow
$fidoScript = Join-Path $env:TEMP "Fido.ps1"

try {
    Invoke-WebRequest -Uri $fidoUrl -OutFile $fidoScript -UseBasicParsing
    Write-Host "Fido script downloaded" -ForegroundColor Green
}
catch {
    Write-Host "Failed to download Fido script: $_" -ForegroundColor Red
    exit 1
}

# Run Fido to get Windows 11 download URL
Write-Host ""
Write-Host "Fetching Windows 11 download link from Microsoft..." -ForegroundColor Yellow
Write-Host "(This queries Microsoft's servers for official ISO links)" -ForegroundColor DarkGray

try {
    # Source the Fido script to get the function
    . $fidoScript
    
    # Call Fido with correct parameters
    # -Win: Windows version (11)
    # -Rel: Release (auto-selects latest)
    # -Ed: Edition (Pro)
    # -Lang: Language
    # -Arch: Architecture (x64)
    # -GetUrl: Return URL instead of downloading
    $downloadUrl = Fido -Win 11 -Lang $Language -Arch "x64" -Ed "Pro" -GetUrl
    
    if (-not $downloadUrl -or $downloadUrl -notmatch "^https://") {
        throw "Failed to get download URL from Fido. Output: $downloadUrl"
    }
    
    Write-Host "Download URL obtained" -ForegroundColor Green
}
catch {
    Write-Host "Failed to get download URL: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Falling back to manual download..." -ForegroundColor Yellow
    Write-Host "Please download Windows 11 ISO manually from:" -ForegroundColor White
    Write-Host "https://www.microsoft.com/software-download/windows11" -ForegroundColor Cyan
    exit 1
}

# Generate output filename
$isoFileName = "Win11_$(Get-Date -Format 'yyyyMMdd')_x64.iso"
$outputFile = Join-Path $OutputPath $isoFileName

# Download the ISO
Write-Host ""
Write-Host "Downloading Windows 11 ISO..." -ForegroundColor Yellow
Write-Host "Destination: $outputFile" -ForegroundColor DarkGray
Write-Host "(This may take 20-60 minutes depending on your connection)" -ForegroundColor DarkGray
Write-Host ""

try {
    # Use BITS for better download handling with progress
    $bitsSupported = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
    
    if ($bitsSupported) {
        Start-BitsTransfer -Source $downloadUrl -Destination $outputFile -DisplayName "Windows 11 ISO" -Description "Downloading from Microsoft"
    }
    else {
        # Fallback to Invoke-WebRequest with progress
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $outputFile -UseBasicParsing
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "SUCCESS! Windows 11 ISO downloaded:" -ForegroundColor Green
    Write-Host $outputFile -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step: Create custom ISO with autounattend.xml" -ForegroundColor White
    Write-Host "  .\New-Win11ISO.ps1 -SourceISO `"$outputFile`" -OutputISO `"Win11_Custom.iso`"" -ForegroundColor DarkGray
}
catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Cleanup Fido script
    Remove-Item -Path $fidoScript -Force -ErrorAction SilentlyContinue
}
