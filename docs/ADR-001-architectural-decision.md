# ADR-001: AVD Resilience: Resolving FSLogix Profile Container Lock Contention in Multi-Region DR

## Status
Accepted

## Service Owner & Sign-Off Authority
Principal End-User Computing & Azure Infrastructure Architect

## Dominant Artefact
FSLogix Cloud Cache Multi-Region Failover Runbook

## Decision & Refusal Boundary
All production state mutations must pass deterministic pre-flight policy evaluation in `src/Invoke-FencedFslogixLeaseRelease.ps1` and satisfy the 16-test Pester verification contract in `tests/Boundary-Verification.Tests.ps1` before execution.
