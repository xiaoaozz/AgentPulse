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
$Platform = if ($Runtime -eq "win-arm64") { "ARM64" } else { "x64" }

Remove-Item $Publish, $Archive, $Checksum -Recurse -Force -ErrorAction SilentlyContinue
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

Write-Host "Created $Archive"
