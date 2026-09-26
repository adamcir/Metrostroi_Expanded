param(
    [Parameter(Position = 0)]
    [string]$GModRoot
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$AddonName = "metrostroi-expanded"

function Add-Candidate {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        $full = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return
    }

    if (-not $List.Contains($full)) {
        $List.Add($full)
    }
}

function Add-SteamRootCandidates {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$SteamRoot
    )

    if ([string]::IsNullOrWhiteSpace($SteamRoot)) {
        return
    }

    Add-Candidate -List $List -Path (Join-Path $SteamRoot "steamapps\common\GarrysMod")

    $libraryFile = Join-Path $SteamRoot "steamapps\libraryfolders.vdf"
    if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) {
        return
    }

    foreach ($line in Get-Content -LiteralPath $libraryFile -ErrorAction SilentlyContinue) {
        if ($line -match '"path"\s+"([^"]+)"') {
            $libraryRoot = $Matches[1] -replace '\\\\', '\'
            Add-Candidate -List $List -Path (Join-Path $libraryRoot "steamapps\common\GarrysMod")
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GModRoot) -and -not [string]::IsNullOrWhiteSpace($env:GMOD_DIR)) {
    $GModRoot = $env:GMOD_DIR
}

if ([string]::IsNullOrWhiteSpace($GModRoot)) {
    $candidates = [System.Collections.Generic.List[string]]::new()

    if ($env:ProgramFiles) {
        Add-SteamRootCandidates -List $candidates -SteamRoot (Join-Path $env:ProgramFiles "Steam")
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFilesX86) {
        Add-SteamRootCandidates -List $candidates -SteamRoot (Join-Path $programFilesX86 "Steam")
    }

    $registryLocations = @(
        @{ Path = "HKCU:\Software\Valve\Steam"; Name = "SteamPath" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"; Name = "InstallPath" },
        @{ Path = "HKLM:\SOFTWARE\Valve\Steam"; Name = "InstallPath" }
    )

    foreach ($entry in $registryLocations) {
        try {
            $value = (Get-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction Stop).($entry.Name)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                Add-SteamRootCandidates -List $candidates -SteamRoot $value
            }
        }
        catch {
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "garrysmod") -PathType Container) {
            $GModRoot = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GModRoot)) {
    Write-Host "Garry's Mod installation was not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage:"
    Write-Host '  tools\install.bat "C:\path\to\GarrysMod"'
    Write-Host ""
    Write-Host "or:"
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\tools\install.ps1 "C:\path\to\GarrysMod"'
    exit 1
}

try {
    $GModRoot = [System.IO.Path]::GetFullPath($GModRoot)
}
catch {
    Write-Host "Invalid Garry's Mod path: $GModRoot" -ForegroundColor Red
    exit 1
}

$GarrysmodDir = Join-Path $GModRoot "garrysmod"
if (-not (Test-Path -LiteralPath $GarrysmodDir -PathType Container)) {
    Write-Host "The selected path is not a Garry's Mod installation:" -ForegroundColor Red
    Write-Host "  $GModRoot"
    Write-Host ""
    Write-Host 'Expected to find a "garrysmod" directory inside it.'
    exit 1
}

$AddonsDir = Join-Path $GarrysmodDir "addons"
$Dest = Join-Path $AddonsDir $AddonName
$Legacy = Join-Path $AddonsDir "metrostroi-passenger-seats"

New-Item -ItemType Directory -Force -Path $AddonsDir | Out-Null

$repoFull = [System.IO.Path]::GetFullPath($RepoDir).TrimEnd('\')
$destFull = [System.IO.Path]::GetFullPath($Dest).TrimEnd('\')

if ([string]::Equals($repoFull, $destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "Metrostroi Expanded is already located in Garry's Mod addons:"
    Write-Host "  $Dest"
    exit 0
}

if (Test-Path -LiteralPath $Legacy -PathType Container) {
    Write-Host "Removing legacy Metrostroi Passenger Seats addon to prevent duplicate loading:"
    Write-Host "  $Legacy"
    Remove-Item -LiteralPath $Legacy -Recurse -Force
}

Write-Host "Installing Metrostroi Expanded..."
Write-Host "Source:      $RepoDir"
Write-Host "Destination: $Dest"

if (Test-Path -LiteralPath $Dest) {
    Remove-Item -LiteralPath $Dest -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

$files = @(
    "addon.json",
    "README.md",
    "LICENSE"
)

foreach ($file in $files) {
    $source = Join-Path $RepoDir $file
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination $Dest -Force
    }
}

$directories = @(
    "lua",
    "materials",
    "models",
    "sound",
    "scripts",
    "resource",
    "particles"
)

foreach ($directory in $directories) {
    $source = Join-Path $RepoDir $directory
    if (Test-Path -LiteralPath $source -PathType Container) {
        Copy-Item -LiteralPath $source -Destination $Dest -Recurse -Force
    }
}

Write-Host ""
Write-Host "Installed successfully." -ForegroundColor Green
Write-Host "Restart Garry's Mod or change/restart the map before testing."
Write-Host "Passenger seat status command: mps_status"
