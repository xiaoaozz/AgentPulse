param(
    [string]$Version = "0.1.0",
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Root "Windows/AgentPulse.Windows/AgentPulse.Windows.csproj"
$Dist = Join-Path $Root "dist"
$Publish = Join-Path $Dist "AgentPulse-$Runtime"
$Archive = Join-Path $Dist "AgentPulse-$Version-$Runtime.zip"
$Checksum = "$Archive.sha256"
$VelopackOutput = Join-Path $Dist "velopack-$Runtime"
$ToolDirectory = Join-Path $Dist ".tools"
$Platform = if ($Runtime -eq "win-arm64") { "ARM64" } else { "x64" }

Remove-Item $Publish, $Archive, $Checksum, $VelopackOutput -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Publish | Out-Null

dotnet publish $Project `
    --configuration Release `
    --runtime $Runtime `
    --self-contained true `
    -p:Platform=$Platform `
    -p:Version=$Version `
    --output $Publish

$Scripts = Join-Path $Publish "Scripts"
$Protocol = Join-Path $Publish "Protocol"
New-Item -ItemType Directory -Force -Path $Scripts, $Protocol | Out-Null
Copy-Item (Join-Path $Root "scripts/agent-pulse-codex-hook.mjs") $Scripts
Copy-Item (Join-Path $Root "scripts/agentpulse-hook.py") $Scripts
Copy-Item (Join-Path $Root "Protocol/agent-event.schema.json") $Protocol

Compress-Archive -Path (Join-Path $Publish "*") -DestinationPath $Archive
$Hash = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
"$Hash *$(Split-Path -Leaf $Archive)" | Set-Content -Encoding ascii $Checksum

if (-not (Test-Path (Join-Path $ToolDirectory "vpk.exe"))) {
    dotnet tool install vpk --tool-path $ToolDirectory --version 1.2.0
}

& (Join-Path $ToolDirectory "vpk.exe") pack `
    --packId io.github.xiaoaozz.AgentPulse `
    --packVersion $Version `
    --packDir $Publish `
    --runtime $Runtime `
    --mainExe AgentPulse.Windows.exe `
    --packTitle AgentPulse `
    --packAuthors "AgentPulse contributors" `
    --outputDir $VelopackOutput

Write-Host "Created $Archive"
Write-Host "Created Velopack installer and update packages in $VelopackOutput"
