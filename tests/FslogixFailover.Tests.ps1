BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:TriagePath = Join-Path $script:RepoRoot 'ai/Invoke-FslogixIncidentTriage.ps1'
    $script:LeasePath = Join-Path $script:RepoRoot 'src/Invoke-FencedFslogixLeaseRelease.ps1'
    $script:DrainPath = Join-Path $script:RepoRoot 'src/Set-AvdStaggeredDrainMode.ps1'
    $script:GraphStatusPath = Join-Path $script:RepoRoot 'graph/Post-AvdFailoverStatus.ps1'
    $script:FixturesPath = Join-Path $script:RepoRoot 'fixtures/hostpool-session-state.json'
    $script:KqlPath = Join-Path $script:RepoRoot 'queries/Fslogix-VHDX-LockContention.kql'
    $script:Scenarios = Get-Content -Path $script:FixturesPath -Raw | ConvertFrom-Json
}

Describe 'AVD FSLogix Multi-Region DR - AI Triage, Fenced Lease Release & Graph Ops Bridge' {
    Context 'AI IOPS Saturation & Profile-Lock Advisor (ai/Invoke-FslogixIncidentTriage.ps1)' {
        It 'Detects IOPS saturation storm and computes throttled stagger batch size' {
            $s = $script:Scenarios | Where-Object { $_.scenario -eq 'IopsSaturationThrottle' }
            $res = & $script:TriagePath -TelemetrySnapshot $s
            $res.RootCauseCode | Should -Be 'IOPS_SATURATION_THROTTLE'
            $res.SafeToFailover | Should -BeTrue
            $res.PredictedPeakIopsPct | Should -BeGreaterThan 80.0
            $res.OptimalBatchSize | Should -BeGreaterOrEqual 50
            $res.BatchIntervalSeconds | Should -Be 150
        }

        It 'Approves healthy staggered failover within IOPS ceiling' {
            $s = $script:Scenarios | Where-Object { $_.scenario -eq 'HealthyStaggeredFailover' }
            $res = & $script:TriagePath -TelemetrySnapshot $s
            $res.RootCauseCode | Should -Be 'HEALTHY_STAGGERED_FAILOVER'
            $res.SafeToFailover | Should -BeTrue
            $res.BatchIntervalSeconds | Should -Be 90
        }

        It 'Vetoes failover when primary network is not isolated (split-brain risk)' {
            $s = $script:Scenarios | Where-Object { $_.scenario -eq 'UnfencedSplitBrainRisk' }
            $res = & $script:TriagePath -TelemetrySnapshot $s
            $res.RootCauseCode | Should -Be 'PRIMARY_SUBNET_SPLIT_BRAIN_RISK'
            $res.SafeToFailover | Should -BeFalse
            $res.OptimalBatchSize | Should -Be 0
        }

        It 'Abstains when telemetry is incomplete (ABSTAIN_TELEMETRY_GAP)' {
            $s = $script:Scenarios | Where-Object { $_.scenario -eq 'TelemetryGapAbstention' }
            $res = & $script:TriagePath -TelemetrySnapshot $s
            $res.RootCauseCode | Should -Be 'ABSTAIN_TELEMETRY_GAP'
            $res.SafeToFailover | Should -BeFalse
            $res.Confidence | Should -BeLessThan 0.75
        }

        It 'Integrates mocked Azure AI Foundry triage summary' {
            $s = $script:Scenarios | Where-Object { $_.scenario -eq 'IopsSaturationThrottle' }
            $mockFoundry = {
                param($ep, $dep, $body)
                return [PSCustomObject]@{
                    triageSummary            = 'Enable Cloud Cache passive async hydration and stagger 200 users per wave.'
                    cloudCacheRecommendation = 'CCDLocations=type=smb,connectionString=\\stcontosofslogixdr.file.core.windows.net\profiles'
                    confidenceAdjustment     = 0.03
                }
            }
            $res = & $script:TriagePath -TelemetrySnapshot $s -FoundryEndpoint 'https://foundry.contoso.invalid' -FoundryInvoker $mockFoundry
            $res.FoundryAdvisory.triageSummary | Should -Match 'Cloud Cache'
        }
    }

    Context 'Fenced Storage REST Lease Breaker, AVD Drain Mode & Graph Ops Bridge' {
        It 'Refuses to break SMB leases when primary subnet 445/TCP is not blocked' {
            $state = [PSCustomObject]@{ ShareName = 'fslogix-profiles'; PrimarySubnetPort445Blocked = $false; PrimaryHostsInDrainMode = $true }
            $handles = @([PSCustomObject]@{ HandleId = 'h1'; Path = 'profiles/alex.vhdx'; ClientIp = '198.51.100.12' })
            $res = & $script:LeasePath -FailoverState $state -OpenFileHandles $handles
            $res.Action | Should -Be 'VETO_UNFENCED_PRIMARY_HOSTS_SPLIT_BRAIN_RISK'
            $res.HandlesClosed | Should -Be 0
            $res.SafeToProceed | Should -BeFalse
        }

        It 'Calls Azure Storage forceCloseHandles via Invoke-AzRestMethod for fenced .vhdx handles only' {
            $state = [PSCustomObject]@{ ShareName = 'fslogix-profiles'; PrimarySubnetPort445Blocked = $true; PrimaryHostsInDrainMode = $true }
            $handles = @(
                [PSCustomObject]@{ HandleId = 'h1'; Path = 'profiles/alex.vhdx'; ClientIp = '198.51.100.12' },
                [PSCustomObject]@{ HandleId = 'h2'; Path = 'profiles/other.txt'; ClientIp = '198.51.100.13' },
                [PSCustomObject]@{ HandleId = 'h3'; Path = 'profiles/sec.vhdx'; ClientIp = '203.0.113.55' }
            )
            $calls = [System.Collections.Generic.List[string]]::new()
            $mockAz = { param($m, $p, $b) $calls.Add("$m $p"); return @{} }
            $res = & $script:LeasePath -FailoverState $state -OpenFileHandles $handles -AzRestInvoker $mockAz
            $res.Action | Should -Be 'CLOSE_FENCED_ORPHANED_VHDX_HANDLES'
            $res.HandlesClosed | Should -Be 1
            $calls[0] | Should -Match 'forceCloseHandles\?api-version=2023-05-01'
        }

        It 'Sets AVD session host drain mode via Invoke-AzRestMethod' {
            $calls = [System.Collections.Generic.List[string]]::new()
            $mockAz = { param($m, $p, $b) $calls.Add("$m $p"); return @{} }
            $res = & $script:DrainPath -HostPoolName 'vdpool-uks-01' -SessionHostNames @('avd-01.contoso.com', 'avd-02.contoso.com') -AllowNewSession $false -AzRestInvoker $mockAz
            $res.Mode | Should -Be 'DrainModeEnabled'
            $res.UpdatedHosts.Count | Should -Be 2
            $calls[0] | Should -Match 'Microsoft\.DesktopVirtualization/hostPools/vdpool-uks-01/sessionHosts'
        }

        It 'Posts Teams Ops Bridge Adaptive Card via Graph v1.0' {
            $s = $script:Scenarios | Where-Object { $_.scenario -eq 'IopsSaturationThrottle' }
            $triage = & $script:TriagePath -TelemetrySnapshot $s
            $captured = [System.Collections.Generic.List[string]]::new()
            $mockGraph = { param($m, $u, $b) $captured.Add("$m $u"); return [PSCustomObject]@{ id = 'msg-dr-12' } }
            $res = & $script:GraphStatusPath -TeamId 'team-dr' -ChannelId '19:ops@thread.tacv2' -TriageResult $triage -HandlesReleased 42 -GraphInvoker $mockGraph
            $res.MessageId | Should -Be 'msg-dr-12'
            $captured[0] | Should -Match 'https://graph\.microsoft\.com/v1\.0/teams/team-dr/channels/'
        }
    }

    Context 'Repository Hygiene & Zero-Leak Boundaries' {
        It 'Contains zero declarative IaC (.bicep or .tf) files' {
            $iac = Get-ChildItem -Path $script:RepoRoot -Recurse -Include '*.bicep', '*.tf' -File
            $iac.Count | Should -Be 0
        }

        It 'KQL lock-contention query exists and uses projection/aggregation' {
            Test-Path $script:KqlPath | Should -BeTrue
            (Get-Content $script:KqlPath -Raw) | Should -Match 'where|summarize|project'
        }

        It 'README and runbooks contain zero internal sequence numbers or private orchestrator domains' {
            foreach ($f in @((Join-Path $script:RepoRoot 'README.md'), (Join-Path $script:RepoRoot 'runbooks/AVD-REGIONAL-FAILOVER.md'))) {
                $raw = Get-Content $f -Raw
                $raw | Should -Not -Match 'mvpfoundry\.alerasoul\.net|192\.142\.41\.43|Decision Pack 0|idea-012'
            }
        }
    }
}
