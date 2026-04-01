$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RunnerPath = Join-Path $RootDir 'scripts\run_incremental_update.ps1'
$BuildVocabularyPath = Join-Path $RootDir 'scripts\build_vocabulary.ps1'
$BuildVocabularySectionedPath = Join-Path $RootDir 'scripts\build_vocabulary_sectioned.ps1'
$BuildIncrementalReportPath = Join-Path $RootDir 'scripts\build_incremental_update_report.ps1'
$SourceRawPath = Join-Path $RootDir '1_vocabulary_raw.md'
$SourceTopicsPath = Join-Path $RootDir '3_topics.md'
$SourcePhrasesPath = Join-Path $RootDir '5_phrases.md'

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if (-not $Condition) { throw $Message }
}

function Invoke-RunnerForFixture {
  $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("run-incremental-update-test-" + [System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  try {
    $scriptsDir = Join-Path $tempRoot 'scripts'
    New-Item -ItemType Directory -Path $scriptsDir | Out-Null

    Copy-Item -LiteralPath $SourceRawPath -Destination (Join-Path $tempRoot '1_vocabulary_raw.md') -Force
    Copy-Item -LiteralPath $SourceTopicsPath -Destination (Join-Path $tempRoot '3_topics.md') -Force
    Copy-Item -LiteralPath $SourcePhrasesPath -Destination (Join-Path $tempRoot '5_phrases.md') -Force

    Copy-Item -LiteralPath $BuildVocabularyPath -Destination (Join-Path $scriptsDir 'build_vocabulary.ps1') -Force
    Copy-Item -LiteralPath $BuildVocabularySectionedPath -Destination (Join-Path $scriptsDir 'build_vocabulary_sectioned.ps1') -Force
    Copy-Item -LiteralPath $BuildIncrementalReportPath -Destination (Join-Path $scriptsDir 'build_incremental_update_report.ps1') -Force
    Copy-Item -LiteralPath $RunnerPath -Destination (Join-Path $scriptsDir 'run_incremental_update.ps1') -Force

    Push-Location $tempRoot
    try {
      & '.\scripts\build_vocabulary.ps1'
      $output = & '.\scripts\run_incremental_update.ps1'
      return ,@($output, $tempRoot)
    }
    finally {
      Pop-Location
    }
  }
  finally {
    if (Test-Path -LiteralPath $tempRoot) {
      Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
  }
}

function Test-RunIncrementalUpdateCreatesAndDeletesTempReport {
  $result = Invoke-RunnerForFixture
  $output = [string]$result[0]

  Assert-True ($output.Contains('=== incremental_update_report ===')) 'Expected runner output to contain the report marker.'

  $tempLine = ($output -split "(`r`n|`n|`r)" | Where-Object { $_ -like 'TEMP_DIR:*' } | Select-Object -First 1)
  Assert-True ($null -ne $tempLine -and $tempLine.Trim() -ne '') 'Expected runner output to include TEMP_DIR.'

  $tempDir = ($tempLine -replace '^TEMP_DIR:\s*', '').Trim()
  Assert-True ($tempDir -ne '') 'Expected TEMP_DIR value.'
  Assert-True (-not (Test-Path -LiteralPath $tempDir)) "Expected temp directory to be deleted: $tempDir"
}

$tests = @(
  'Test-RunIncrementalUpdateCreatesAndDeletesTempReport'
)

$failures = New-Object System.Collections.Generic.List[string]

foreach ($testName in $tests) {
  try {
    & $testName
    Write-Host "PASS $testName"
  }
  catch {
    $failures.Add("${testName}: $($_.Exception.Message)") | Out-Null
    Write-Host "FAIL $testName"
    Write-Host $_.Exception.Message
  }
}

if ($failures.Count -gt 0) {
  throw ($failures -join [Environment]::NewLine)
}

