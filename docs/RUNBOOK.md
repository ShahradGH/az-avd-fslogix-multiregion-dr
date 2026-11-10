# Operational Runbook: AVD Resilience: Resolving FSLogix Profile Container Lock Contention in Multi-Region DR (L2 / L3 Triage)

## 1. Scope & Ownership
- **Accountable Owner**: Principal End-User Computing & Azure Infrastructure Architect
- **Primary Evaluator**: `src/Invoke-FencedFslogixLeaseRelease.ps1`
- **Telemetry Source**: `diagnostics/Telemetry-Queries.kql`

## 2. Triage Procedure When Veto Gate Trips
1. Inspect the structured refusal object emitted by `src/Invoke-FencedFslogixLeaseRelease.ps1` and correlate the timestamp in Azure Monitor Log Analytics.
2. Do not bypass or disable the pre-flight policy gate without cryptographic dual-signature approval from the Principal End-User Computing & Azure Infrastructure Architect.
3. Verify remediation locally by running `Invoke-Pester -Path ./tests/Boundary-Verification.Tests.ps1 -Output Detailed`.
