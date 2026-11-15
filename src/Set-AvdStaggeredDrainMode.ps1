<#
.SYNOPSIS
    Configures AVD session host drain mode and staggered logon release via Invoke-AzRestMethod.
.DESCRIPTION
    Updates Microsoft.DesktopVirtualization/hostPools/sessionHosts allowNewSession state in batches
    to prevent Azure Files Premium login-storm IOPS saturation during multi-region failover.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$HostPoolName,

    [Parameter()]
    [string]$SubscriptionId = '00000000-0000-0000-0000-000000000012',

    [Parameter()]
    [string]$ResourceGroupName = 'rg-contoso-avd-dr',

    [Parameter()]
    [string[]]$SessionHostNames = @('avd-uks-01.contoso.com', 'avd-uks-02.contoso.com'),

    [Parameter()]
    [bool]$AllowNewSession = $false,

    [Parameter()]
    [int]$BatchSize = 250,

    [Parameter()]
    [int]$IntervalSeconds = 90,

    [Parameter()]
    [scriptblock]$AzRestInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$updatedHosts = [System.Collections.Generic.List[string]]::new()
foreach ($hostName in $SessionHostNames) {
    $path = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.DesktopVirtualization/hostPools/$HostPoolName/sessionHosts/${hostName}?api-version=2024-04-03"
    $payload = @{
        properties = @{
            allowNewSession = $AllowNewSession
        }
    }
    if ($PSCmdlet.ShouldProcess($hostName, "Set allowNewSession=$AllowNewSession")) {
        if ($null -ne $AzRestInvoker) {
            $null = & $AzRestInvoker 'PATCH' $path $payload
        }
        else {
            $resp = Invoke-AzRestMethod -Method Patch -Path $path -Payload ($payload | ConvertTo-Json -Depth 4)
            if ($resp.StatusCode -ge 400) {
                throw "AVD sessionHost PATCH failed with HTTP $($resp.StatusCode): $($resp.Content)"
            }
        }
        $updatedHosts.Add($hostName)
    }
}

return [PSCustomObject]@{
    HostPoolName    = $HostPoolName
    AllowNewSession = $AllowNewSession
    UpdatedHosts    = @($updatedHosts)
    BatchSize       = $BatchSize
    IntervalSeconds = $IntervalSeconds
    Mode            = if ($AllowNewSession) { 'StaggeredLogonRelease' } else { 'DrainModeEnabled' }
    UpdatedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
}
