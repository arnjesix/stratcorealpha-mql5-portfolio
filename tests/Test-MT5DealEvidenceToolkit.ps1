[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'src\SCA_MT5DealEvidenceExporter.mq5'
$comparatorPath = Join-Path $root 'tools\Compare-MT5DealEvidence.ps1'
$reporterPath = Join-Path $root 'tools\New-MT5DealEvidenceReport.ps1'
$docPath = Join-Path $root 'docs\MT5_DEAL_EVIDENCE_TOOLKIT.md'
$buyerGuidePath = Join-Path $root `
    'docs\MT5_EXECUTION_RECONCILIATION_BUYER_GUIDE.md'
$samplePath = Join-Path $root `
    'docs\evidence\MT5_Execution_Reconciliation_Sample.html'
$coverPath = Join-Path $root `
    'assets\mt5-deal-evidence-exporter-cover-750x500.png'
$previewPath = Join-Path $root `
    'assets\mt5-execution-reconciliation-synthetic-preview.png'
$fixtures = Join-Path $root 'tests\fixtures\mt5-deal-evidence'
$referencePath = Join-Path $fixtures 'reference.sample.csv'
$matchPath = Join-Path $fixtures 'candidate-match.sample.csv'
$driftPath = Join-Path $fixtures 'candidate-drift.sample.csv'

foreach ($path in @(
        $sourcePath,
        $comparatorPath,
        $reporterPath,
        $docPath,
        $buyerGuidePath,
        $samplePath,
        $coverPath,
        $previewPath,
        $referencePath,
        $matchPath,
        $driftPath
    )) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Toolkit input missing: $path"
    }
}

$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8
foreach ($required in @(
        'HistorySelect(',
        'HistoryDealGetTicket(',
        'FileOpen(',
        'FILE_WRITE',
        'read_only_no_account_id_no_order_action_no_performance_claim'
    )) {
    if (-not $source.Contains($required)) {
        throw "Exporter source lacks required operation or boundary: $required"
    }
}
foreach ($prohibited in @(
        '(?i)\bOrderSend\s*\(',
        '(?i)\bCTrade\b',
        '(?i)\bPosition(Open|Close|Modify)\s*\(',
        '(?i)\bOrder(Open|Close|Delete|Modify)\s*\(',
        '(?i)\bAccountInfo(Integer|Double|String)\s*\(',
        '(?i)\bACCOUNT_(LOGIN|NAME|SERVER|COMPANY)\b',
        '(?i)\bDEAL_(EXTERNAL_ID|COMMENT)\b',
        '(?i)\bWebRequest\s*\(',
        '(?im)^\s*#import\b'
    )) {
    if ($source -match $prohibited) {
        throw "Exporter source contains prohibited API or field: $prohibited"
    }
}

$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
if ($sourceHash -ne
    '9D894D572437946F361F69576679D92290A92109C17DCB31565EB669CD04AF77') {
    throw "Unexpected exporter source hash: $sourceHash"
}

$matchOutput = @(& $comparatorPath -ReferencePath $referencePath `
        -CandidatePath $matchPath)
$matchSummary = $matchOutput | Where-Object {
    $_.PSObject.Properties.Name -contains 'matched'
} | Select-Object -First 1
if (-not $matchSummary.matched -or $matchSummary.difference_count -ne 0) {
    throw 'Toolkit comparator failed its match fixture.'
}

$driftOutput = @(& $comparatorPath -ReferencePath $referencePath `
        -CandidatePath $driftPath -PriceTolerance 0.00001 `
        -MoneyTolerance 0.01 -TimeToleranceMilliseconds 500)
$driftSummary = $driftOutput | Where-Object {
    $_.PSObject.Properties.Name -contains 'matched'
} | Select-Object -First 1
$driftFields = @($driftOutput | Where-Object {
        $_.PSObject.Properties.Name -contains 'field'
    } | Select-Object -ExpandProperty field -Unique)
if ($driftSummary.matched -or $driftSummary.difference_count -ne 5) {
    throw 'Toolkit comparator failed its five-difference fixture.'
}
foreach ($field in @('time_msc', 'price', 'reason', 'profit', 'row_presence')) {
    if ($driftFields -notcontains $field) {
        throw "Toolkit comparator did not report: $field"
    }
}

$tempReport = Join-Path ([IO.Path]::GetTempPath()) `
    ('sca-mt5-toolkit-{0}.html' -f [guid]::NewGuid().ToString('N'))
try {
    $reportResult = & $reporterPath -ReferencePath $referencePath `
        -CandidatePath $driftPath -OutputPath $tempReport `
        -ReferenceLabel 'Synthetic tester reference' `
        -CandidateLabel 'Synthetic demo candidate' `
        -PriceTolerance 0.00001 -MoneyTolerance 0.01 `
        -TimeToleranceMilliseconds 500
    if ($reportResult.DifferenceCount -ne 5 -or $reportResult.Matched) {
        throw 'Toolkit HTML report returned the wrong fixture result.'
    }
    $html = Get-Content -LiteralPath $tempReport -Raw -Encoding utf8
    if ($html -notmatch '5 differences require review' -or
        $html -notmatch 'ordinal position' -or
        $html -match '(?i)<script\b|https?://|file://|C:\\Users\\') {
        throw 'Toolkit HTML report is incomplete or contains an unsafe route.'
    }
}
finally {
    if (Test-Path -LiteralPath $tempReport -PathType Leaf) {
        Remove-Item -LiteralPath $tempReport -Force
    }
}

$sample = Get-Content -LiteralPath $samplePath -Raw -Encoding utf8
if ($sample -notmatch '5 differences require review' -or
    $sample -match '(?i)<script\b|https?://|file://|C:\\Users\\') {
    throw 'Published synthetic report is incomplete or unsafe.'
}

$buyerGuide = Get-Content -LiteralPath $buyerGuidePath -Raw -Encoding utf8
$buyerGuideLinks = @([regex]::Matches($buyerGuide, 'https://github\.com/arnjesix/stratcorealpha-mql5-portfolio/'))
if ($buyerGuide -notmatch 'Five differences that lead to different investigations' -or
    $buyerGuide -notmatch 'A bounded first milestone' -or
    $buyerGuide -notmatch 'It is not\s+investment advice' -or
    $buyerGuideLinks.Count -ne 3 -or
    $buyerGuide -match '(?i)guaranteed? profit|C:\\Users\\|AppData|password\s*[:=]') {
    throw 'Buyer guide is incomplete, unbounded or contains unsafe text.'
}

Add-Type -AssemblyName System.Drawing
$cover = [Drawing.Image]::FromFile($coverPath)
try {
    if ($cover.Width -ne 750 -or $cover.Height -ne 500) {
        throw "Toolkit cover has wrong dimensions: $($cover.Width)x$($cover.Height)"
    }
}
finally {
    $cover.Dispose()
}

$preview = [Drawing.Image]::FromFile($previewPath)
try {
    if ($preview.Width -ne 1518 -or $preview.Height -ne 780) {
        throw "Synthetic preview has wrong dimensions: $($preview.Width)x$($preview.Height)"
    }
}
finally {
    $preview.Dispose()
}

[pscustomobject]@{
    SourceHash = $sourceHash
    TransactionApis = 0
    AccountIdentityFields = 0
    MatchDifferences = 0
    DriftDifferences = 5
    HtmlExternalRoutes = 0
    Cover = '750x500'
    Preview = '1518x780'
    BuyerGuideLinks = $buyerGuideLinks.Count
    Passed = $true
}
