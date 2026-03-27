#Requires -Version 5.1
<#
.SYNOPSIS
    Apply workspace IDs to widgets.json for workspace-scoped widgets.
.DESCRIPTION
    After creating workspaces in Wave Terminal UI, run this script with the
    workspace IDs to scope widgets to their correct workspaces.
.EXAMPLE
    .\apply-workspace-ids.ps1 -OpsId "ws-abc123" -DevId "ws-def456" -NetId "ws-ghi789"
.EXAMPLE
    .\apply-workspace-ids.ps1 -OpsId "ws-abc123" -DevId "ws-def456" -NetId "ws-ghi789" -RemoteId "ws-jkl012"
#>
param(
    [Parameter(Mandatory)][string]$OpsId,
    [Parameter(Mandatory)][string]$DevId,
    [Parameter(Mandatory)][string]$NetId,
    [string]$RemoteId
)

$WidgetsFile = "$env:USERPROFILE\.config\waveterm\widgets.json"
$RepoFile = "D:\mapping\services\apps\wave-terminal\config\widgets.json"

# Widget-to-workspace mapping
$WorkspaceMap = @{
    # Ops workspace
    "defwidget@sysinfo"  = @($OpsId)
    "cpu-graph"          = @($OpsId)
    "mem-graph"          = @($OpsId)
    "all-cpu-graph"      = @($OpsId)
    "btop"               = @($OpsId)
    "disk-usage"         = @($OpsId)
    "docker-stats"       = @($OpsId)
    "gpu-stats"          = @($OpsId)
    "machine-dashboard"  = @($OpsId)
    # Dev workspace
    "defwidget@web"      = @($DevId)
    "weather"            = @($DevId)
    # Net workspace
    "mikrotik"           = @($NetId)
    "mikrotik-web"       = @($NetId)
    "quick-connect"      = @($NetId)
    # Shared: ssh-health in Ops + Net
    "ssh-health"         = @($OpsId, $NetId)
}

# Optional Remote workspace
if ($RemoteId) {
    $WorkspaceMap["docker-manager"] = @($OpsId, $RemoteId)
    $WorkspaceMap["cf-tunnels"]     = @($OpsId, $RemoteId)
    $WorkspaceMap["git-sync"]       = @($OpsId, $RemoteId)
    $WorkspaceMap["gpu-stats"]      = @($OpsId, $RemoteId)
} else {
    $WorkspaceMap["docker-manager"] = @($OpsId)
    $WorkspaceMap["cf-tunnels"]     = @($OpsId)
    $WorkspaceMap["git-sync"]       = @($OpsId)
}

# Read widgets.json
$json = Get-Content $RepoFile -Raw | ConvertFrom-Json

# Apply workspace arrays
foreach ($widget in $WorkspaceMap.Keys) {
    if ($json.PSObject.Properties.Name -contains $widget) {
        $json.$widget | Add-Member -NotePropertyName "workspaces" -NotePropertyValue $WorkspaceMap[$widget] -Force
        Write-Host "  $widget -> $($WorkspaceMap[$widget] -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "  $widget — NOT FOUND in widgets.json" -ForegroundColor Yellow
    }
}

# Save to both repo and live config
$output = $json | ConvertTo-Json -Depth 10
$output | Set-Content $RepoFile -Encoding UTF8
$output | Set-Content $WidgetsFile -Encoding UTF8

Write-Host "`nDone. Restart Wave Terminal to apply." -ForegroundColor Cyan
Write-Host "Repo:  $RepoFile" -ForegroundColor DarkGray
Write-Host "Live:  $WidgetsFile" -ForegroundColor DarkGray
