$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GeneratorPath = Join-Path $RootDir 'scripts\build_incremental_update_report.ps1'

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Needle
  )

  if (-not $Text.Contains($Needle)) {
    throw "Expected report to contain: $Needle"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Needle
  )

  if ($Text.Contains($Needle)) {
    throw "Expected report not to contain: $Needle"
  }
}

function Get-ReportSection {
  param(
    [string]$Text,
    [string]$Heading,
    [string]$NextHeading
  )

  $start = $Text.IndexOf($Heading, [System.StringComparison]::Ordinal)
  if ($start -lt 0) {
    throw "Section not found: $Heading"
  }

  $sliceStart = $start + $Heading.Length
  $end = if ($NextHeading -eq '') {
    $Text.Length
  }
  else {
    $found = $Text.IndexOf($NextHeading, $sliceStart, [System.StringComparison]::Ordinal)
    if ($found -lt 0) { $Text.Length } else { $found }
  }

  return $Text.Substring($sliceStart, $end - $sliceStart)
}

function Invoke-GeneratorForFixture {
  param(
    [string]$OldVocabularyText,
    [string]$VocabularyText,
    [string]$TopicsText,
    [string]$PhrasesText
  )

  $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("incremental-report-test-" + [System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  try {
    $oldVocabularyPath = Join-Path $tempRoot 'old_vocabulary.md'
    $vocabularyPath = Join-Path $tempRoot '2_vocabulary.md'
    $topicsPath = Join-Path $tempRoot '3_topics.md'
    $phrasesPath = Join-Path $tempRoot '5_phrases.md'
    $outputPath = Join-Path $tempRoot 'incremental_update_report.md'

    [System.IO.File]::WriteAllText($oldVocabularyPath, ($OldVocabularyText.Trim() + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($vocabularyPath, ($VocabularyText.Trim() + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($topicsPath, ($TopicsText.Trim() + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($phrasesPath, ($PhrasesText.Trim() + [Environment]::NewLine), [System.Text.Encoding]::UTF8)

    & $GeneratorPath `
      -OldVocabularyPath $oldVocabularyPath `
      -VocabularyPath $vocabularyPath `
      -TopicsPath $topicsPath `
      -PhrasesPath $phrasesPath `
      -OutputPath $outputPath

    return [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::UTF8)
  }
  finally {
    if (Test-Path -LiteralPath $tempRoot) {
      Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
  }
}

function Test-DetectsNewEntriesAndTailTopicRecommendations {
  $report = Invoke-GeneratorForFixture -OldVocabularyText @'
# vocabulary

## Грамматические таблицы

### Presente

| Лицо | hablar |
| --- | --- |
| yo | háblo |
'@ -VocabularyText @'
# vocabulary

## Грамматические таблицы

### Presente

| Лицо | hablar |
| --- | --- |
| yo | háblo |

### Gerundio

| Infinitivo | Gerundio |
| --- | --- |
| hablár | hablándo |
| comér | comiéndo |
'@ -TopicsText @'
# Темы

1. **Presente**
   Источник: `### Presente`
'@ -PhrasesText @'
# Фразы

## 1. Presente

| Испанский | Перевод |
| --- | --- |
| Yo háblo aquí. | Я говорю здесь. |

## 2. Gerundio

| Испанский | Перевод |
| --- | --- |
| Estoy hablándo con Ana. | Я говорю с Аной. |
'@

  Assert-Contains $report '## Новые элементы словаря'
  Assert-Contains $report '| Gerundio | hablándo | да |'
  Assert-Contains $report '| Gerundio | comiéndo | нет |'
  Assert-Contains $report '## Новые темы для 3_topics.md'
  Assert-Contains $report '- Добавить в хвост тему для раздела `Gerundio`.'
  Assert-Contains $report '## Новые элементы без покрытия'
  Assert-Contains $report '| Gerundio | comiéndo |'
}

function Test-IgnoresAlreadyCoveredLegacyAndNewEntries {
  $report = Invoke-GeneratorForFixture -OldVocabularyText @'
# vocabulary

## Глаголы

### Глаголы все

| Испанский | Перевод на русский |
| --- | --- |
| hablár | говорить |
'@ -VocabularyText @'
# vocabulary

## Глаголы

### Глаголы все

| Испанский | Перевод на русский |
| --- | --- |
| hablár | говорить |
| pensár en | думать о |
| ¿Qué hóra es? | сколько времени? |
'@ -TopicsText @'
# Темы

1. **База**
   Источник: `### Глаголы все`
'@ -PhrasesText @'
# Фразы

## 1. База

| Испанский | Перевод |
| --- | --- |
| Yo háblo con Ana. | Я говорю с Аной. |
| Quiero pensár en ti. | Я хочу думать о тебе. |
| A ver, ¿Qué hóra es? | Который час? |
'@

  $newUncoveredPart = Get-ReportSection -Text $report -Heading '## Новые элементы без покрытия' -NextHeading '## Рекомендации для новых фраз'
  Assert-NotContains $newUncoveredPart '| Глаголы все | pensár en |'
  Assert-NotContains $newUncoveredPart '| Глаголы все | ¿Qué hóra es? |'
  Assert-Contains $report '| Глаголы все | pensár en | да |'
  Assert-Contains $report '| Глаголы все | ¿Qué hóra es? | да |'
}

function Test-TreatsNumeralsAsOptionalRecommendations {
  $report = Invoke-GeneratorForFixture -OldVocabularyText @'
# vocabulary

## Количественные

### Количественные

| Испанский | Перевод на русский |
| --- | --- |
| úno | один |
'@ -VocabularyText @'
# vocabulary

## Количественные

### Количественные

| Испанский | Перевод на русский |
| --- | --- |
| úno | один |
| dos | два |
'@ -TopicsText @'
# Темы

1. **Количественные**
   Источник: `### Количественные`
'@ -PhrasesText @'
# Фразы

## 1. Количественные

| Испанский | Перевод |
| --- | --- |
| Tengo úno aquí. | У меня один здесь. |
'@

  $newUncoveredPart = Get-ReportSection -Text $report -Heading '## Новые элементы без покрытия' -NextHeading '## Рекомендации для новых фраз'
  Assert-NotContains $newUncoveredPart '| Количественные | dos |'
  Assert-Contains $report '## Рекомендации для новых фраз'
  Assert-Contains $report '| Количественные | dos | необязательно |'
}

function Test-IgnoresSingleColumnMarkdownTables {
  $report = Invoke-GeneratorForFixture -OldVocabularyText @'
# vocabulary

## Test

### Weird

| Header |
| --- |
| value |
'@ -VocabularyText @'
# vocabulary

## Test

### Weird

| Header |
| --- |
| value |
| value2 |
'@ -TopicsText @'
# Темы

1. **База**
   Источник: `### Weird`
'@ -PhrasesText @'
# Фразы

## 1. База

| Испанский | Перевод |
| --- | --- |
| Nada cambia. | Ничего не меняется. |
'@

  Assert-Contains $report '## Новые элементы словаря'
  Assert-Contains $report 'Новых элементов не найдено.'
}

$tests = @(
  'Test-DetectsNewEntriesAndTailTopicRecommendations',
  'Test-IgnoresAlreadyCoveredLegacyAndNewEntries',
  'Test-TreatsNumeralsAsOptionalRecommendations',
  'Test-IgnoresSingleColumnMarkdownTables'
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
