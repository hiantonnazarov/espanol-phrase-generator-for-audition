$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GeneratorPath = Join-Path $RootDir 'scripts\build_phrases_audio.ps1'

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Needle
  )

  if (-not $Text.Contains($Needle)) {
    throw "Expected output to contain: $Needle"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Needle
  )

  if ($Text.Contains($Needle)) {
    throw "Expected output not to contain: $Needle"
  }
}

function Invoke-GeneratorForFixture {
  param([string]$PhrasesText)

  $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("phrases-audio-test-" + [System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  try {
    $inputPath = Join-Path $tempRoot '5_phrases.md'
    $outputPath = Join-Path $tempRoot '5_phrases_audio.md'

    [System.IO.File]::WriteAllText($inputPath, ($PhrasesText.Trim() + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    & $GeneratorPath -InputPath $inputPath -OutputPath $outputPath
    return [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::UTF8)
  }
  finally {
    if (Test-Path -LiteralPath $tempRoot) {
      Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
  }
}

function Test-FlattensMarkdownTablesIntoPlainLines {
  $output = Invoke-GeneratorForFixture @'
# Фразы по темам

## 1. Presente
| yo | háblo |
| tú | háblas |

| tú puédes escuchár hoy. | Ты можешь слушать сегодня. |
'@

  Assert-Contains $output '# Фразы по темам'
  Assert-Contains $output '## 1. Presente'
  Assert-Contains $output 'yo háblo'
  Assert-Contains $output 'tú háblas'
  Assert-Contains $output 'tú puédes escuchár hoy. Ты можешь слушать сегодня.'
  Assert-NotContains $output '| yo |'
}

function Test-StripsMarkdownNoiseAndNormalizesSpacing {
  $output = Invoke-GeneratorForFixture @'
# Тест

## 2. Формат
| `lo` \ `la` | его / это |
| **¿quién?** | *Кто?* |
| uno   |   dos |
'@

  Assert-Contains $output 'lo la его это'
  Assert-Contains $output 'quién? Кто?'
  Assert-Contains $output 'uno dos'
  Assert-NotContains $output '`'
  Assert-NotContains $output '**'
  Assert-NotContains $output '¿'
  Assert-NotContains $output ' / '
}

function Test-PreservesBlankLinesAndMixedSectionContent {
  $output = Invoke-GeneratorForFixture @'
# Фразы

## 3. Секция
Общая инфа по теме

| Испанский | Перевод |
| --- | --- |
| Me llamo Ana. | Меня зовут Аня. |

После таблицы
'@

  Assert-Contains $output "## 3. Секция`r`nОбщая инфа по теме"
  Assert-Contains $output "Общая инфа по теме`r`n`r`nИспанский Перевод"
  Assert-Contains $output "Me llamo Ana. Меня зовут Аня."
  Assert-Contains $output "Me llamo Ana. Меня зовут Аня.`r`n`r`nПосле таблицы"
  Assert-NotContains $output '| --- | --- |'
}

$tests = @(
  'Test-FlattensMarkdownTablesIntoPlainLines',
  'Test-StripsMarkdownNoiseAndNormalizesSpacing',
  'Test-PreservesBlankLinesAndMixedSectionContent'
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
