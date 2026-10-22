# MEX AI Driver backend installer (PowerShell 5.1+)
[CmdletBinding()]
param(
    [string]$Destination = "",
    [switch]$ForceGuide,
    [switch]$PullModel,
    [switch]$Start,
    [string]$Model = "qwen3:8b"
)
$ErrorActionPreference = "Stop"
$src = Join-Path (Split-Path -Parent $PSScriptRoot) "tools/ai_driver_backend"
if (-not (Test-Path (Join-Path $src "mex_ai_server.js"))) { throw "Backend source is missing: $src" }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "Node.js >= 18 is required." }
$v = (& node --version).Trim()
$matchVersion = [regex]::Match($v, '^v(\d+)')
if (-not $matchVersion.Success -or [int]$matchVersion.Groups[1].Value -lt 18) { throw "Node.js >= 18 required ($v)." }
if ($Model -notmatch '^[a-zA-Z0-9_./:-]{1,90}$') { throw "Invalid model name" }
if (-not $Destination) {
    if ($env:OS -eq "Windows_NT") {
        $base = $env:LOCALAPPDATA
        if (-not $base) { $base = Join-Path $HOME "AppData/Local" }
        $Destination = Join-Path $base "MetrostroiExpanded/AIBackend"
    } else {
        $base = $env:XDG_DATA_HOME
        if (-not $base) { $base = Join-Path $HOME ".local/share" }
        $Destination = Join-Path $base "metrostroi-expanded/ai-backend"
    }
}
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$items = @("mex_ai_server.js","driver_guide.md","chat_guide.md","package.json","example_request.json","README.md","test/server.test.js")
foreach ($item in $items) {
    $from = Join-Path $src $item
    $to = Join-Path $Destination $item
    if (-not (Test-Path $from)) { throw "Missing: $from" }
    if (($item -eq "driver_guide.md" -or $item -eq "chat_guide.md") -and (Test-Path $to) -and -not $ForceGuide) {
        Write-Host "Preserving custom driver_guide.md"
        continue
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to -Force
    Write-Host "Installed $item"
}
$launcher = @('@echo off','cd /d "%~dp0"', ('if not defined OLLAMA_MODEL set "OLLAMA_MODEL=' + $Model + '"'), 'node mex_ai_server.js','pause')
Set-Content -LiteralPath (Join-Path $Destination "start_backend.cmd") -Value $launcher -Encoding ASCII
Write-Host "Backend installed at: $Destination"
Write-Host "TCP 127.0.0.1:3002, Ollama 127.0.0.1:11434"
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Warning "Ollama not found. Install and start Ollama separately."
} elseif ($PullModel) {
    & ollama pull $Model
    if ($LASTEXITCODE -ne 0) { throw "Failed to pull Ollama model." }
}
if ($Start) {
    $env:OLLAMA_MODEL = $Model
    Push-Location $Destination
    try { & node "mex_ai_server.js" } finally { Pop-Location }
} else {
    Write-Host "Run start_backend.cmd in the installation folder, or run node mex_ai_server.js there."
}
