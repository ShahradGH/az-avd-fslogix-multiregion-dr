# Set-AvdStaggeredDrainMode.ps1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$HostPoolName, [int]$BatchSize = 250, [int]$IntervalSeconds = 90)
Set-StrictMode -Version Latest
return [PSCustomObject]@{ HostPoolName = $HostPoolName; BatchSize = $BatchSize; IntervalSeconds = $IntervalSeconds; Mode = 'StaggeredLogonRelease' }
