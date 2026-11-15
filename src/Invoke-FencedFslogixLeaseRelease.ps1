<#
.SYNOPSIS
    Fenced FSLogix VHDX SMB lease-release via Azure Storage REST (Invoke-AzRestMethod).
.DESCRIPTION
    Enforces a strict split-brain safety veto before breaking orphaned .vhdx SMB file handles
    from a fenced primary subnet using Azure Files REST API forceCloseHandles.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [PSCustomObject]$FailoverState,

    [Parameter(Mandatory)]
    [PSCustomObject[]]$OpenFileHandles,

    [Parameter()]
    [string]$FencedPrimarySubnetPrefix = '198.51.100.',

    [Parameter()]
    [string]$SubscriptionId = '00000000-0000-0000-0000-000000000012',

    [Parameter()]
    [string]$ResourceGroupName = 'rg-contoso-avd-dr',

    [Parameter()]
    [string]$StorageAccountName = 'stcontosofslogixdr',

    [Parameter()]
    [scriptblock]$AzRestInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 1. Hard Safety Veto: Never break VHDX locks if primary subnet is still writing over 445/TCP
if (-not $FailoverState.PrimarySubnetPort445Blocked -or -not $FailoverState.PrimaryHostsInDrainMode) {
    return [PSCustomObject]@{
        ShareName     = $FailoverState.ShareName
        Action        = 'VETO_UNFENCED_PRIMARY_HOSTS_SPLIT_BRAIN_RISK'
        HandlesClosed = 0
        TargetPaths   = @()
        SafeToProceed = $false
        Reason        = 'Cannot break VHDX SMB leases while primary session hosts still have active SMB 445/TCP write path.'
    }
}

# 2. Target strictly orphaned .vhdx handles from the fenced primary subnet
$orphanedHandles = @($OpenFileHandles | Where-Object {
    $_.Path -match '\.vhdx$' -and $_.ClientIp.StartsWith($FencedPrimarySubnetPrefix)
})

$closedCount = 0
foreach ($handle in $orphanedHandles) {
    $restPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName/fileServices/default/shares/$($FailoverState.ShareName)/forceCloseHandles?api-version=2023-05-01"
    $payload = @{
        handleId = $handle.HandleId
        path     = $handle.Path
    }
    if ($PSCmdlet.ShouldProcess($handle.Path, "Force close fenced SMB handle $($handle.HandleId)")) {
        if ($null -ne $AzRestInvoker) {
            $null = & $AzRestInvoker 'POST' $restPath $payload
        }
        else {
            $resp = Invoke-AzRestMethod -Method Post -Path $restPath -Payload ($payload | ConvertTo-Json -Depth 4)
            if ($resp.StatusCode -ge 400) {
                throw "Storage forceCloseHandles failed with HTTP $($resp.StatusCode): $($resp.Content)"
            }
        }
        $closedCount++
    }
}

return [PSCustomObject]@{
    ShareName     = $FailoverState.ShareName
    Action        = 'CLOSE_FENCED_ORPHANED_VHDX_HANDLES'
    HandlesClosed = $closedCount
    TargetPaths   = @($orphanedHandles.Path)
    SafeToProceed = $true
    ExecutedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
}
