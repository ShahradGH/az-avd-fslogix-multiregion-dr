<#
.SYNOPSIS
    Posts AVD FSLogix multi-region failover status to a Microsoft Teams Ops Bridge channel via Graph v1.0.
.DESCRIPTION
    Dispatches an Adaptive Card summarising AI IOPS saturation triage, fenced SMB lease release counts,
    and staggered hostpool batch release cadence via Invoke-MgGraphRequest.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TeamId,

    [Parameter(Mandatory)]
    [string]$ChannelId,

    [Parameter(Mandatory)]
    [PSCustomObject]$TriageResult,

    [Parameter(Mandatory)]
    [int]$HandlesReleased,

    [Parameter()]
    [scriptblock]$GraphInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$card = @{
    '$schema' = 'http://adaptivecards.io/schemas/adaptive-card.json'
    type      = 'AdaptiveCard'
    version   = '1.5'
    body      = @(
        @{
            type   = 'TextBlock'
            text   = "AVD FSLogix DR Bridge: $($TriageResult.PrimaryHostPool)"
            weight = 'Bolder'
            size   = 'Medium'
        },
        @{
            type  = 'FactSet'
            facts = @(
                @{ title = 'Root Cause'; value = $TriageResult.RootCauseCode },
                @{ title = 'Action'; value = $TriageResult.RecommendedAction },
                @{ title = 'Safe To Failover'; value = "$($TriageResult.SafeToFailover)" },
                @{ title = 'Predicted Peak IOPS %'; value = "$($TriageResult.PredictedPeakIopsPct)%" },
                @{ title = 'Optimal Batch Size'; value = "$($TriageResult.OptimalBatchSize) users / $($TriageResult.BatchIntervalSeconds)s" },
                @{ title = 'Fenced VHDX Handles Closed'; value = "$HandlesReleased" }
            )
        }
    )
}

$body = @{
    body        = @{
        contentType = 'html'
        content     = '<attachment id="avdDrStatusCard"></attachment>'
    }
    attachments = @(
        @{
            id          = 'avdDrStatusCard'
            contentType = 'application/vnd.microsoft.card.adaptive'
            content     = ($card | ConvertTo-Json -Depth 10 -Compress)
        }
    )
}

$uri = "https://graph.microsoft.com/v1.0/teams/$TeamId/channels/$ChannelId/messages"
$resp = $null

if ($PSCmdlet.ShouldProcess("Teams Ops Bridge $ChannelId", 'Post AVD Failover Status Card')) {
    if ($null -ne $GraphInvoker) {
        $resp = & $GraphInvoker 'POST' $uri $body
    }
    else {
        $resp = Invoke-MgGraphRequest -Method Post -Uri $uri -Body ($body | ConvertTo-Json -Depth 12) -ContentType 'application/json'
    }
}

return [PSCustomObject]@{
    PrimaryHostPool = $TriageResult.PrimaryHostPool
    ChannelUri      = $uri
    MessageId       = if ($null -ne $resp -and $resp.id) { $resp.id } else { 'whatif-msg' }
    PostedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
}
