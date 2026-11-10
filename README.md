# AVD Resilience: Resolving FSLogix Profile Container Lock Contention in Multi-Region DR

[![Pester Verification](https://img.shields.io/badge/pester-16%2F16%20passing-brightgreen)](tests/FslogixFailover.Tests.ps1)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Architecture Deep-Dive](https://img.shields.io/badge/blog-alerasoul.net-0a1128)](https://alerasoul.net/avd-fslogix-multiregion-profile-locks/)

> **Primary Governance Artefact:** FSLogix Cloud Cache Multi-Region Failover Runbook  
> **Accountable Service Owner:** Principal End-User Computing & Azure Infrastructure Architect  
> **Full Architectural Deep-Dive:** [https://alerasoul.net/avd-fslogix-multiregion-profile-locks/](https://alerasoul.net/avd-fslogix-multiregion-profile-locks/)

---

## Repository Layout (13 Files)

```text
├── .github/workflows/ci.yml
├── .gitignore
├── LICENSE
├── README.md
├── config/cloud-cache-registry.reg
├── fixtures/hostpool-session-state.json
├── infra/avd-hostpool-dr.bicep
├── infra/azure-files-premium.bicep
├── queries/Fslogix-VHDX-LockContention.kql
├── runbooks/AVD-REGIONAL-FAILOVER.md
├── src/Invoke-FencedFslogixLeaseRelease.ps1
├── src/Set-AvdStaggeredDrainMode.ps1
└── tests/FslogixFailover.Tests.ps1
```

## Quickstart & Offline Verification

```powershell
# 1. Execute the primary PowerShell 7 evaluator
pwsh -NoProfile -File ./src/Invoke-FencedFslogixLeaseRelease.ps1

# 2. Run the 16-test Pester verification contract
Invoke-Pester -Path ./tests/FslogixFailover.Tests.ps1 -Output Detailed
```

## License

Released under the [MIT License](LICENSE). Authored by **Shahrad Alerasoul** ([alerasoul.net](https://alerasoul.net)).
