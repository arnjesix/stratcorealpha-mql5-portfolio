[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $root `
    '.github\ISSUE_TEMPLATE\mt5-execution-reconciliation.yml'
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Issue form missing: $templatePath"
}

$form = Get-Content -LiteralPath $templatePath -Raw -Encoding utf8
foreach ($required in @(
        'name: MT5 execution reconciliation scope',
        'id: evidence_format',
        'id: reference_identity',
        'id: candidate_identity',
        'id: frozen_scope',
        'id: tolerances',
        'id: expected_match',
        'id: suspected_divergence',
        'id: public_request_confirmation',
        'This issue is public',
        'Do not paste or attach proprietary source code',
        'templates/MT5_EXECUTION_RECONCILIATION_SCOPE_TEMPLATE.md',
        'private evidence must stay on an approved funded project route',
        'does not prove historical fillability, broker parity, profitability or future performance'
    )) {
    if (-not $form.Contains($required)) {
        throw "Issue form lacks required field or safety gate: $required"
    }
}

$ids = @([regex]::Matches($form, '(?m)^    id: ([a-z0-9_]+)$') |
    ForEach-Object { $_.Groups[1].Value })
if ($ids.Count -ne 8 -or @($ids | Sort-Object -Unique).Count -ne 8) {
    throw "Issue form has $($ids.Count) IDs and requires eight unique IDs."
}

$requiredValidations = @([regex]::Matches(
        $form,
        '(?m)^(?:      |          )required: true$'
    )).Count
if ($requiredValidations -ne 11) {
    throw "Issue form has $requiredValidations required validations; expected 11."
}

if ($form -match '(?i)\b(upload|attach)\s+(?:your\s+)?(?:source|set|history)|account\s+(?:number|login)\s*[:=]') {
    throw 'Issue form appears to request a private file or account identity.'
}

[pscustomobject]@{
    UniqueFields = 8
    RequiredValidations = 11
    PrivateFileRequests = 0
    AccountIdentityRequests = 0
    ScopeTemplateLinked = $true
    Passed = $true
}
