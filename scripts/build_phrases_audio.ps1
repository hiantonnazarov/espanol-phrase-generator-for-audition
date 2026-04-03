param(
  [string]$InputPath = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($InputPath -eq '') { $InputPath = Join-Path $RootDir '5_phrases.md' }
if ($OutputPath -eq '') { $OutputPath = Join-Path $RootDir '5_phrases_audio.md' }

function Get-CleanText {
  param([string]$Text)

  if ($null -eq $Text) { return '' }

  $value = $Text
  $value = $value -replace '[`*_]+', ''
  $value = $value -replace '[¿¡]', ''
  $value = $value -replace '[\\/]+', ' '
  $value = $value -replace '\s+', ' '
  return $value.Trim()
}

function Split-MarkdownRow {
  param([string]$Line)

  $trimmed = $Line.Trim()
  if (-not ($trimmed.StartsWith('|') -and $trimmed.EndsWith('|'))) {
    return @()
  }

  return @(
    $trimmed.Substring(1, $trimmed.Length - 2).Split('|') |
    ForEach-Object { Get-CleanText $_ }
  )
}

function Test-SeparatorRow {
  param([string[]]$Cells)

  if ($Cells.Count -eq 0) { return $false }
  foreach ($cell in $Cells) {
    if ($cell -eq '') { continue }
    if ($cell -notmatch '^:?-{3,}:?$') {
      return $false
    }
  }
  return $true
}

if (-not (Test-Path -LiteralPath $InputPath)) {
  throw "File not found: $InputPath"
}

$lines = [System.IO.File]::ReadAllLines((Resolve-Path $InputPath), [System.Text.Encoding]::UTF8)
$output = New-Object System.Collections.Generic.List[string]

foreach ($line in $lines) {
  $trimmed = $line.Trim()

  if ($trimmed -eq '') {
    $output.Add('') | Out-Null
    continue
  }

  if ($trimmed.StartsWith('|') -and $trimmed.EndsWith('|')) {
    $cells = [string[]]@(Split-MarkdownRow $line)
    if ((Test-SeparatorRow $cells)) {
      continue
    }

    $joined = (
      $cells |
      Where-Object { $_ -ne '' }
    ) -join ' '

    $output.Add($joined) | Out-Null
    continue
  }

  $output.Add((Get-CleanText $line)) | Out-Null
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and (-not (Test-Path -LiteralPath $outputDirectory))) {
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

[System.IO.File]::WriteAllLines($OutputPath, [string[]]$output, [System.Text.Encoding]::UTF8)
