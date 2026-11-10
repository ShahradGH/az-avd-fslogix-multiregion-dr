# Invoke-FencedFslogixLeaseRelease.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [PSCustomObject]$FailoverState,
    [Parameter(Mandatory)] [PSCustomObject[]]$OpenFileHandles,
    [Parameter()] [string]$FencedPrimarySubnetPrefix = '10.230.2.'
)

$ErrorActionPreference = 'Stop'

# 1. Hard Safety Veto: Never break VHDX locks if primary subnet is still writing over 445/TCP
if (-not $FailoverState.PrimarySubnetPort445Blocked -or -not $FailoverState.PrimaryHostsInDrainMode) {
    return [PSCustomObject]@{
        ShareName      = $FailoverState.ShareName
        Action         = 'VETO_UNFENCED_PRIMARY_HOSTS_SPLIT_BRAIN_RISK'
        HandlesClosed  = 0
        SafeToProceed  = $false
        Reason         = 'Cannot break VHDX SMB leases while primary session hosts still have active SMB 445/TCP write path.'
    }
}

# 2. Target strictly orphaned .vhdx handles from the fenced primary subnet
$orphanedHandles = @($OpenFileHandles | Where-Object {
    $_.Path -match '\.vhdx$' -and $_.ClientIp.StartsWith($FencedPrimarySubnetPrefix)
})

return [PSCustomObject]@{
    ShareName      = $FailoverState.ShareName
    Action         = 'CLOSE_FENCED_ORPHANED_VHDX_HANDLES'
    HandlesClosed  = $orphanedHandles.Count
    TargetPaths    = @($orphanedHandles.Path)
    SafeToProceed  = $true
}
