<#
.SYNOPSIS
    Creates a custom Windows 11 ISO with embedded autounattend.xml for unattended installation.

.DESCRIPTION
    This script takes a source Windows 11 ISO, embeds your autounattend.xml answer file,
    and creates a new bootable ISO image. The resulting ISO can be used for fully
    unattended Windows installations.

.PARAMETER SourceISO
    Path to the original Windows 11 ISO file.

.PARAMETER OutputISO
    Path where the new custom ISO will be created.

.PARAMETER AutoUnattend
    Path to the autounattend.xml file. Defaults to autounattend.xml in the script directory.

.PARAMETER OscdimgPath
    Path to oscdimg.exe. If not specified, searches common Windows ADK locations.

.EXAMPLE
    .\New-Win11ISO.ps1 -SourceISO "C:\ISOs\Win11_24H2.iso" -OutputISO "C:\ISOs\Win11_Custom.iso"

.EXAMPLE
    .\New-Win11ISO.ps1 -SourceISO ".\Win11.iso" -OutputISO ".\Win11_Unattended.iso" -AutoUnattend ".\my-autounattend.xml"

.NOTES
    Requires Windows Assessment and Deployment Kit (ADK) with Deployment Tools installed.
    Must be run with Administrator privileges to mount ISO images.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to the source Windows 11 ISO")]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SourceISO,

    [Parameter(Mandatory = $true, HelpMessage = "Path for the output custom ISO")]
    [string]$OutputISO,

    [Parameter(HelpMessage = "Path to autounattend.xml file")]
    [string]$AutoUnattend,

    [Parameter(HelpMessage = "Path to oscdimg.exe (auto-detected if not specified)")]
    [string]$OscdimgPath
)

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Default to autounattend.xml in script directory
if (-not $AutoUnattend) {
    $AutoUnattend = Join-Path $PSScriptRoot 'autounattend.xml'
}

if (-not (Test-Path $AutoUnattend)) {
    throw "autounattend.xml not found at: $AutoUnattend"
}

# Find oscdimg.exe
function Find-Oscdimg {
    param([string]$CustomPath)
    
    if ($CustomPath -and (Test-Path $CustomPath)) {
        return $CustomPath
    }
    
    $searchPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        "${env:ProgramFiles(x86)}\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        "${env:ProgramFiles}\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )
    
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    # Try PATH
    $inPath = Get-Command 'oscdimg.exe' -ErrorAction SilentlyContinue
    if ($inPath) {
        return $inPath.Source
    }
    
    throw @"
oscdimg.exe not found. Please install Windows ADK with Deployment Tools:
https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install

Or specify the path manually with -OscdimgPath
"@
}

$oscdimg = Find-Oscdimg -CustomPath $OscdimgPath
Write-Host "Using oscdimg: $oscdimg" -ForegroundColor Cyan

# Create temp working directory
$tempDir = Join-Path $env:TEMP "Win11ISO_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Write-Host "Working directory: $tempDir" -ForegroundColor Cyan

try {
    # Mount source ISO
    Write-Host "`nMounting source ISO..." -ForegroundColor Yellow
    $mountResult = Mount-DiskImage -ImagePath (Resolve-Path $SourceISO).Path -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    $sourcePath = "${driveLetter}:\"
    Write-Host "Mounted at: $sourcePath" -ForegroundColor Green

    # Copy ISO contents to temp directory
    Write-Host "`nCopying ISO contents (this may take a few minutes)..." -ForegroundColor Yellow
    $isoContents = Join-Path $tempDir 'iso'
    
    # Use robocopy for faster copying with progress
    $robocopyArgs = @(
        $sourcePath
        $isoContents
        '/E'           # Copy subdirectories including empty ones
        '/NFL'         # No file list
        '/NDL'         # No directory list
        '/NJH'         # No job header
        '/NJS'         # No job summary
        '/NC'          # No file class
        '/NS'          # No file size
        '/NP'          # No progress percentage
    )
    
    & robocopy @robocopyArgs | Out-Null
    
    # Robocopy exit codes 0-7 are success
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy failed with exit code $LASTEXITCODE"
    }
    
    Write-Host "ISO contents copied successfully" -ForegroundColor Green

    # Copy autounattend.xml to ISO root
    Write-Host "`nAdding autounattend.xml to ISO root..." -ForegroundColor Yellow
    Copy-Item -Path $AutoUnattend -Destination (Join-Path $isoContents 'autounattend.xml') -Force
    Write-Host "autounattend.xml added" -ForegroundColor Green

    # Dismount source ISO before creating new one
    Write-Host "`nDismounting source ISO..." -ForegroundColor Yellow
    Dismount-DiskImage -ImagePath (Resolve-Path $SourceISO).Path | Out-Null
    Write-Host "Source ISO dismounted" -ForegroundColor Green

    # Locate boot files for oscdimg
    $etfsboot = Join-Path $isoContents 'boot\etfsboot.com'
    $efisys = Join-Path $isoContents 'efi\microsoft\boot\efisys.bin'
    
    # Some ISOs use efisys_noprompt.bin for no "Press any key" prompt
    $efisysNoprompt = Join-Path $isoContents 'efi\microsoft\boot\efisys_noprompt.bin'
    if (Test-Path $efisysNoprompt) {
        $efisys = $efisysNoprompt
    }
    
    if (-not (Test-Path $etfsboot)) {
        throw "Boot file not found: $etfsboot"
    }
    if (-not (Test-Path $efisys)) {
        throw "UEFI boot file not found: $efisys"
    }

    # Ensure output directory exists
    $outputDir = Split-Path $OutputISO -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Create new bootable ISO
    Write-Host "`nCreating bootable ISO..." -ForegroundColor Yellow
    Write-Host "This may take several minutes depending on your disk speed." -ForegroundColor DarkGray
    
    # oscdimg arguments for UEFI + Legacy BIOS boot
    $oscdimgArgs = @(
        '-m'                           # Ignore maximum image size
        '-o'                           # Optimize storage by MD5 hashing duplicate files
        '-u2'                          # UDF file system
        '-udfver102'                   # UDF version 1.02
        "-bootdata:2#p0,e,b`"$etfsboot`"#pEF,e,b`"$efisys`""  # Dual boot (BIOS + UEFI)
        $isoContents                   # Source folder
        $OutputISO                     # Output ISO
    )
    
    & $oscdimg @oscdimgArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "oscdimg failed with exit code $LASTEXITCODE"
    }

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "SUCCESS! Custom ISO created:" -ForegroundColor Green
    Write-Host $OutputISO -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "`nThe ISO includes your autounattend.xml and is ready"
    Write-Host "for fully unattended Windows installation."
}
catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    
    # Attempt to dismount ISO if still mounted
    try {
        Dismount-DiskImage -ImagePath (Resolve-Path $SourceISO).Path -ErrorAction SilentlyContinue | Out-Null
    }
    catch { }
    
    throw
}
finally {
    # Cleanup temp directory
    if (Test-Path $tempDir) {
        Write-Host "`nCleaning up temporary files..." -ForegroundColor DarkGray
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
