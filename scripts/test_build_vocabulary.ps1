$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GeneratorPath = Join-Path $RootDir 'scripts\build_vocabulary.ps1'
$SectionedGeneratorPath = Join-Path $RootDir 'scripts\build_vocabulary_sectioned.ps1'
$SourceRawPath = Join-Path $RootDir '1_vocabulary_raw.md'

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Needle
  )

  if (-not $Text.Contains($Needle)) {
    throw "Expected generated vocabulary to contain: $Needle"
  }
}

function Invoke-GeneratorForFixture {
  $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vocabulary-test-" + [System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  try {
    $rawPath = Join-Path $tempRoot '1_vocabulary_raw.md'
    $outputPath = Join-Path $tempRoot '2_vocabulary.md'
    $scriptsDir = Join-Path $tempRoot 'scripts'
    $fixtureScript = Join-Path $tempRoot 'run_build_vocabulary.ps1'

    New-Item -ItemType Directory -Path $scriptsDir | Out-Null
    Copy-Item -LiteralPath $SourceRawPath -Destination $rawPath -Force
    Copy-Item -LiteralPath $GeneratorPath -Destination (Join-Path $scriptsDir 'build_vocabulary.ps1') -Force
    Copy-Item -LiteralPath $SectionedGeneratorPath -Destination (Join-Path $scriptsDir 'build_vocabulary_sectioned.ps1') -Force
    $fixtureLines = @(
      "`$ErrorActionPreference = 'Stop'",
      "& '.\scripts\build_vocabulary.ps1'"
    )
    [System.IO.File]::WriteAllLines($fixtureScript, $fixtureLines, [System.Text.Encoding]::UTF8)

    Push-Location $tempRoot
    try {
      & $fixtureScript
    }
    finally {
      Pop-Location
    }

    return [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::UTF8)
  }
  finally {
    if (Test-Path -LiteralPath $tempRoot) {
      Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
  }
}

function Test-BuildVocabularyProducesCleanSections {
  $result = Invoke-GeneratorForFixture

  Assert-Contains $result '# vocabulary'
  Assert-Contains $result '## Глаголы'
  Assert-Contains $result '## Цвета'
  Assert-Contains $result '| el colór | цвет |'
  Assert-Contains $result '| rójo | красный |'
  Assert-Contains $result '| morádo | фиолетовый |'
  Assert-Contains $result '## Грамматические таблицы'
  Assert-Contains $result '## Фразы (разговорное / кафе / быт)'
  if ($result.Contains('| Cerca = Al lado |') -or $result.Contains('| Dentro = en |') -or $result.Contains('| Encima = sobre |') -or $result.Contains('| valér = costár |')) {
    throw 'Expected generated vocabulary to skip legacy `=` aggregates.'
  }
}

$tests = @(
  'Test-BuildVocabularyProducesCleanSections'
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
