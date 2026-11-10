# AVD & FSLogix Multi-Region Failover Runbook

1. Confirm primary UK South session hosts are network-fenced or drained.
2. Execute `src/Invoke-FencedFslogixLeaseRelease.ps1` to break orphaned SMB leases on `profile.vhdx` containers.
3. Release UK West host pool drain mode in staggered cohorts via `src/Set-AvdStaggeredDrainMode.ps1`.
