# AVD & FSLogix Multi-Region Disaster Recovery Runbook

## 1. Purpose and Split-Brain Prevention Invariant

During a regional Azure Virtual Desktop (AVD) outage, the primary hazard is not the failover itself—it is **FSLogix VHDX split-brain corruption** and **Azure Files Premium login-storm IOPS saturation**. If standby session hosts in the secondary region mount a user's `.vhdx` profile container whilst a primary host still holds an active SMB 445/TCP write lease, the profile container is corrupted.

This runbook enforces a **Fence-Then-Release-Then-Stagger** sequence using PowerShell 7.4+, `Invoke-AzRestMethod`, an AI IOPS Saturation Advisor (`ai/Invoke-FslogixIncidentTriage.ps1`), and Microsoft Graph v1.0 Teams Ops Bridge notifications (`graph/Post-AvdFailoverStatus.ps1`).

## 2. Failover Execution Sequence

### Step 1: Fence Primary Session Hosts & SMB 445/TCP Path
1. Place all primary region AVD session hosts into drain mode (`allowNewSession = $false`) via `src/Set-AvdStaggeredDrainMode.ps1`.
2. Apply an NSG deny rule on the primary AVD subnet (`198.51.100.0/24`) blocking outbound `445/TCP` to the Azure Files Private Endpoint.
3. Verify `PrimarySubnetPort445Blocked = $true` and `PrimaryHostsInDrainMode = $true`.

### Step 2: Run AI Profile-Lock & IOPS Saturation Triage
Execute `ai/Invoke-FslogixIncidentTriage.ps1` with the latest `WVDConnections` and Azure Files `Microsoft.Storage/storageAccounts/fileServices` metrics:
- If `RootCauseCode` is `PRIMARY_SUBNET_SPLIT_BRAIN_RISK` (`SafeToFailover = $false`), **ABORT** immediately and complete Step 1.
- If `RootCauseCode` is `ABSTAIN_TELEMETRY_GAP` (`Confidence < 0.75`), verify Azure Monitor diagnostic ingestion before proceeding.
- If `RootCauseCode` is `IOPS_SATURATION_THROTTLE`, adopt the computed `OptimalBatchSize` and `BatchIntervalSeconds` (150s) to avoid exceeding 80% of provisioned Azure Files Premium IOPS.

### Step 3: Fenced SMB Lease Release (`src/Invoke-FencedFslogixLeaseRelease.ps1`)
Once fencing is confirmed, execute `Invoke-FencedFslogixLeaseRelease.ps1`. The script invokes `POST .../fileServices/default/shares/{shareName}/forceCloseHandles?api-version=2023-05-01` via `Invoke-AzRestMethod`, targeting **only** `.vhdx` handles originating from the fenced primary subnet prefix.

### Step 4: Staggered Secondary HostPool Release & Teams Ops Bridge Update
1. Enable `allowNewSession = $true` on secondary region session hosts in batches matching `OptimalBatchSize`.
2. Post the structured status Adaptive Card to the Teams Ops Bridge via `graph/Post-AvdFailoverStatus.ps1`.
3. Monitor `queries/Fslogix-VHDX-LockContention.kql` in Log Analytics for any residual `STATUS_SHARING_VIOLATION` events.
