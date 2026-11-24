<#
.SYNOPSIS
    Sync or export the portable `AGENTS.md` + `.agents/` workflow kit to another repository or globally.
.DESCRIPTION
    Supports two portable reuse modes:
      1. `-TargetRepo <path>` : Copies `AGENTS.md` and `.agents/` into any target project root.
      2. `-InstallGlobal`     : Installs all skills from `.agents/skills/*` into `~/.gemini/config/skills/`
                                so Antigravity discovers them automatically across every workspace on this PC.
    Supports `-DryRun` to preview actions without modifying files.
.EXAMPLE
    .\.agents\skills\learn-and-persist-workflow\scripts\sync_agents_kit.ps1 -TargetRepo "C:\Projects\my_next_app"
.EXAMPLE
    .\.agents\skills\learn-and-persist-workflow\scripts\sync_agents_kit.ps1 -InstallGlobal
.EXAMPLE
    .\.agents\skills\learn-and-persist-workflow\scripts\sync_agents_kit.ps1 -InstallGlobal -DryRun
#>

[CmdletBinding()]
param(
    [string]$TargetRepo = '',
    [switch]$InstallGlobal,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Resolve repository root (4 levels up from .agents/skills/learn-and-persist-workflow/scripts)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$agentsDir = Join-Path $repoRoot '.agents'
$agentsMd = Join-Path $repoRoot 'AGENTS.md'

if (-not (Test-Path $agentsDir) -or -not (Test-Path $agentsMd)) {
    Write-Error "Could not locate AGENTS.md and .agents/ at $repoRoot"
    exit 1
}

if ($TargetRepo -eq '' -and -not $InstallGlobal) {
    Write-Host "Specify -TargetRepo <path> and/or -InstallGlobal (optional -DryRun)." -ForegroundColor Yellow
    exit 1
}

if ($TargetRepo -ne '') {
    if (-not (Test-Path $TargetRepo)) {
        Write-Error "Target repository path does not exist: $TargetRepo"
        exit 1
    }
    $destAgentsMd = Join-Path $TargetRepo 'AGENTS.md'
    $destAgentsDir = Join-Path $TargetRepo '.agents'

    if ($DryRun) {
        Write-Host "[DryRun] Would copy $agentsMd -> $destAgentsMd" -ForegroundColor Cyan
        Write-Host "[DryRun] Would copy $agentsDir -> $destAgentsDir" -ForegroundColor Cyan
    } else {
        Copy-Item -Path $agentsMd -Destination $destAgentsMd -Force
        Copy-Item -Path $agentsDir -Destination $TargetRepo -Recurse -Force
        Write-Host "Synced AGENTS.md and .agents/ to $TargetRepo" -ForegroundColor Green
    }
}

if ($InstallGlobal) {
    $globalSkillsDir = Join-Path $HOME '.gemini\config\skills'
    $skills = Get-ChildItem -Directory (Join-Path $agentsDir 'skills')

    if ($DryRun) {
        Write-Host "[DryRun] Would ensure directory $globalSkillsDir" -ForegroundColor Cyan
        foreach ($s in $skills) {
            Write-Host "[DryRun] Would install skill '$($s.Name)' -> $(Join-Path $globalSkillsDir $s.Name)" -ForegroundColor Cyan
        }
    } else {
        New-Item -ItemType Directory -Force -Path $globalSkillsDir | Out-Null
        foreach ($s in $skills) {
            Copy-Item -Path $s.FullName -Destination $globalSkillsDir -Recurse -Force
            Write-Host "Installed global skill: $($s.Name)" -ForegroundColor Green
        }
    }
}
