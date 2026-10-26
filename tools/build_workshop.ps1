# Create a Steam Workshop-safe staging folder for Metrostroi Expanded.
# Run via tools\build_workshop.bat. Never publish the repository root directly.
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$workshopRoot = Join-Path $repoRoot "build\workshop\metrostroi-expanded"

# Only in-game assets belong in a GMA. In particular, Steam's GMad whitelist
# rejects .md, .ps1 and .sh files present in this development repository.
$allowed = @{
    "lua"       = @(".lua")
    "materials" = @(".vmt", ".vtf", ".png", ".jpg", ".jpeg")
    "models"    = @(".mdl", ".vvd", ".vtx", ".phy", ".ani")
    "sound"     = @(".wav", ".mp3", ".ogg")
    "particles" = @(".pcf")
    "resource"  = @(".ttf", ".otf", ".properties")
    "maps"      = @(".bsp", ".nav", ".ain")
    "scenes"    = @(".vcd")
    "backgrounds" = @(".vtf", ".vmt", ".png", ".jpg", ".jpeg")
}
$addonJson = Join-Path $repoRoot "addon.json"
if (-not (Test-Path -LiteralPath $addonJson -PathType Leaf)) {
    throw "Missing addon.json in $repoRoot"
}
# Never modify the development repository, the installed addon or any
# hand-authored game files. Only rebuild this dedicated staging folder.
if (Test-Path -LiteralPath $workshopRoot) {
    Remove-Item -LiteralPath $workshopRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $workshopRoot -Force | Out-Null
Copy-Item -LiteralPath $addonJson -Destination (Join-Path $workshopRoot "addon.json") -Force

$copied = 0
$skipped = 0
foreach ($folder in $allowed.Keys) {
    $sourceDir = Join-Path $repoRoot $folder
    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
        continue
    }
    $permitted = $allowed[$folder]
    foreach ($file in Get-ChildItem -LiteralPath $sourceDir -File -Recurse) {
        $ext = [IO.Path]::GetExtension($file.Name).ToLowerInvariant()
        if ($permitted -notcontains $ext) {
            Write-Host ("Skipping non-Workshop file: " + $file.FullName.Substring($repoRoot.Length + 1))
            $skipped++
            continue
        }
        # GMad only accepts game folders; e.g. a loose README or install
        # script may be useful in GitHub but must never enter the upload.
        $relPath = $file.FullName.Substring($repoRoot.Length + 1)
        $target = Join-Path $workshopRoot $relPath
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $copied++
    }
}
# Fail early if an essential Lua module was omitted. Previously the builder
# checked only the ASNP autorun, so a partial Workshop upload could start the
# AI autorun but fail to include bridge.lua/controller.lua and crash at startup.
$requiredLua = @(
    "lua/autorun/metrostroi_expanded_asnp.lua",
    "lua/autorun/metrostroi_expanded_rpi.lua",
    "lua/autorun/metrostroi_expanded_damage.lua",
    "lua/autorun/metrostroi_expanded_station_builder.lua",
    "lua/autorun/metrostroi_expanded_track_builder.lua",
    "lua/autorun/metrostroi_expanded_passenger_seats.lua",
    "lua/autorun/server/mex_ars_nearest.lua",
    "lua/autorun/server/mex_ars_player_pos.lua",
    "lua/autorun/server/mex_ai_driver.lua",
    "lua/metrostroi_expanded/ai_driver/bridge.lua",
    "lua/metrostroi_expanded/ai_driver/controller.lua",
    "lua/metrostroi_expanded/ai_driver/cab.lua",
    "lua/metrostroi_expanded/ai_driver/chat.lua",
    "lua/metrostroi_expanded/ai_driver/visual.lua"
)
if ($copied -eq 0) {
    throw "Workshop build failed: no game files were copied."
}
foreach ($relative in $requiredLua) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) {
        throw "Workshop build failed: required MEX source is missing: $relative"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $workshopRoot $relative) -PathType Leaf)) {
        throw "Workshop build failed: required Lua file was not packaged: $relative"
    }
}
Write-Host ("Validated essential Lua modules: " + $requiredLua.Count)
Write-Host ""
Write-Host "Metrostroi Expanded Workshop build ready." -ForegroundColor Green
Write-Host ("Included game files: " + $copied + "; skipped non-Workshop files: " + $skipped)
Write-Host ("Select THIS folder in gmpublisher: " + $workshopRoot) -ForegroundColor Cyan
Write-Host "Do not select the Git repository root or tools directory."
