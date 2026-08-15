[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReferencePath,

    [Parameter(Mandatory)]
    [string]$CandidatePath,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [string]$ReferenceLabel = 'Reference export',

    [string]$CandidateLabel = 'Candidate export',

    [decimal]$PriceTolerance = 0,

    [decimal]$VolumeTolerance = 0,

    [decimal]$MoneyTolerance = 0.01,

    [long]$TimeToleranceMilliseconds = 0,

    [switch]$CompareIdentifiers
)

$ErrorActionPreference = 'Stop'
$comparatorPath = Join-Path $PSScriptRoot 'Compare-MT5DealEvidence.ps1'
if (-not (Test-Path -LiteralPath $comparatorPath -PathType Leaf)) {
    throw "Comparator missing: $comparatorPath"
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and
    -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    throw "Report directory does not exist: $outputDirectory"
}

$referenceFile = (Resolve-Path -LiteralPath $ReferencePath -ErrorAction Stop).Path
$candidateFile = (Resolve-Path -LiteralPath $CandidatePath -ErrorAction Stop).Path
$referenceHash = (Get-FileHash -LiteralPath $referenceFile -Algorithm SHA256).Hash
$candidateHash = (Get-FileHash -LiteralPath $candidateFile -Algorithm SHA256).Hash

$comparison = @(& $comparatorPath `
        -ReferencePath $referenceFile `
        -CandidatePath $candidateFile `
        -PriceTolerance $PriceTolerance `
        -VolumeTolerance $VolumeTolerance `
        -MoneyTolerance $MoneyTolerance `
        -TimeToleranceMilliseconds $TimeToleranceMilliseconds `
        -CompareIdentifiers:$CompareIdentifiers)
$summary = $comparison | Where-Object {
    $_.PSObject.Properties.Name -contains 'matched'
} | Select-Object -First 1
$differences = @($comparison | Where-Object {
        $_.PSObject.Properties.Name -contains 'field'
    })
if ($null -eq $summary) {
    throw 'Comparator did not return a summary.'
}

function Encode-Html {
    param([AllowNull()][object]$Value)

    return [Net.WebUtility]::HtmlEncode([string]$Value)
}

$statusClass = if ($summary.matched) { 'match' } else { 'drift' }
$statusText = if ($summary.matched) {
    'No differences under this contract'
}
else {
    "$($summary.difference_count) differences require review"
}

$differenceRows = if ($differences.Count -eq 0) {
    '<tr><td colspan="7" class="empty">No field difference exceeded the supplied tolerances.</td></tr>'
}
else {
    ($differences | ForEach-Object {
            '<tr>' +
            '<td>' + (Encode-Html $_.row) + '</td>' +
            '<td><strong>' + (Encode-Html $_.field) + '</strong></td>' +
            '<td><code>' + (Encode-Html $_.reference) + '</code></td>' +
            '<td><code>' + (Encode-Html $_.candidate) + '</code></td>' +
            '<td><code>' + (Encode-Html $_.delta) + '</code></td>' +
            '<td><code>' + (Encode-Html $_.tolerance) + '</code></td>' +
            '<td>' + (Encode-Html $_.kind) + '</td>' +
            '</tr>'
        }) -join "`n"
}

$html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MT5 Deal Evidence Reconciliation</title>
  <style>
    :root { color-scheme: dark; --bg:#07111f; --panel:#0d1a2b; --line:#29445f; --text:#edf4fb; --muted:#9fb2c6; --teal:#42d3c6; --orange:#ffb66e; --blue:#62a8ff; }
    * { box-sizing: border-box; }
    body { margin:0; background:linear-gradient(145deg,#07111f,#132640); color:var(--text); font:15px/1.5 "Segoe UI",Arial,sans-serif; }
    main { max-width:1180px; margin:0 auto; padding:54px 38px 70px; }
    .eyebrow { color:#88a1ba; font-weight:800; letter-spacing:.14em; text-transform:uppercase; }
    h1 { margin:10px 0 8px; font-size:42px; line-height:1.12; }
    .subtitle { margin:0 0 26px; color:var(--muted); font-size:19px; }
    .status { display:inline-flex; align-items:center; gap:10px; padding:10px 16px; border-radius:999px; font-weight:800; }
    .status.match { color:#bff7f1; border:1px solid #27877f; background:#0b302f; }
    .status.drift { color:#ffe0bd; border:1px solid #9a6332; background:#352313; }
    .status::before { content:""; width:10px; height:10px; border-radius:50%; background:currentColor; }
    .cards { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:14px; margin:28px 0; }
    .card,.panel { background:rgba(10,24,41,.94); border:1px solid var(--line); border-radius:18px; }
    .card { padding:18px; }
    .card span { display:block; color:var(--muted); font-size:12px; font-weight:800; letter-spacing:.08em; text-transform:uppercase; }
    .card strong { display:block; margin-top:6px; font-size:26px; }
    .panel { margin-top:18px; padding:24px; }
    h2 { margin:0 0 16px; font-size:22px; }
    .inputs { display:grid; grid-template-columns:1fr 1fr; gap:16px; }
    .input { padding:16px; background:#0a1524; border:1px solid #233c56; border-radius:13px; }
    .input b { display:block; margin-bottom:8px; color:#d9e7f5; }
    .hash { color:#88a4bd; font:12px/1.45 Consolas,monospace; word-break:break-all; }
    table { width:100%; border-collapse:collapse; font-size:13px; }
    th { color:#89a5bf; background:#142b45; text-align:left; text-transform:uppercase; letter-spacing:.05em; font-size:11px; }
    th,td { padding:12px 10px; border-bottom:1px solid #1d354d; vertical-align:top; }
    code { color:#d3e2f0; font:12px Consolas,monospace; white-space:nowrap; }
    .empty { color:#a9c4bf; text-align:center; padding:30px; }
    .contract { display:grid; grid-template-columns:repeat(4,1fr); gap:10px; margin:0; padding:0; list-style:none; }
    .contract li { background:#0a1524; border:1px solid #223c55; border-radius:12px; padding:12px; }
    .contract small { display:block; color:var(--muted); }
    .boundary { margin-top:20px; padding:17px 19px; border-left:4px solid var(--blue); background:#0b1829; color:#b7c9da; }
    footer { margin-top:28px; color:#718ba5; font-size:12px; }
    @media (max-width:800px) { .cards,.contract { grid-template-columns:1fr 1fr; } .inputs { grid-template-columns:1fr; } main { padding:30px 18px; } .panel { overflow-x:auto; } }
  </style>
</head>
<body>
<main>
  <div class="eyebrow">StratCoreAlpha • Execution evidence</div>
  <h1>MT5 Deal Evidence Reconciliation</h1>
  <p class="subtitle">Deterministic ordinal comparison under an explicit field and tolerance contract.</p>
  <div class="status $statusClass">$(Encode-Html $statusText)</div>

  <section class="cards" aria-label="comparison summary">
    <div class="card"><span>Reference rows</span><strong>$(Encode-Html $summary.reference_rows)</strong></div>
    <div class="card"><span>Candidate rows</span><strong>$(Encode-Html $summary.candidate_rows)</strong></div>
    <div class="card"><span>Rows compared</span><strong>$(Encode-Html $summary.shared_rows_compared)</strong></div>
    <div class="card"><span>Differences</span><strong>$(Encode-Html $summary.difference_count)</strong></div>
  </section>

  <section class="panel">
    <h2>Evidence inputs</h2>
    <div class="inputs">
      <div class="input"><b>$(Encode-Html $ReferenceLabel)</b><div class="hash">SHA-256 $(Encode-Html $referenceHash)</div></div>
      <div class="input"><b>$(Encode-Html $CandidateLabel)</b><div class="hash">SHA-256 $(Encode-Html $candidateHash)</div></div>
    </div>
  </section>

  <section class="panel">
    <h2>Comparison contract</h2>
    <ul class="contract">
      <li><small>Time tolerance</small><b>$(Encode-Html $summary.time_tolerance_ms) ms</b></li>
      <li><small>Price tolerance</small><b>$(Encode-Html $summary.price_tolerance)</b></li>
      <li><small>Volume tolerance</small><b>$(Encode-Html $summary.volume_tolerance)</b></li>
      <li><small>Cash tolerance</small><b>$(Encode-Html $summary.money_tolerance)</b></li>
    </ul>
  </section>

  <section class="panel">
    <h2>Field differences</h2>
    <table>
      <thead><tr><th>Row</th><th>Field</th><th>Reference</th><th>Candidate</th><th>Delta</th><th>Tolerance</th><th>Kind</th></tr></thead>
      <tbody>$differenceRows</tbody>
    </table>
  </section>

  <div class="boundary"><strong>Evidence boundary.</strong> This report compares rows by ordinal position and reports stored deal-history fields only. It does not realign shifted event sequences, reconstruct unfilled signals, prove historical fillability, establish broker parity or support any profitability or future-performance claim. MT5 deal, order and position identifiers were $(if ($summary.identifiers_compared) { 'included' } else { 'ignored' }) under this comparison contract.</div>
  <footer>No account path, login, account name, broker identity or credential is embedded in this report. Review all displayed deal values before distribution.</footer>
</main>
</body>
</html>
"@

[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($OutputPath),
    $html,
    [Text.UTF8Encoding]::new($false)
)

[pscustomobject]@{
    OutputPath = [IO.Path]::GetFullPath($OutputPath)
    ReferenceRows = $summary.reference_rows
    CandidateRows = $summary.candidate_rows
    DifferenceCount = $summary.difference_count
    Matched = $summary.matched
    IdentifiersCompared = $summary.identifiers_compared
    ClaimBoundary = $summary.claim_boundary
}
