param(
  [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$VocabularyPath = Join-Path $RootDir '2_vocabulary.md'
$BuildVocabularyPath = Join-Path $RootDir 'scripts\build_vocabulary.ps1'
$BuildIncrementalReportPath = Join-Path $RootDir 'scripts\build_incremental_update_report.ps1'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("incremental-update-run-" + [System.Guid]::NewGuid().ToString('N'))
$oldVocabularyPath = Join-Path $tempRoot 'old_vocabulary.md'
$reportPath = Join-Path $tempRoot 'incremental_update_report.md'

New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
  if (Test-Path -LiteralPath $VocabularyPath) {
    Copy-Item -LiteralPath $VocabularyPath -Destination $oldVocabularyPath -Force
  }
  else {
    [System.IO.File]::WriteAllText($oldVocabularyPath, '', [System.Text.Encoding]::UTF8)
  }

  & $BuildVocabularyPath

  & $BuildIncrementalReportPath `
    -OldVocabularyPath $oldVocabularyPath `
    -OutputPath $reportPath

  Write-Output ("TEMP_DIR: {0}" -f $tempRoot)
  Write-Output '=== incremental_update_report ==='
  Write-Output (Get-Content -LiteralPath $reportPath -Raw)
  Write-Output '=== end incremental_update_report ==='
}
finally {
  if (-not $KeepTemp) {
    if (Test-Path -LiteralPath $tempRoot) {
      Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
  }
  else {
    Write-Output ("KEEP_TEMP: {0}" -f $tempRoot)
  }
}

