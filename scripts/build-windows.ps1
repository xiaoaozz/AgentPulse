param(
    [string]$Version = "0.1.0",
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Root "Platforms/Windows/Sources/AgentPulse.Windows/AgentPulse.Windows.csproj"
$Dist = Join-Path $Root "dist"
$Publish = Join-Path $Dist "AgentPulse-$Runtime"
$VelopackOutput = Join-Path $Dist "velopack-$Runtime"
$ReleaseOutput = Join-Path $Dist "release-$Runtime"
$ToolDirectory = Join-Path $Dist ".tools"
$Platform = if ($Runtime -eq "win-arm64") { "ARM64" } else { "x64" }

Remove-Item $Publish, $VelopackOutput, $ReleaseOutput -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Publish, $ReleaseOutput | Out-Null

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
Copy-Item (Join-Path $Root "Shared/Protocol/agent-event.schema.json") $Protocol

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

$Setup = @(Get-ChildItem $VelopackOutput -Filter "*-Setup.exe")
$Portable = @(Get-ChildItem $VelopackOutput -Filter "*-Portable.zip")
if ($Setup.Count -ne 1 -or $Portable.Count -ne 1) {
    throw "Expected exactly one Velopack setup package and one portable package"
}
Copy-Item $Setup[0].FullName (Join-Path $ReleaseOutput "AgentPulse-Windows-Setup.exe")
Copy-Item $Portable[0].FullName (Join-Path $ReleaseOutput "AgentPulse-Windows-Portable.zip")

Write-Host "Created user-facing Windows packages in $ReleaseOutput"
