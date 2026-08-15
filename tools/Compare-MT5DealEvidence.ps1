[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReferencePath,

    [Parameter(Mandatory)]
    [string]$CandidatePath,

    [string]$DifferenceReportPath,

    [decimal]$PriceTolerance = 0,

    [decimal]$VolumeTolerance = 0,

    [decimal]$MoneyTolerance = 0.01,

    [long]$TimeToleranceMilliseconds = 0,

    [switch]$CompareIdentifiers,

    [switch]$FailOnDifference
)

$ErrorActionPreference = 'Stop'
$invariant = [Globalization.CultureInfo]::InvariantCulture
$expectedColumns = @(
    'event_index',
    'server_time',
    'time_msc',
    'symbol',
    'deal_type',
    'entry_type',
    'reason',
    'volume',
    'price',
    'sl',
    'tp',
    'commission',
    'fee',
    'swap',
    'profit',
    'magic',
    'deal_ticket',
    'order_ticket',
    'position_id'
)

function Resolve-EvidenceFile {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    $item = Get-Item -LiteralPath $resolved.Path
    if ($item.PSIsContainer) {
        throw "Evidence path is not a file: $Path"
    }
    return $resolved.Path
}

function Import-EvidenceCsv {
    param([Parameter(Mandatory)][string]$Path)

    $header = Get-Content -LiteralPath $Path -TotalCount 1 -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($header)) {
        throw "Evidence CSV is empty: $Path"
    }

    $observedColumns = @($header -split ',' | ForEach-Object {
            $_.Trim().Trim('"')
        })
    if ($observedColumns.Count -ne $expectedColumns.Count) {
        throw "Evidence CSV has $($observedColumns.Count) columns; expected $($expectedColumns.Count): $Path"
    }
    for ($index = 0; $index -lt $expectedColumns.Count; $index++) {
        if ($observedColumns[$index] -cne $expectedColumns[$index]) {
            throw "Evidence CSV column $($index + 1) is '$($observedColumns[$index])'; expected '$($expectedColumns[$index])': $Path"
        }
    }

    return @(Import-Csv -LiteralPath $Path -Encoding utf8)
}

function Convert-ToDecimal {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Field,
        [Parameter(Mandatory)][int]$Row,
        [Parameter(Mandatory)][string]$Path
    )

    $parsed = 0D
    if (-not [decimal]::TryParse(
            $Value,
            [Globalization.NumberStyles]::Float,
            $invariant,
            [ref]$parsed
        )) {
        throw "Invalid decimal '$Value' in $Field at data row ${Row}: $Path"
    }
    return $parsed
}

function Convert-ToInt64 {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Field,
        [Parameter(Mandatory)][int]$Row,
        [Parameter(Mandatory)][string]$Path
    )

    $parsed = 0L
    if (-not [long]::TryParse(
            $Value,
            [Globalization.NumberStyles]::Integer,
            $invariant,
            [ref]$parsed
        )) {
        throw "Invalid integer '$Value' in $Field at data row ${Row}: $Path"
    }
    return $parsed
}

if ($PriceTolerance -lt 0 -or $VolumeTolerance -lt 0 -or
    $MoneyTolerance -lt 0 -or $TimeToleranceMilliseconds -lt 0) {
    throw 'Comparison tolerances must be zero or positive.'
}

$referenceFile = Resolve-EvidenceFile -Path $ReferencePath
$candidateFile = Resolve-EvidenceFile -Path $CandidatePath
$referenceRows = Import-EvidenceCsv -Path $referenceFile
$candidateRows = Import-EvidenceCsv -Path $candidateFile

$differences = [Collections.Generic.List[object]]::new()

function Add-Difference {
    param(
        [int]$Row,
        [string]$Field,
        [string]$Reference,
        [string]$Candidate,
        [string]$Delta,
        [string]$Tolerance,
        [string]$Kind
    )

    $differences.Add([pscustomobject]@{
            row = $Row
            field = $Field
            reference = $Reference
            candidate = $Candidate
            delta = $Delta
            tolerance = $Tolerance
            kind = $Kind
        })
}

$sharedCount = [Math]::Min($referenceRows.Count, $candidateRows.Count)
$categoricalFields = @('symbol', 'deal_type', 'entry_type', 'reason', 'magic')
$numericFields = @(
    @{ Name = 'volume'; Tolerance = $VolumeTolerance },
    @{ Name = 'price'; Tolerance = $PriceTolerance },
    @{ Name = 'sl'; Tolerance = $PriceTolerance },
    @{ Name = 'tp'; Tolerance = $PriceTolerance },
    @{ Name = 'commission'; Tolerance = $MoneyTolerance },
    @{ Name = 'fee'; Tolerance = $MoneyTolerance },
    @{ Name = 'swap'; Tolerance = $MoneyTolerance },
    @{ Name = 'profit'; Tolerance = $MoneyTolerance }
)

for ($index = 0; $index -lt $sharedCount; $index++) {
    $rowNumber = $index + 1
    $reference = $referenceRows[$index]
    $candidate = $candidateRows[$index]

    foreach ($field in $categoricalFields) {
        $referenceValue = [string]$reference.$field
        $candidateValue = [string]$candidate.$field
        if ($referenceValue -cne $candidateValue) {
            Add-Difference -Row $rowNumber -Field $field `
                -Reference $referenceValue -Candidate $candidateValue `
                -Delta '' -Tolerance 'exact' -Kind 'categorical'
        }
    }

    $referenceTime = Convert-ToInt64 -Value ([string]$reference.time_msc) `
        -Field 'time_msc' -Row $rowNumber -Path $referenceFile
    $candidateTime = Convert-ToInt64 -Value ([string]$candidate.time_msc) `
        -Field 'time_msc' -Row $rowNumber -Path $candidateFile
    $timeDelta = [Math]::Abs($candidateTime - $referenceTime)
    if ($timeDelta -gt $TimeToleranceMilliseconds) {
        Add-Difference -Row $rowNumber -Field 'time_msc' `
            -Reference ([string]$reference.time_msc) `
            -Candidate ([string]$candidate.time_msc) `
            -Delta ([string]$timeDelta) `
            -Tolerance ([string]$TimeToleranceMilliseconds) -Kind 'time'
    }

    foreach ($fieldDefinition in $numericFields) {
        $field = [string]$fieldDefinition.Name
        $tolerance = [decimal]$fieldDefinition.Tolerance
        $referenceValue = Convert-ToDecimal `
            -Value ([string]$reference.$field) -Field $field `
            -Row $rowNumber -Path $referenceFile
        $candidateValue = Convert-ToDecimal `
            -Value ([string]$candidate.$field) -Field $field `
            -Row $rowNumber -Path $candidateFile
        $delta = [Math]::Abs($candidateValue - $referenceValue)
        if ($delta -gt $tolerance) {
            Add-Difference -Row $rowNumber -Field $field `
                -Reference ($referenceValue.ToString($invariant)) `
                -Candidate ($candidateValue.ToString($invariant)) `
                -Delta ($delta.ToString($invariant)) `
                -Tolerance ($tolerance.ToString($invariant)) -Kind 'numeric'
        }
    }

    if ($CompareIdentifiers) {
        foreach ($field in @('deal_ticket', 'order_ticket', 'position_id')) {
            $referenceValue = [string]$reference.$field
            $candidateValue = [string]$candidate.$field
            if ($referenceValue -cne $candidateValue) {
                Add-Difference -Row $rowNumber -Field $field `
                    -Reference $referenceValue -Candidate $candidateValue `
                    -Delta '' -Tolerance 'exact' -Kind 'identifier'
            }
        }
    }
}

if ($referenceRows.Count -ne $candidateRows.Count) {
    $largerCount = [Math]::Max($referenceRows.Count, $candidateRows.Count)
    for ($index = $sharedCount; $index -lt $largerCount; $index++) {
        $rowNumber = $index + 1
        $referenceValue = if ($index -lt $referenceRows.Count) {
            [string]$referenceRows[$index].event_index
        }
        else { '<missing>' }
        $candidateValue = if ($index -lt $candidateRows.Count) {
            [string]$candidateRows[$index].event_index
        }
        else { '<missing>' }
        Add-Difference -Row $rowNumber -Field 'row_presence' `
            -Reference $referenceValue -Candidate $candidateValue `
            -Delta '' -Tolerance 'exact' -Kind 'row_count'
    }
}

if (-not [string]::IsNullOrWhiteSpace($DifferenceReportPath)) {
    $reportDirectory = Split-Path -Parent $DifferenceReportPath
    if (-not [string]::IsNullOrWhiteSpace($reportDirectory) -and
        -not (Test-Path -LiteralPath $reportDirectory -PathType Container)) {
        throw "Difference report directory does not exist: $reportDirectory"
    }
    if ($differences.Count -gt 0) {
        $differences | Export-Csv -LiteralPath $DifferenceReportPath `
            -NoTypeInformation -Encoding utf8
    }
    else {
        [IO.File]::WriteAllText(
            [IO.Path]::GetFullPath($DifferenceReportPath),
            '"row","field","reference","candidate","delta","tolerance","kind"' + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false)
        )
    }
}

$summary = [pscustomobject]@{
    reference_rows = $referenceRows.Count
    candidate_rows = $candidateRows.Count
    shared_rows_compared = $sharedCount
    difference_count = $differences.Count
    matched = ($differences.Count -eq 0)
    identifiers_compared = [bool]$CompareIdentifiers
    price_tolerance = $PriceTolerance
    volume_tolerance = $VolumeTolerance
    money_tolerance = $MoneyTolerance
    time_tolerance_ms = $TimeToleranceMilliseconds
    claim_boundary = 'ordinal_field_comparison_only_no_signal_fill_or_performance_proof'
}

$summary
if ($differences.Count -gt 0) {
    $differences
}

if ($FailOnDifference -and $differences.Count -gt 0) {
    exit 2
}
