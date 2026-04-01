param(
  [Parameter(Mandatory = $true)]
  [string]$OldVocabularyPath,
  [string]$VocabularyPath = '',
  [string]$TopicsPath = '',
  [string]$PhrasesPath = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($VocabularyPath -eq '') { $VocabularyPath = Join-Path $rootDir '2_vocabulary.md' }
if ($TopicsPath -eq '') { $TopicsPath = Join-Path $rootDir '3_topics.md' }
if ($PhrasesPath -eq '') { $PhrasesPath = Join-Path $rootDir '5_phrases.md' }

function Get-CleanCell {
  param([string]$Value)

  if ($null -eq $Value) { return '' }
  return (($Value -replace '\s+', ' ').Trim())
}

function Split-MarkdownRow {
  param([string]$Line)

  $trimmed = $Line.Trim()
  if (-not ($trimmed.StartsWith('|') -and $trimmed.EndsWith('|'))) {
    return @()
  }

  $cells = $trimmed.Substring(1, $trimmed.Length - 2).Split('|')
  return @($cells | ForEach-Object { Get-CleanCell $_ })
}

function Test-SeparatorRow {
  param([string[]]$Cells)

  if ($Cells.Count -eq 0) { return $false }
  foreach ($cell in $Cells) {
    if ($cell -notmatch '^:?-{3,}:?$') {
      return $false
    }
  }
  return $true
}

function Get-HeaderLevel {
  param([string]$Line)

  $trimmed = $Line.Trim()
  if ($trimmed -match '^(#+)\s+') {
    return $Matches[1].Length
  }
  return 0
}

function Get-MarkdownTableRows {
  param(
    [string[]]$Lines,
    [int]$StartIndex
  )

  $rows = New-Object System.Collections.Generic.List[string[]]
  $index = $StartIndex
  while ($index -lt $Lines.Count) {
    $line = $Lines[$index]
    if (-not $line.Trim().StartsWith('|')) {
      break
    }

    $cells = @(Split-MarkdownRow $line)
    if ($cells.Count -gt 0) {
      $rows.Add($cells) | Out-Null
    }
    $index++
  }

  return @{
    Rows = $rows
    NextIndex = $index
  }
}

function Get-NormalizedText {
  param([string]$Text)

  $value = $Text.ToLowerInvariant()
  $value = $value -replace '[¡!¿?\.,;:()\[\]"]', ' '
  $value = $value -replace '[\\/]+', ' '
  $value = $value -replace '\s+', ' '
  return $value.Trim()
}

function Get-NormalizedPhraseText {
  param([string]$Text)

  return " $(Get-NormalizedText $Text) "
}

function Get-EntryMatcher {
  param([string]$Entry)

  $normalized = Get-NormalizedText $Entry
  if ($normalized -eq '') {
    return $null
  }

  $tokens = @($normalized.Split(' ') | Where-Object { $_ -ne '' })
  if ($tokens.Count -le 1) {
    return @{
      Type = 'single'
      Value = " $normalized "
    }
  }

  return @{
    Type = 'phrase'
    Pattern = "(?<!\p{L})$([regex]::Escape($normalized))(?!\p{L})"
  }
}

function Split-GrammarCell {
  param([string]$Value)

  $clean = Get-CleanCell $Value
  if ($clean -eq '') { return @() }

  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($piece in ($clean -split ',')) {
    foreach ($subPiece in ($piece -split '/')) {
      $candidate = Get-CleanCell $subPiece
      if ($candidate -ne '') {
        $parts.Add($candidate) | Out-Null
      }
    }
  }

  return @($parts)
}

function Test-TrackableEntry {
  param([string]$Entry)

  $clean = Get-CleanCell $Entry
  if ($clean -eq '') { return $false }
  if ($clean -match '[А-Яа-яЁё]') { return $false }
  if ($clean -match '^-') { return $false }
  if ($clean -match '^\d+$') { return $false }
  if ($clean -in @('yo', 'tú', 'él / ella / usted', 'nosotros/as', 'vosotros/as', 'ellos / ellas / ustedes')) {
    return $false
  }
  return $true
}

function Get-VocabularyCandidatesFromRow {
  param(
    [string[]]$Header,
    [string[]]$Cells
  )

  if ($Header.Count -eq 0 -or $Cells.Count -eq 0) {
    return @()
  }

  $firstHeader = $Header[0]
  $secondHeader = if ($Header.Count -gt 1) { $Header[1] } else { '' }

  if ($firstHeader -eq 'Испанский' -or $firstHeader -eq 'Маркер') {
    return @($Cells[0])
  }

  if ($firstHeader -eq 'Лицо') {
    return @(
      $Cells |
      Select-Object -Skip 1 |
      ForEach-Object { Split-GrammarCell $_ }
    )
  }

  if ($firstHeader -eq 'Infinitivo' -and $secondHeader -in @('Participio', 'Gerundio')) {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($index in @(0, 1)) {
      if ($index -lt $Cells.Count) {
        foreach ($candidate in (Split-GrammarCell $Cells[$index])) {
          $result.Add($candidate) | Out-Null
        }
      }
    }
    return @($result)
  }

  if ($firstHeader -eq 'Infinitivo') {
    return @(Split-GrammarCell $Cells[0])
  }

  if ($firstHeader -eq 'Тип') {
    return @(
      $Cells |
      Select-Object -Skip 1 |
      ForEach-Object { Split-GrammarCell $_ }
    )
  }

  if ($firstHeader -eq 'Паттерн' -or $firstHeader -eq 'Паттерн / пример') {
    $result = New-Object System.Collections.Generic.List[string]
    if ($Cells.Count -gt 1) {
      foreach ($candidate in (Split-GrammarCell $Cells[1])) {
        $result.Add($candidate) | Out-Null
      }
    }
    if ($Cells.Count -gt 2) {
      foreach ($candidate in (Split-GrammarCell $Cells[2])) {
        $result.Add($candidate) | Out-Null
      }
    }
    return @($result)
  }

  if ($firstHeader -eq 'Правило') {
    if ($Cells.Count -gt 1) {
      return @(Split-GrammarCell $Cells[1])
    }
    return @()
  }

  if (($firstHeader -eq '-AR' -and $secondHeader -eq 'Ejemplo') -or $secondHeader -like 'Ejemplo*') {
    $result = New-Object System.Collections.Generic.List[string]
    for ($index = 1; $index -lt $Cells.Count; $index += 2) {
      foreach ($candidate in (Split-GrammarCell $Cells[$index])) {
        $result.Add($candidate) | Out-Null
      }
    }
    return @($result)
  }

  return @($Cells[0])
}

function Get-VocabularyEntries {
  param([string]$Path)

  $lines = [System.IO.File]::ReadAllLines((Resolve-Path $Path), [System.Text.Encoding]::UTF8)
  $entries = New-Object System.Collections.Generic.List[object]
  $group = ''
  $section = ''

  $i = 0
  while ($i -lt $lines.Count) {
    $line = $lines[$i]
    $level = Get-HeaderLevel $line
    if ($level -eq 2) {
      $group = $line.Trim().Substring(3).Trim()
      $i++
      continue
    }

    if ($level -eq 3) {
      $section = $line.Trim().Substring(4).Trim()
      $i++
      continue
    }

    if ($line.Trim().StartsWith('|')) {
      $table = Get-MarkdownTableRows -Lines $lines -StartIndex $i
      $rows = $table.Rows
      $i = $table.NextIndex

      if ($rows.Count -lt 3) {
        continue
      }

      $header = @($rows[0])
      $separator = $rows[1]
      if (($header.Count -lt 2) -or (-not (Test-SeparatorRow $separator))) {
        continue
      }

      for ($r = 2; $r -lt $rows.Count; $r++) {
        $cells = $rows[$r]
        if ($cells.Count -lt 2) { continue }

        $candidates = Get-VocabularyCandidatesFromRow -Header $header -Cells $cells
        foreach ($candidate in $candidates) {
          $spanish = Get-CleanCell $candidate
          if (-not (Test-TrackableEntry $spanish)) { continue }

          $matcher = Get-EntryMatcher $spanish
          if ($null -eq $matcher) { continue }

          $entries.Add([pscustomobject]@{
            Group = $group
            Section = $section
            Entry = $spanish
            Matcher = $matcher
            Key = ("{0}|{1}|{2}" -f (Get-NormalizedText $group), (Get-NormalizedText $section), (Get-NormalizedText $spanish))
          }) | Out-Null
        }
      }

      continue
    }

    $i++
  }

  return $entries.ToArray()
}

function Get-PhraseRows {
  param([string]$Path)

  $lines = [System.IO.File]::ReadAllLines((Resolve-Path $Path), [System.Text.Encoding]::UTF8)
  $phrases = New-Object System.Collections.Generic.List[string]

  function Get-MarkdownTableBlock {
    param(
      [string[]]$Lines,
      [int]$StartIndex
    )

    $line = $Lines[$StartIndex]
    if (-not $line.Trim().StartsWith('|')) { return $null }

    $rows = New-Object System.Collections.Generic.List[object]
    $j = $StartIndex
    while ($j -lt $Lines.Count) {
      $tableLine = $Lines[$j]
      if (-not $tableLine.Trim().StartsWith('|')) { break }
      $cells = @(Split-MarkdownRow $tableLine)
      if ($cells.Count -gt 0) {
        $rows.Add($cells) | Out-Null
      }
      $j++
    }

    return [pscustomobject]@{
      StartIndex = $StartIndex
      NextIndex = $j
      Rows = @($rows.ToArray())
    }
  }

  function Get-TableDataStartRowIndex {
    param([object[]]$Rows)
    if ($Rows.Count -ge 2 -and (Test-SeparatorRow $Rows[1])) { return 2 }
    return 0
  }

  function Test-IsCyrillicText {
    param([string]$Text)
    return $Text -match '[А-Яа-яЁё]'
  }

  function Get-WordCount {
    param([string]$Text)
    $normalized = (Get-NormalizedText $Text).Trim()
    if ($normalized -eq '') { return 0 }
    return @($normalized.Split(' ') | Where-Object { $_ -ne '' }).Count
  }

  function Test-IsPhraseLikeRow {
    param(
      [string]$Spanish,
      [string]$Russian
    )

    if ($Spanish -eq '' -or $Russian -eq '') { return $false }
    if (-not (Test-IsCyrillicText $Russian)) { return $false }

    $spanishWords = Get-WordCount $Spanish
    $russianWords = Get-WordCount $Russian
    return ($spanishWords -ge 3 -and $russianWords -ge 2)
  }

  function Get-PhraseRowsFromTableBlock {
    param([object[]]$Rows)

    $dataStartIndex = Get-TableDataStartRowIndex -Rows $Rows
    $result = New-Object System.Collections.Generic.List[object]

    for ($r = $dataStartIndex; $r -lt $Rows.Count; $r++) {
      $cells = @($Rows[$r])
      if ($cells.Count -lt 2) { continue }
      $spanish = Get-CleanCell $cells[0]
      $russian = Get-CleanCell $cells[1]
      if ($spanish -eq '' -and $russian -eq '') { continue }
      $result.Add([pscustomobject]@{ Spanish = $spanish; Russian = $russian }) | Out-Null
    }

    return @($result.ToArray())
  }

  function Get-PhraseTableBlockForSection {
    param(
      [object[]]$Blocks,
      [string]$SectionTitle
    )

    $isNumbersTopic = $SectionTitle -match 'Числительные'
    $best = $null

    foreach ($block in $Blocks) {
      $candidateRows = @(Get-PhraseRowsFromTableBlock -Rows @($block.Rows))
      if ($candidateRows.Count -eq 0) { continue }

      $phraseLikeCount = 0
      foreach ($row in $candidateRows) {
        if ($isNumbersTopic) {
          if (Test-IsCyrillicText $row.Russian) { $phraseLikeCount++ }
          continue
        }

        if (Test-IsPhraseLikeRow -Spanish $row.Spanish -Russian $row.Russian) {
          $phraseLikeCount++
        }
      }

      if ($phraseLikeCount -gt 0) {
        $best = $block
      }
    }

    return $best
  }

  $currentTitle = ''
  $currentBlocks = New-Object System.Collections.Generic.List[object]

  function Flush-CurrentSection {
    if ($currentTitle -eq '') { return }

    $phraseBlock = Get-PhraseTableBlockForSection -Blocks @($currentBlocks.ToArray()) -SectionTitle $currentTitle
    if ($null -ne $phraseBlock) {
      foreach ($row in (Get-PhraseRowsFromTableBlock -Rows @($phraseBlock.Rows))) {
        if ($row.Spanish -ne '') { $phrases.Add($row.Spanish) | Out-Null }
      }
    }

    $currentBlocks.Clear()
  }

  $i = 0
  while ($i -lt $lines.Count) {
    $line = $lines[$i]
    $level = Get-HeaderLevel $line
    if ($level -eq 2) {
      Flush-CurrentSection
      $currentTitle = $line.Trim().Substring(3).Trim()
      $i++
      continue
    }

    if (-not $line.Trim().StartsWith('|')) {
      $i++
      continue
    }

    $block = Get-MarkdownTableBlock -Lines $lines -StartIndex $i
    if ($null -ne $block) {
      $currentBlocks.Add($block) | Out-Null
      $i = $block.NextIndex
      continue
    }

    $i++
  }

  Flush-CurrentSection

  return @($phrases.ToArray())
}

function Get-UsageCount {
  param(
    [hashtable]$Matcher,
    [string[]]$Phrases
  )

  $count = 0
  foreach ($phrase in $Phrases) {
    $normalizedPhrase = Get-NormalizedPhraseText $phrase
    if ($Matcher.Type -eq 'single') {
      $needle = $Matcher.Value
      $index = 0
      while ($index -lt $normalizedPhrase.Length) {
        $found = $normalizedPhrase.IndexOf($needle, $index, [System.StringComparison]::Ordinal)
        if ($found -lt 0) { break }
        $count++
        $index = $found + $needle.Length
      }
      continue
    }

    $count += ([regex]::Matches($normalizedPhrase, $Matcher.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
  }

  return $count
}

function Test-OptionalCoverageEntry {
  param([object]$Entry)

  return $Entry.Section -in @('Количественные', 'Порядковые')
}

function Get-TopicValidationReminders {
  return @(
    @{
      Section = 'Количественные'
      Reminder = 'В каждой новой фразе по этой теме должно быть числительное.'
    },
    @{
      Section = 'Порядковые'
      Reminder = 'В каждой новой фразе по этой теме должен быть порядковый числительный.'
    },
    @{
      Section = 'Месяцы и дни недели'
      Reminder = 'В каждой новой фразе по этой теме должен быть месяц или день недели.'
    },
    @{
      Section = 'Фразы про время и даты'
      Reminder = 'В каждой новой фразе по этой теме должна быть формула времени или даты.'
    },
    @{
      Section = 'Hace'
      Reminder = 'Для погодной темы используй форму `hace` с погодной лексикой.'
    },
    @{
      Section = 'Está'
      Reminder = 'Для погодной темы используй форму `está` с погодной лексикой.'
    },
    @{
      Section = 'Hay'
      Reminder = 'Для погодной темы используй форму `hay` с погодной лексикой.'
    },
    @{
      Section = 'Осадки и явления'
      Reminder = 'В новой фразе по теме должны явно появляться осадки или природное явление.'
    },
    @{
      Section = 'Времена года'
      Reminder = 'В новой фразе по теме должно явно появляться время года.'
    },
    @{
      Section = 'Природа'
      Reminder = 'В новой фразе по теме должно быть слово из лексики природы.'
    },
    @{
      Section = 'Presente'
      Reminder = 'Фразы должны содержать форму presente.'
    },
    @{
      Section = 'Gerundio'
      Reminder = 'Каждая новая фраза должна содержать форму gerundio.'
    },
    @{
      Section = 'Pretérito perfecto'
      Reminder = 'Каждая новая фраза должна содержать форму pretérito perfecto.'
    },
    @{
      Section = 'Pretérito perfecto simple'
      Reminder = 'Каждая новая фраза должна содержать форму pretérito perfecto simple.'
    },
    @{
      Section = 'Imperfecto'
      Reminder = 'Каждая новая фраза должна содержать форму imperfecto.'
    },
    @{
      Section = 'Futuro simple'
      Reminder = 'Каждая новая фраза должна содержать форму futuro simple.'
    }
  )
}

function Get-TopicRecommendations {
  param(
    [object[]]$NewEntries,
    [string]$TopicsText
  )

  $recommendations = New-Object System.Collections.Generic.List[object]
  $seenSections = @{}

  foreach ($entry in ($NewEntries | Sort-Object Section, Entry)) {
    $section = Get-CleanCell $entry.Section
    if ($section -eq '') { continue }

    $normalizedSection = Get-NormalizedText $section
    if ($seenSections.ContainsKey($normalizedSection)) { continue }

    $topicPattern = [regex]::Escape("### $section")
    $titlePattern = [regex]::Escape($section)
    if ($TopicsText -match $topicPattern -or $TopicsText -match $titlePattern) {
      $seenSections[$normalizedSection] = $true
      continue
    }

    $recommendations.Add([pscustomobject]@{
      Section = $section
    }) | Out-Null
    $seenSections[$normalizedSection] = $true
  }

  return $recommendations.ToArray()
}

function Format-ThreeColumnTable {
  param(
    [string]$ThirdHeader,
    [object[]]$Rows,
    [scriptblock]$ThirdSelector
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("| Раздел | Элемент | $ThirdHeader |") | Out-Null
  $lines.Add('| --- | --- | --- |') | Out-Null

  foreach ($row in $Rows) {
    $lines.Add("| $($row.Section) | $($row.Entry) | $(& $ThirdSelector $row) |") | Out-Null
  }

  return $lines.ToArray()
}

function Format-TwoColumnTable {
  param([object[]]$Rows)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Раздел | Элемент |') | Out-Null
  $lines.Add('| --- | --- |') | Out-Null

  foreach ($row in $Rows) {
    $lines.Add("| $($row.Section) | $($row.Entry) |") | Out-Null
  }

  return $lines.ToArray()
}

function Add-ReportLines {
  param(
    [System.Collections.Generic.List[string]]$Target,
    [string[]]$Lines
  )

  foreach ($line in $Lines) {
    $Target.Add($line) | Out-Null
  }
}

$oldEntries = Get-VocabularyEntries -Path $OldVocabularyPath
$currentEntries = Get-VocabularyEntries -Path $VocabularyPath
$phraseRows = Get-PhraseRows -Path $PhrasesPath
$topicsText = [System.IO.File]::ReadAllText((Resolve-Path $TopicsPath), [System.Text.Encoding]::UTF8)
$oldKeys = @{}

foreach ($entry in $oldEntries) {
  if (-not $oldKeys.ContainsKey($entry.Key)) {
    $oldKeys[$entry.Key] = $true
  }
}

$newEntries = @(
  $currentEntries |
  Where-Object { -not $oldKeys.ContainsKey($_.Key) } |
  Sort-Object Section, Entry
)

$newEntryResults = @(
  foreach ($entry in $newEntries) {
    $count = Get-UsageCount -Matcher $entry.Matcher -Phrases $phraseRows
    [pscustomobject]@{
      Group = $entry.Group
      Section = $entry.Section
      Entry = $entry.Entry
      Count = $count
      Covered = ($count -gt 0)
      Optional = (Test-OptionalCoverageEntry $entry)
    }
  }
)

$topicRecommendations = @(
  Get-TopicRecommendations -NewEntries $newEntries -TopicsText $topicsText
)

$requiredUncovered = @(
  $newEntryResults |
  Where-Object { (-not $_.Covered) -and (-not $_.Optional) } |
  Sort-Object Section, Entry
)

$phraseRecommendations = @(
  $newEntryResults |
  Where-Object { -not $_.Covered } |
  Sort-Object @{ Expression = 'Optional'; Descending = $false }, Section, Entry
)

$topicValidationReminders = Get-TopicValidationReminders
$narrowThemeWarnings = New-Object System.Collections.Generic.List[object]
$warningKeys = @{}

foreach ($candidate in ($topicRecommendations + $newEntries)) {
  $section = $candidate.Section
  $reminder = $topicValidationReminders | Where-Object { $_.Section -eq $section } | Select-Object -First 1
  if ($null -eq $reminder) { continue }

  $warningKey = Get-NormalizedText $section
  if ($warningKeys.ContainsKey($warningKey)) { continue }

  $narrowThemeWarnings.Add([pscustomobject]@{
    Topic = $section
    Reminder = $reminder.Reminder
  }) | Out-Null
  $warningKeys[$warningKey] = $true
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add('# incremental update report') | Out-Null
$report.Add('') | Out-Null
$report.Add("Старый словарь: ``$([System.IO.Path]::GetFileName($OldVocabularyPath))``") | Out-Null
$report.Add("Новый словарь: ``$([System.IO.Path]::GetFileName($VocabularyPath))``") | Out-Null
$report.Add("Темы: ``$([System.IO.Path]::GetFileName($TopicsPath))``") | Out-Null
$report.Add("Фразы: ``$([System.IO.Path]::GetFileName($PhrasesPath))``") | Out-Null
$report.Add('') | Out-Null
$report.Add("Новых словарных элементов: $($newEntryResults.Count)") | Out-Null
$report.Add("Новых обязательных элементов без покрытия: $($requiredUncovered.Count)") | Out-Null
$report.Add("Кандидатов на новые темы: $($topicRecommendations.Count)") | Out-Null
$report.Add('') | Out-Null

$report.Add('## Новые элементы словаря') | Out-Null
$report.Add('') | Out-Null
if ($newEntryResults.Count -eq 0) {
  $report.Add('Новых элементов не найдено.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-ThreeColumnTable -ThirdHeader 'Уже есть во фразах' -Rows $newEntryResults -ThirdSelector { param($row) if ($row.Covered) { 'да' } else { 'нет' } })
}
$report.Add('') | Out-Null

$report.Add('## Новые темы для 3_topics.md') | Out-Null
$report.Add('') | Out-Null
if ($topicRecommendations.Count -eq 0) {
  $report.Add('Новых тем не найдено: хвост `3_topics.md` можно не расширять.') | Out-Null
}
else {
  foreach ($topic in $topicRecommendations) {
    $report.Add("- Добавить в хвост тему для раздела ``$($topic.Section)``.") | Out-Null
  }
}
$report.Add('') | Out-Null

$report.Add('## Новые элементы без покрытия') | Out-Null
$report.Add('') | Out-Null
if ($requiredUncovered.Count -eq 0) {
  $report.Add('Новых обязательных элементов без покрытия не найдено.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-TwoColumnTable -Rows $requiredUncovered)
}
$report.Add('') | Out-Null

$report.Add('## Рекомендации для новых фраз') | Out-Null
$report.Add('') | Out-Null
if ($phraseRecommendations.Count -eq 0) {
  $report.Add('Новые фразы не требуются: все новые элементы уже встречаются в `5_phrases.md`.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-ThreeColumnTable -ThirdHeader 'Приоритет' -Rows $phraseRecommendations -ThirdSelector { param($row) if ($row.Optional) { 'необязательно' } else { 'обязательно' } })
}
$report.Add('') | Out-Null

$report.Add('## Предупреждения по узким темам') | Out-Null
$report.Add('') | Out-Null
if ($narrowThemeWarnings.Count -eq 0) {
  $report.Add('Специальных предупреждений нет.') | Out-Null
}
else {
  $report.Add('| Тема | Напоминание |') | Out-Null
  $report.Add('| --- | --- |') | Out-Null
  foreach ($warning in $narrowThemeWarnings) {
    $report.Add("| $($warning.Topic) | $($warning.Reminder) |") | Out-Null
  }
}
$report.Add('') | Out-Null

if ($OutputPath -eq '') {
  $report -join [Environment]::NewLine
}
else {
  $outputDirectory = Split-Path -Parent $OutputPath
  if ($outputDirectory -and (-not (Test-Path -LiteralPath $outputDirectory))) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
  }
  [System.IO.File]::WriteAllLines($OutputPath, [string[]]$report, [System.Text.Encoding]::UTF8)
}
