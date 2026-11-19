@{
    RootModule        = 'AvdIdentityResilience.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '11111111-2222-3333-4444-555555550002'
    Author            = 'ShahradGH'
    CompanyName       = 'Independent Architecture'
    Copyright         = '(c) ShahradGH. MIT License.'
    Description       = 'Microsoft Graph v2.x Entra ID user licence validation, Conditional Access sign-in inspection, and AVD DR wave reconnection notices.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Get-AvdSessionUserEntraContext',
        'Invoke-AvdConditionalAccessSignInCheck',
        'Send-AvdCohortReconnectNotice'
    )
}
