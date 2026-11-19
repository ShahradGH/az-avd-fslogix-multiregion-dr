<#
.SYNOPSIS
    Microsoft Graph v2.x identity resilience and cohort reconnection module for AVD & FSLogix DR.
.DESCRIPTION
    Validates Entra ID user licensing and account status prior to staggered AVD wave reconnection,
    inspects Entra ID sign-in logs for Conditional Access or token-replay anomalies during regional
    failover, and dispatches cohort reconnection notices via Microsoft Graph v1.0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-AvdGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [scriptblock]$GraphInvoker
    )

    if ($null -ne $GraphInvoker) {
        return & $GraphInvoker $Method $Uri $Body
    }

    $params = @{
        Method = $Method
        Uri    = $Uri
    }
    if ($null -ne $Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
        $params['ContentType'] = 'application/json'
    }

    return Invoke-MgGraphRequest @params
}

function Get-AvdSessionUserEntraContext {
    <#
    .SYNOPSIS
        Validates Entra ID account status and AVD/M365 licence eligibility before staggered wave reconnection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$UserPrincipalNames,

        [Parameter()]
        [scriptblock]$GraphInvoker
    )

    $eligible = [System.Collections.Generic.List[PSCustomObject]]::new()
    $blocked = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($upn in $UserPrincipalNames) {
        $encoded = [System.Uri]::EscapeDataString($upn)
        $uri = "https://graph.microsoft.com/v1.0/users/$encoded`?`$select=id,userPrincipalName,accountEnabled,assignedLicenses,userType"
        $user = Invoke-AvdGraphRequest -Method 'GET' -Uri $uri -GraphInvoker $GraphInvoker

        $licenceCount = @($user.assignedLicenses).Count
        $isEligible = ($user.accountEnabled -eq $true) -and ($licenceCount -gt 0) -and ($user.userType -ne 'Guest')

        $record = [PSCustomObject]@{
            UserPrincipalName = $user.userPrincipalName
            AccountEnabled    = [bool]$user.accountEnabled
            LicenceCount      = $licenceCount
            UserType          = $user.userType
            EligibleForWave   = $isEligible
        }

        if ($isEligible) { $eligible.Add($record) } else { $blocked.Add($record) }
    }

    return [PSCustomObject]@{
        TotalChecked   = $UserPrincipalNames.Count
        EligibleCount  = $eligible.Count
        BlockedCount   = $blocked.Count
        EligibleUsers  = $eligible.ToArray()
        BlockedUsers   = $blocked.ToArray()
        CheckedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Invoke-AvdConditionalAccessSignInCheck {
    <#
    .SYNOPSIS
        Queries Entra ID sign-in logs for Conditional Access failures or risky AVD sign-ins during DR failover.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppDisplayName,

        [Parameter()]
        [int]$Top = 50,

        [Parameter()]
        [scriptblock]$GraphInvoker
    )

    $filter = [System.Uri]::EscapeDataString("appDisplayName eq '$AppDisplayName'")
    $uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$filter&`$top=$Top"
    $resp = Invoke-AvdGraphRequest -Method 'GET' -Uri $uri -GraphInvoker $GraphInvoker
    $events = @($resp.value)

    $caFailures = @($events | Where-Object {
        $_.conditionalAccessStatus -eq 'failure' -or $_.riskLevelDuringSignIn -in @('high', 'medium')
    })

    return [PSCustomObject]@{
        AppDisplayName     = $AppDisplayName
        InspectedEvents    = $events.Count
        CaFailureCount     = $caFailures.Count
        StormAuthHealthy   = ($caFailures.Count -eq 0)
        FlaggedUsers       = @($caFailures | ForEach-Object { $_.userPrincipalName } | Select-Object -Unique)
        CheckedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Send-AvdCohortReconnectNotice {
    <#
    .SYNOPSIS
        Dispatches a staggered AVD wave reconnection notice to a Teams channel via Microsoft Graph.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$TeamId,

        [Parameter(Mandatory)]
        [string]$ChannelId,

        [Parameter(Mandatory)]
        [int]$WaveNumber,

        [Parameter(Mandatory)]
        [int]$BatchSize,

        [Parameter(Mandatory)]
        [int]$EstimatedWaitSeconds,

        [Parameter()]
        [scriptblock]$GraphInvoker
    )

    $uri = "https://graph.microsoft.com/v1.0/teams/$TeamId/channels/$ChannelId/messages"
    $payload = @{
        body = @{
            contentType = 'html'
            content     = "<b>AVD DR Reconnect Wave $WaveNumber</b> | Authorised Batch Size: $BatchSize users | Next Window: ${EstimatedWaitSeconds}s"
        }
    }

    if (-not $PSCmdlet.ShouldProcess("$TeamId/$ChannelId", "Send AVD DR Wave $WaveNumber notice")) {
        return [PSCustomObject]@{
            WaveNumber = $WaveNumber
            Dispatched = $false
            MessageId  = 'WHATIF-DRYRUN'
        }
    }

    $resp = Invoke-AvdGraphRequest -Method 'POST' -Uri $uri -Body $payload -GraphInvoker $GraphInvoker
    return [PSCustomObject]@{
        WaveNumber = $WaveNumber
        Dispatched = $true
        MessageId  = $resp.id
    }
}

Export-ModuleMember -Function @(
    'Get-AvdSessionUserEntraContext',
    'Invoke-AvdConditionalAccessSignInCheck',
    'Send-AvdCohortReconnectNotice'
)
