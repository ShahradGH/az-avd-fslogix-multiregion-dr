# AVD & FSLogix Multi-Region DR: Fenced Lease Release & AI Login-Storm Triage

Deterministic multi-region disaster recovery orchestration for **Azure Virtual Desktop (AVD)** and **FSLogix Profile Containers** on **Azure Files Premium**, built with **PowerShell 7.4+ (`Invoke-AzRestMethod`)**, **Microsoft Graph v2.x**, and an **AI IOPS Saturation & Profile-Lock Advisor**.

---

## Executive & C-Suite Business Value

### Business Risk Addressed
During a regional Azure outage, naive "flip-the-switch" AVD failovers fail in two predictable ways:
1. **VHDX Profile Corruption (Split-Brain)**: Breaking SMB file locks whilst primary hosts still write over `445/TCP` corrupts user profiles.
2. **Login-Storm Storage Collapse**: Reconnecting 500+ users simultaneously onto standby Azure Files Premium shares triggers massive `45 IOPS/user` logon bursts, saturating provisioned IOPS and causing 15+ minute black-screen logons.

### Measurable ROI & Operational Impact
| DR Resilience Dimension | Naive Regional Failover | Fenced Lease Release & AI Login-Storm Triage |
| :--- | :--- | :--- |
| **VHDX Split-Brain Risk** | High (un-fenced SMB handle breaks) | **Zero** (`445/TCP` NSG-fence + host-drain veto) |
| **Standby Storage Saturation** | >100% IOPS collapse (black screens) | **Capped below 80%** via AI-computed wave batching |
| **Identity & CA Readiness** | Discovered post-failover via tickets | **Pre-validated** via Graph v2.x licence & sign-in audit |
| **Executive Ops Visibility** | Ad-hoc status calls | **Real-time Teams Adaptive Card** + wave notices |

- **Zero Split-Brain Profile Corruption**: Hard safety vetoes in `src/Invoke-FencedFslogixLeaseRelease.ps1` refuse to close SMB handles until primary hosts are drained and `445/TCP` is NSG-fenced.
- **Predictable RTO Without Over-Provisioning**: `ai/Invoke-FslogixIncidentTriage.ps1` computes exact `OptimalBatchSize` and `BatchIntervalSeconds` from live `WVDConnections` and SMB latency telemetry, keeping standby storage below the 80% saturation ceiling.
- **Executive Ops Bridge Visibility**: `graph/Post-AvdFailoverStatus.ps1` and `identity/AvdIdentityResilience.psm1` validate Entra ID user readiness, inspect Conditional Access sign-in health, and dispatch real-time Adaptive Cards to Microsoft Teams via Graph v1.0.

---

## Chief Architect & Engineer Blueprint

### Control-Plane & AI Boundaries
1. **AI Incident & IOPS Triage (`ai/Invoke-FslogixIncidentTriage.ps1`)**: Evaluates `ai/fslogix-iops-saturation-model.json` against `WVDConnections` + Azure Files telemetry, optionally enriched by Azure AI Foundry (`temperature = 0.0`, untrusted telemetry isolation), with an explicit abstention gate (`ABSTAIN_TELEMETRY_GAP`) when `Confidence < 0.75`.
2. **Fenced Azure Storage REST Lease Breaker (`src/Invoke-FencedFslogixLeaseRelease.ps1`)**: Calls `forceCloseHandles?api-version=2023-05-01` via `Invoke-AzRestMethod` strictly for `.vhdx` handles on the fenced primary subnet (`198.51.100.`). Zero Bicep or Terraform templates.
3. **Staggered AVD HostPool Drain/Release (`src/Set-AvdStaggeredDrainMode.ps1`)**: Patches `Microsoft.DesktopVirtualization/hostPools/sessionHosts` (`api-version=2024-04-03`) via `Invoke-AzRestMethod`.
4. **Teams Ops Bridge (`graph/Post-AvdFailoverStatus.ps1`)**: Posts Adaptive Cards to `/v1.0/teams/{teamId}/channels/{channelId}/messages`.

### Architecture & Sequence Diagrams

![AVD FSLogix DR Topology](diagrams/012-azure-stencil-avd-fslogix-dr-topology.png)

![FSLogix Lease Breaker Flow](diagrams/012-azure-stencil-fslogix-lease-breaker-flow.png)

---

## AI Subcomponent & Pilot Grafting Guide

### Chief Architect / Chief Engineer Pilot-Grafting Instructions
1. **Entra ID Workload Identity & Graph Scopes**: Grant your DR automation Managed Identity `User.Read.All`, `AuditLog.Read.All`, and `ChannelMessage.Send` in Microsoft Graph v2.x, alongside Azure Storage `Storage File Data SMB Share Elevated Contributor` on the standby Azure Files share.
2. **Graft onto Existing AVD Host Pools**: Import `identity/AvdIdentityResilience.psm1` ahead of `src/Set-AvdStaggeredDrainMode.ps1` so disabled/unlicensed accounts are filtered out of Wave 1 reconnection cohorts—zero Bicep or Terraform templates required.
3. **Validate Conditional Access Parity**: Run `Invoke-AvdConditionalAccessSignInCheck` against the secondary region's session hosts before opening Wave 2 to catch regional Conditional Access named-location blocks early.

### Quickstart: Run AI IOPS Triage & Pester 6.x Verification
```powershell
# 1. Run AI IOPS saturation & split-brain triage across synthetic hostpool scenarios
$states = Get-Content ./fixtures/hostpool-session-state.json -Raw | ConvertFrom-Json
foreach ($s in $states) {
    & ./ai/Invoke-FslogixIncidentTriage.ps1 -TelemetrySnapshot $s |
        Select-Object PrimaryHostPool, RootCauseCode, SafeToFailover, PredictedPeakIopsPct, OptimalBatchSize, Confidence
}

# 2. Preview fenced SMB lease release (-WhatIf)
$failoverState = [PSCustomObject]@{
    ShareName                  = 'fslogix-profiles-prod'
    PrimarySubnetPort445Blocked = $true
    PrimaryHostsInDrainMode    = $true
}
$handles = @([PSCustomObject]@{ HandleId = 'hdl-901'; Path = 'profiles/alex.vhdx'; ClientIp = '198.51.100.42' })
& ./src/Invoke-FencedFslogixLeaseRelease.ps1 -FailoverState $failoverState -OpenFileHandles $handles -WhatIf

# 3. Execute Pester 6.x verification suite
Invoke-Pester -Path ./tests/FslogixFailover.Tests.ps1 -Output Detailed
```

---

## Microsoft Learn References

- [FSLogix Profile Containers and Azure Files](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/wvd/windows-virtual-desktop-fslogix)
- [Azure Files Scalability and Performance Targets](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-scale-targets)
- [FSLogix Cloud Cache Overview](https://learn.microsoft.com/en-us/fslogix/concepts-cloud-cache)
- [Azure Virtual Desktop Business Continuity and Disaster Recovery](https://learn.microsoft.com/en-us/azure/virtual-desktop/disaster-recovery)
