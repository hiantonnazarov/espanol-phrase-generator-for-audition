param(
  [string]$VocabularyPath = '',
  [string]$PhrasesPath = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($VocabularyPath -eq '') { $VocabularyPath = Join-Path $rootDir '2_vocabulary.md' }
if ($PhrasesPath -eq '') { $PhrasesPath = Join-Path $rootDir '5_phrases.md' }
if ($OutputPath -eq '') { $OutputPath = Join-Path $rootDir '4_words_usage.md' }

function Get-StopwordSet {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($word in @(
      # Articles / determiners
      'el', 'la', 'los', 'las', 'lo',
      'un', 'una', 'unos', 'unas',
      # Common prepositions (and contractions)
      'a', 'de', 'en', 'con', 'sin', 'por', 'para', 'sobre', 'entre',
      'hacia', 'hasta', 'desde', 'durante', 'contra', 'segun', 'tras',
      'al', 'del'
    )) {
    [void]$set.Add($word)
  }
  return $set
}

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

  $cells = $trimmed.Substring(1, $trimmed.Length - 2).Split('|') | ForEach-Object { Get-CleanCell $_ }
  $cells = [string[]]$cells
  Write-Output -NoEnumerate $cells
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

    $cells = Split-MarkdownRow $line
    $cells = [string[]]@($cells)
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

  $normalized = Get-NormalizedText $Text
  return " $normalized "
}

function Get-EntryMatcher {
  param(
    [string]$Entry,
    [string]$Group = '',
    [string]$Section = ''
  )

  $normalized = Get-NormalizedText $Entry
  if ($normalized -eq '') {
    return $null
  }

  $tokens = @($normalized.Split(' ') | Where-Object { $_ -ne '' })
  if ($tokens.Count -le 1) {
    $normalizedNoDiacritics = Remove-Diacritics $normalized
    $useNoDiacriticsForSingle = ($Section -in @('Предлоги', 'Союзы', 'Указательные местоимения', 'Предлоги места'))
    return @{
      Type = 'single'
      Value = if ($useNoDiacriticsForSingle) { " $normalizedNoDiacritics " } else { " $normalized " }
      UseNoDiacritics = $useNoDiacriticsForSingle
    }
  }

  $normalizedNoDiacritics = Remove-Diacritics $normalized
  $stopwords = Get-StopwordSet
  $contentTokens = @(
    $normalizedNoDiacritics.Split(' ') |
    Where-Object { $_ -ne '' } |
    Where-Object { -not $stopwords.Contains($_) }
  )

  # For entries that are mostly function words (articles/prepositions) + one content word,
  # track usage by the content word only to reduce noise from article/preposition variation.
  # Keep it conservative to avoid false positives like "a ver" -> "ver".
  if ($contentTokens.Count -eq 1 -and $contentTokens[0].Length -ge 4) {
    return @{
      Type = 'single'
      Value = " $($contentTokens[0]) "
      UseNoDiacritics = $true
    }
  }

  return @{
    Type = 'phrase'
    UseNoDiacritics = $true
    Pattern = "(?<!\p{L})$([regex]::Escape($normalizedNoDiacritics))(?!\p{L})"
  }
}

function Get-LegacyEntryReason {
  param([string]$Entry)

  $clean = Get-CleanCell $Entry
  if ($clean -match '[=]' -or $clean -match '[\\/]') {
    return 'legacy-агрегат с `=` или вариантами'
  }

  return $null
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

function Get-EntryLetterLength {
  param([string]$Entry)

  $clean = Get-CleanCell $Entry
  if ($clean -eq '') { return 0 }

  return (($clean -replace '[^\p{L}]', '').Length)
}

function Test-SupplementalEntry {
  param([object]$Entry)

  if ($null -eq $Entry) { return $false }
  if ($Entry.IsLegacy) { return $false }
  if ($Entry.Group -eq 'Числительные') { return $false }
  if ($Entry.CountsTowardCoverage) { return $false }
  $normalized = Get-NormalizedText $Entry.Entry
  $tokens = @($normalized.Split(' ') | Where-Object { $_ -ne '' })
  if ($tokens.Count -ne 1) { return $false }
  return ((Get-EntryLetterLength $Entry.Entry) -ge 3)
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

          $matcher = Get-EntryMatcher -Entry $spanish -Group $group -Section $section
          if ($null -eq $matcher) { continue }

          $entries.Add([pscustomobject]@{
            Group = $group
            Section = $section
            Entry = $spanish
            Matcher = $matcher
            LegacyReason = Get-LegacyEntryReason $spanish
            IsLegacy = ($null -ne (Get-LegacyEntryReason $spanish))
            CountsTowardCoverage = ($group -notin @('Грамматические таблицы', 'Фразы (разговорное / кафе / быт)', 'Числительные'))
          }) | Out-Null
        }
      }

      continue
    }

    $i++
  }

  return $entries
}

function Split-VariantValues {
  param([string]$Value)

  $clean = Get-CleanCell $Value
  if ($clean -eq '') { return @() }

  return @(
    $clean -split '\s*/\s*' |
    ForEach-Object { Get-CleanCell $_ } |
    Where-Object { $_ -ne '' }
  )
}

function New-TenseCoverageSpec {
  param(
    [string]$Tense,
    [string]$Lemma,
    [string]$Person,
    [string]$Form
  )

  $cleanForm = Get-CleanCell $Form
  if (-not (Test-TrackableEntry $cleanForm)) { return $null }

  $matcher = Get-EntryMatcher -Entry $cleanForm
  if ($null -eq $matcher) { return $null }

  return [pscustomobject]@{
    Tense = $Tense
    Lemma = Get-CleanCell $Lemma
    Person = Get-CleanCell $Person
    Form = $cleanForm
    Matcher = $matcher
  }
}

function Get-TenseCoverageSpecs {
  param([string]$Path)

  $lines = [System.IO.File]::ReadAllLines((Resolve-Path $Path), [System.Text.Encoding]::UTF8)
  $specs = New-Object System.Collections.Generic.List[object]
  $section = ''
  $futureEndings = @()

  $i = 0
  while ($i -lt $lines.Count) {
    $line = $lines[$i]
    $level = Get-HeaderLevel $line
    if ($level -eq 3) {
      $section = $line.Trim().Substring(4).Trim()
      $i++
      continue
    }

    if (-not $line.Trim().StartsWith('|')) {
      $i++
      continue
    }

    $table = Get-MarkdownTableRows -Lines $lines -StartIndex $i
    $rows = $table.Rows
    $i = $table.NextIndex

    if ($rows.Count -lt 3) { continue }

    $header = @($rows[0])
    if (($header.Count -lt 2) -or (-not (Test-SeparatorRow $rows[1]))) {
      continue
    }

    switch ($section) {
      'Presente' {
        if ($header[0] -eq 'Лицо') {
          $lemmas = @($header | Select-Object -Skip 1)
          for ($c = 0; $c -lt $lemmas.Count; $c++) {
            $cleanLemma = (Get-CleanCell $lemmas[$c]).Trim()
            if ($cleanLemma -in @('Притяжат. перед сущ.', 'Притяжат. после сущ.')) {
              continue
            }
            if ([string]::IsNullOrWhiteSpace($cleanLemma)) {
              continue
            }

            for ($r = 2; $r -lt $rows.Count; $r++) {
              $cells = @($rows[$r])
              if ($cells.Count -le ($c + 1)) { continue }
              $person = $cells[0]
              foreach ($lemma in (Split-VariantValues $cleanLemma)) {
                $spec = New-TenseCoverageSpec -Tense $section -Lemma $lemma -Person $person -Form $cells[$c + 1]
                if ($null -ne $spec) { $specs.Add($spec) | Out-Null }
              }
            }
          }
        }
        elseif ($header[0] -eq 'Паттерн' -and $header[1] -eq 'Глагол' -and $header[2] -eq 'Пример форм') {
          for ($r = 2; $r -lt $rows.Count; $r++) {
            $cells = @($rows[$r])
            if ($cells.Count -lt 3) { continue }
            foreach ($form in (Split-GrammarCell $cells[2])) {
              $spec = New-TenseCoverageSpec -Tense $section -Lemma $cells[1] -Person '' -Form $form
              if ($null -ne $spec) { $specs.Add($spec) | Out-Null }
            }
          }
        }
      }
      'Pretérito perfecto' {
        if ($header[0] -eq 'Лицо' -and $header[1] -eq 'Haber') {
          for ($r = 2; $r -lt $rows.Count; $r++) {
            $cells = @($rows[$r])
            $spec = New-TenseCoverageSpec -Tense $section -Lemma '' -Person $cells[0] -Form $cells[1]
            if ($null -ne $spec) { $specs.Add($spec) | Out-Null }
          }
        }
        elseif ($header[0] -eq 'Infinitivo' -and $header[1] -eq 'Participio') {
          for ($r = 2; $r -lt $rows.Count; $r++) {
            $cells = @($rows[$r])
            $lemma = $cells[0]
            $form = $cells[1]
            $spec = New-TenseCoverageSpec -Tense $section -Lemma $lemma -Person '' -Form $form
            if ($null -ne $spec) { $specs.Add($spec) | Out-Null }
          }
        }
      }
      'Gerundio' {
        if ($header[0] -eq 'Infinitivo' -and $header[1] -eq 'Gerundio') {
          for ($r = 2; $r -lt $rows.Count; $r++) {
            $cells = @($rows[$r])
            $spec = New-TenseCoverageSpec -Tense $section -Lemma $cells[0] -Person '' -Form $cells[1]
            if ($null -ne $spec) { $specs.Add($spec) | Out-Null }
          }
        }
      }
      'Imperfecto' {
        if ($header[0] -eq 'Лицо') {
          $lemmas = @($header | Select-Object -Skip 1)
          for ($r = 2; $r -lt $rows.Count; $r++) {
            $cells = @($rows[$r])
            $person = $cells[0]
            for ($c = 1; $c -lt [Math]::Min($cells.Count, $header.Count); $c++) {
              foreach ($lemma in (Split-VariantValues $lemmas[$c - 1])) {
                $spec = New-TenseCoverageSpec -Tense $section -Lemma $lemma -Person $person -Form $cells[$c]
                if ($null -ne $spec) { $specs.Add($spec) | Out-Null }
              }
            }
          }
        }
      }
      'Futuro simple' {
        if ($header[0] -eq 'Лицо' -and $header[1] -eq 'Окончание') {
          $futureEndings = @()
          for ($r = 2; $r -lt $rows.Count; $r++) {
            $cells = @($rows[$r])
            $futureEndings += [pscustomobject]@{
              Person = $cells[0]
              Ending = (Get-CleanCell $cells[1]).TrimStart('-')
            }
            $spec = New-TenseCoverageSpec -Tense $section -Lemma 'comér' -Person $cells[0] -Form $cells[2]
            if ($null -ne $spec) { $specs.Add($spec) | Out-Null }
          }
        }
        elseif ($header[0] -eq 'Infinitivo' -and $header[1] -eq 'Raíz irregular') {
          for ($r = 2; $r -lt $rows.Count; $r++) {
            $cells = @($rows[$r])
            foreach ($endingRow in $futureEndings) {
              $form = (Get-CleanCell $cells[1]) + $endingRow.Ending
              $spec = New-TenseCoverageSpec -Tense $section -Lemma $cells[0] -Person $endingRow.Person -Form $form
              if ($null -ne $spec) { $specs.Add($spec) | Out-Null }
            }
          }
        }
      }
      'Pretérito perfecto simple' {
        if ($header[0] -eq 'Лицо') {
          $lemmas = @($header | Select-Object -Skip 1)
          for ($r = 2; $r -lt $rows.Count; $r++) {
            $cells = @($rows[$r])
            $person = $cells[0]
            for ($c = 1; $c -lt [Math]::Min($cells.Count, $header.Count); $c++) {
              foreach ($lemma in (Split-VariantValues $lemmas[$c - 1])) {
                $spec = New-TenseCoverageSpec -Tense $section -Lemma $lemma -Person $person -Form $cells[$c]
                if ($null -ne $spec) { $specs.Add($spec) | Out-Null }
              }
            }
          }
        }
      }
    }
  }

  return $specs
}

function Get-TenseSectionUsageMaps {
  param(
    [object[]]$PhraseSections,
    [object[]]$TenseCoverageSpecs
  )

  $maps = @{}
  foreach ($rule in (Get-TenseCoverageRules)) {
    $sections = @($PhraseSections | Where-Object { $_.Title -match $rule.TitlePattern })
    if ($sections.Count -eq 0) { continue }

    $sectionSpecs = @($TenseCoverageSpecs | Where-Object { $_.Tense -eq $rule.Label })
    if ($sectionSpecs.Count -eq 0) { continue }

    $lemmaUsage = @{}
    $personUsage = @{}
    foreach ($lemma in @($sectionSpecs | Where-Object { $_.Lemma -ne '' } | Select-Object -ExpandProperty Lemma -Unique)) {
      $lemmaUsage[$lemma] = 0
    }
    foreach ($person in @($sectionSpecs | Where-Object { $_.Person -ne '' } | Select-Object -ExpandProperty Person -Unique)) {
      $personUsage[$person] = 0
    }
    foreach ($section in $sections) {
      foreach ($phrase in $section.Phrases) {
        foreach ($spec in $sectionSpecs) {
          if ((Get-UsageCount -Matcher $spec.Matcher -Phrases @($phrase)) -le 0) { continue }

          if ($spec.Lemma -ne '') {
            $lemmaUsage[$spec.Lemma]++
          }

          if ($spec.Person -ne '') {
            $personUsage[$spec.Person]++
          }
        }
      }
    }

    foreach ($section in $sections) {
      $maps[$section.Title] = [pscustomobject]@{
        Rule = $rule
        Section = $section
        LemmaUsage = $lemmaUsage
        PersonUsage = $personUsage
      }
    }
  }

  return $maps
}

function Get-PhraseRows {
  param([string]$Path)

  $phrases = New-Object System.Collections.Generic.List[string]
  foreach ($section in (Get-PhraseSections -Path $Path)) {
    foreach ($phrase in $section.Phrases) {
      $phrases.Add($phrase) | Out-Null
    }
  }

  return @($phrases.ToArray())
}

function Get-MarkdownTableBlock {
  param(
    [string[]]$Lines,
    [int]$StartIndex
  )

  $i = $StartIndex
  $line = $Lines[$i]
  if (-not $line.Trim().StartsWith('|')) { return $null }

  $rows = New-Object System.Collections.Generic.List[object]
  $j = $i
  while ($j -lt $Lines.Count) {
    $tableLine = $Lines[$j]
    if (-not $tableLine.Trim().StartsWith('|')) { break }
    $cells = Split-MarkdownRow $tableLine
    $cells = [string[]]@($cells)
    if ($cells.Count -gt 0) {
      $rows.Add($cells) | Out-Null
    }
    $j++
  }

  return [pscustomobject]@{
    StartIndex = $i
    NextIndex = $j
    Rows = @($rows.ToArray())
  }
}

function Get-TableDataStartRowIndex {
  param([object[]]$Rows)

  if ($Rows.Count -ge 2 -and (Test-SeparatorRow $Rows[1])) {
    return 2
  }

  return 0
}

function Get-WordCount {
  param([string]$Text)

  $normalized = (Get-NormalizedText $Text).Trim()
  if ($normalized -eq '') { return 0 }
  return @($normalized.Split(' ') | Where-Object { $_ -ne '' }).Count
}

function Test-IsCyrillicText {
  param([string]$Text)

  return $Text -match '[А-Яа-яЁё]'
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
  param(
    [object[]]$Rows,
    [string]$SectionTitle
  )

  $dataStartIndex = Get-TableDataStartRowIndex -Rows $Rows
  $result = New-Object System.Collections.Generic.List[object]

  for ($r = $dataStartIndex; $r -lt $Rows.Count; $r++) {
    $cells = @($Rows[$r])
    if ($cells.Count -lt 2) { continue }
    $spanish = Get-CleanCell $cells[0]
    $russian = Get-CleanCell $cells[1]
    if ($spanish -eq '' -and $russian -eq '') { continue }

    $result.Add([pscustomobject]@{
      Spanish = $spanish
      Russian = $russian
    }) | Out-Null
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
    $rows = @($block.Rows)
    if ($rows.Count -le 0) { continue }

    $candidateRows = @(Get-PhraseRowsFromTableBlock -Rows $rows -SectionTitle $SectionTitle)
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

function Get-PhraseSections {
  param([string]$Path)

  $lines = [System.IO.File]::ReadAllLines((Resolve-Path $Path), [System.Text.Encoding]::UTF8)
  $sections = New-Object System.Collections.Generic.List[object]

  $currentTitle = ''
  $currentBlocks = New-Object System.Collections.Generic.List[object]

  function Flush-CurrentSection {
    if ($currentTitle -eq '') { return }

    $phraseBlock = Get-PhraseTableBlockForSection -Blocks @($currentBlocks.ToArray()) -SectionTitle $currentTitle

    $phrases = New-Object System.Collections.Generic.List[string]
    $rowsForSection = New-Object System.Collections.Generic.List[object]

    if ($null -ne $phraseBlock) {
      $candidateRows = @(Get-PhraseRowsFromTableBlock -Rows @($phraseBlock.Rows) -SectionTitle $currentTitle)
      foreach ($row in $candidateRows) {
        if ($row.Spanish -ne '') {
          $phrases.Add($row.Spanish) | Out-Null
          $rowsForSection.Add($row) | Out-Null
        }
      }
    }

    $sections.Add([pscustomobject]@{
      Title = $currentTitle
      Phrases = @($phrases.ToArray())
      Rows = @($rowsForSection.ToArray())
    }) | Out-Null

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

  return @($sections.ToArray())
}

function Get-UsageCount {
  param(
    [hashtable]$Matcher,
    [string[]]$Phrases
  )

  $count = 0
  foreach ($phrase in $Phrases) {
    $useNoDiacritics = ($Matcher.ContainsKey('UseNoDiacritics') -and $Matcher.UseNoDiacritics)
    $normalizedPhrase = if ($useNoDiacritics) {
      " $(Remove-Diacritics (Get-NormalizedText $phrase)) "
    }
    else {
      Get-NormalizedPhraseText $phrase
    }
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

function Get-PersonRules {
  return @(
    @{ Label = 'yo'; Patterns = @('\byo\b', '\bhe\b') },
    @{ Label = 'tú'; Patterns = @('\btú\b', '\bhas\b') },
    @{ Label = 'él / ella / usted'; Patterns = @('\bél\b', '\bélla\b', '\busted\b', '\bha\b') },
    @{ Label = 'nosotros/as'; Patterns = @('\bnosotros\b', '\bnosotras\b', '\bh[ée]mos\b') },
    @{ Label = 'vosotros/as'; Patterns = @('\bvosotros\b', '\bvosotras\b', '\bhabéis\b') },
    @{ Label = 'ellos / ellas / ustedes'; Patterns = @('\béllos\b', '\béllas\b', '\bustedes\b', '\bhan\b') }
  )
}

function Get-PersonLabelsForPhrase {
  param([string]$Phrase)

  $normalized = Get-NormalizedText $Phrase
  $labels = New-Object System.Collections.Generic.List[string]
  foreach ($rule in (Get-PersonRules)) {
    foreach ($pattern in $rule.Patterns) {
      if ($normalized -match $pattern) {
        $labels.Add($rule.Label) | Out-Null
        break
      }
    }
  }

  return @($labels | Select-Object -Unique)
}

function Remove-Diacritics {
  param([string]$Text)

  if ($null -eq $Text) { return '' }

  # Preserve ñ/Ñ: they are distinct letters in Spanish.
  $sentinelLower = '__ENYE_LOWER__'
  $sentinelUpper = '__ENYE_UPPER__'
  $protected = $Text.Replace('ñ', $sentinelLower).Replace('Ñ', $sentinelUpper)

  $normalized = $protected.Normalize([Text.NormalizationForm]::FormD)
  $builder = New-Object System.Text.StringBuilder
  foreach ($char in $normalized.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$builder.Append($char)
    }
  }

  $result = $builder.ToString().Normalize([Text.NormalizationForm]::FormC)
  $result = $result.Replace($sentinelLower, 'ñ').Replace($sentinelUpper, 'Ñ')
  return $result
}

function Get-TenseCoverageRules {
  return @(
    @{ TitlePattern = 'Presente'; Label = 'Presente'; VocabularySections = @('Presente'); ReportPersons = $true },
    @{ TitlePattern = 'Pretérito perfecto:'; Label = 'Pretérito perfecto'; VocabularySections = @('Pretérito perfecto'); ReportPersons = $true },
    @{ TitlePattern = 'Imperfecto'; Label = 'Imperfecto'; VocabularySections = @('Imperfecto'); ReportPersons = $true },
    @{ TitlePattern = 'Pretérito perfecto simple'; Label = 'Pretérito perfecto simple'; VocabularySections = @('Pretérito perfecto simple'); ReportPersons = $true },
    @{ TitlePattern = 'Futuro simple'; Label = 'Futuro simple'; VocabularySections = @('Futuro simple'); ReportPersons = $true },
    @{ TitlePattern = 'Gerundio'; Label = 'Gerundio'; VocabularySections = @('Gerundio'); ReportPersons = $false }
  )
}

function Get-TenseLemmaCoverageRows {
  param(
    [object[]]$PhraseSections,
    [object[]]$TenseCoverageSpecs
  )

  $rows = New-Object System.Collections.Generic.List[object]
  $usageMaps = Get-TenseSectionUsageMaps -PhraseSections $PhraseSections -TenseCoverageSpecs $TenseCoverageSpecs
  foreach ($usage in $usageMaps.Values) {
    foreach ($lemma in @($usage.LemmaUsage.Keys | Sort-Object -Unique)) {
      $rows.Add([pscustomobject]@{
        Tense = $usage.Rule.Label
        Lemma = $lemma
        Covered = $(if ($usage.LemmaUsage[$lemma] -gt 0) { 'да' } else { 'нет' })
      }) | Out-Null
    }
  }

  return $rows
}

function Get-TensePersonCoverageRows {
  param(
    [object[]]$PhraseSections,
    [object[]]$TenseCoverageSpecs
  )

  $rows = New-Object System.Collections.Generic.List[object]
  $usageMaps = Get-TenseSectionUsageMaps -PhraseSections $PhraseSections -TenseCoverageSpecs $TenseCoverageSpecs
  foreach ($rule in (Get-TenseCoverageRules | Where-Object { $_.ReportPersons })) {
    $section = $PhraseSections | Where-Object { $_.Title -match $rule.TitlePattern } | Select-Object -First 1
    if ($null -eq $section) { continue }

    $personCounts = @{}
    foreach ($personRule in (Get-PersonRules)) {
      $personCounts[$personRule.Label] = 0
    }

    $usage = $usageMaps[$section.Title]
    if ($null -ne $usage) {
      foreach ($person in $usage.PersonUsage.Keys) {
        $personCounts[$person] = [int]$usage.PersonUsage[$person]
      }
    }

    foreach ($phrase in $section.Phrases) {
      foreach ($label in (Get-PersonLabelsForPhrase -Phrase $phrase)) {
        if ($personCounts[$label] -eq 0) {
          $personCounts[$label]++
        }
      }
    }

    foreach ($personRule in (Get-PersonRules)) {
      $rows.Add([pscustomobject]@{
        Title = $section.Title
        Person = $personRule.Label
        Covered = $(if ($personCounts[$personRule.Label] -gt 0) { 'да' } else { 'нет' })
        Count = $personCounts[$personRule.Label]
      }) | Out-Null
    }
  }

  return $rows
}

function Get-TensePersonBalanceFindings {
  param([object[]]$PersonCoverageRows)

  $findings = New-Object System.Collections.Generic.List[object]
  foreach ($sectionGroup in ($PersonCoverageRows | Group-Object Title)) {
    $rows = @($sectionGroup.Group)
    if ($rows.Count -eq 0) { continue }

    $counts = @{}
    foreach ($row in $rows) {
      $counts[$row.Person] = [int]$row.Count
    }

    $yoCount = [int]$counts['yo']
    $otherRows = @($rows | Where-Object { $_.Person -ne 'yo' })
    $maxOtherCount = [int](($otherRows | Measure-Object -Property Count -Maximum).Maximum)
    $sumOtherCounts = [int](($otherRows | Measure-Object -Property Count -Sum).Sum)
    $totalCount = $yoCount + $sumOtherCounts

    if ($totalCount -lt 6) { continue }
    if ($yoCount -lt 4) { continue }
    if ($yoCount -le $sumOtherCounts) { continue }
    if ($yoCount -lt ($maxOtherCount + 3)) { continue }

    $findings.Add([pscustomobject]@{
      Title = $sectionGroup.Name
      Skew = "yo=$yoCount, tú=$([int]$counts['tú']), él / ella / usted=$([int]$counts['él / ella / usted']), nosotros/as=$([int]$counts['nosotros/as']), vosotros/as=$([int]$counts['vosotros/as']), ellos / ellas / ustedes=$([int]$counts['ellos / ellas / ustedes'])"
      Reason = 'стартовый блок слишком концентрируется на `yo`; перераспределить часть фраз на другие лица'
    }) | Out-Null
  }

  return $findings
}

function Get-ReductionCandidates {
  param(
    [object[]]$PhraseSections,
    [object[]]$CanonicalEntries,
    [object[]]$PersonCoverageRows,
    [object[]]$TenseCoverageSpecs
  )

  $candidates = New-Object System.Collections.Generic.List[object]
  $usageMaps = Get-TenseSectionUsageMaps -PhraseSections $PhraseSections -TenseCoverageSpecs $TenseCoverageSpecs

  foreach ($section in $PhraseSections) {
    $sectionUsage = $usageMaps[$section.Title]
    foreach ($row in $section.Rows) {
      $matchedEntries = @(
        $CanonicalEntries |
        Where-Object { (Get-UsageCount -Matcher $_.Matcher -Phrases @($row.Spanish)) -gt 0 }
      )
      if ($matchedEntries.Count -eq 0) { continue }

      $hasUniqueCoverage = $false
      foreach ($entry in $matchedEntries) {
        if ($entry.Count -le 1) {
          $hasUniqueCoverage = $true
          break
        }
      }
      if ($hasUniqueCoverage) { continue }

      $phrasePersons = @(Get-PersonLabelsForPhrase -Phrase $row.Spanish)
      $breaksPersonCoverage = $false
      foreach ($person in $phrasePersons) {
        $personRow = $PersonCoverageRows | Where-Object { $_.Title -eq $section.Title -and $_.Person -eq $person } | Select-Object -First 1
        if ($null -ne $personRow -and $personRow.Count -le 1) {
          $breaksPersonCoverage = $true
          break
        }
      }
      if ($breaksPersonCoverage) { continue }

      $breaksTenseLemmaCoverage = $false
      if ($null -ne $sectionUsage) {
        $matchedSpecs = @(
          $TenseCoverageSpecs |
          Where-Object {
            $_.Tense -eq $sectionUsage.Rule.Label -and
            (Get-UsageCount -Matcher $_.Matcher -Phrases @($row.Spanish)) -gt 0
          }
        )

        foreach ($lemma in @($matchedSpecs | Where-Object { $_.Lemma -ne '' } | Select-Object -ExpandProperty Lemma -Unique)) {
          if ($sectionUsage.LemmaUsage[$lemma] -le 1) {
            $breaksTenseLemmaCoverage = $true
            break
          }
        }
      }
      if ($breaksTenseLemmaCoverage) { continue }

      $candidates.Add([pscustomobject]@{
        Title = $section.Title
        Spanish = $row.Spanish
        Reason = 'все канонические покрытия дублируются в других фразах'
      }) | Out-Null
    }
  }

  return $candidates
}

function Get-OveruseThreshold {
  param([object[]]$CoveredEntries)

  if ($CoveredEntries.Count -eq 0) { return 3 }

  $average = ($CoveredEntries | Measure-Object -Property Count -Average).Average
  $threshold = [Math]::Ceiling([double]$average * 1.5)
  return [Math]::Max(3, [int]$threshold)
}

function Get-TopicValidationRules {
  return @(
    @{
      TitlePattern = 'Presente'
      RequiredSections = @('Presente')
      Expectation = 'форму presente'
      ValidationMode = 'entries'
    },
    @{
      TitlePattern = 'Календарь'
      RequiredSections = @('Месяцы и дни недели')
      Expectation = 'месяц или день недели'
      ValidationMode = 'entries'
    },
    @{
      TitlePattern = 'Время и даты'
      RequiredSections = @('Фразы про время и даты')
      Expectation = 'формулу времени или даты'
      ValidationMode = 'time_date'
    },
    @{
      TitlePattern = 'Погода: hace/está/hay'
      RequiredSections = @('Hace', 'Está', 'Hay')
      Expectation = 'погодную форму `hace` / `está` / `hay`'
      ValidationMode = 'weather'
    },
    @{
      TitlePattern = 'Погода: осадки/явления'
      RequiredSections = @('Осадки и явления', 'Времена года')
      Expectation = 'осадки, явление или время года'
      ValidationMode = 'entries'
    },
    @{
      TitlePattern = 'Природа'
      RequiredSections = @('Природа')
      Expectation = 'слово по теме природы'
      ValidationMode = 'entries'
    },
    @{
      TitlePattern = 'Gerundio'
      RequiredSections = @('Gerundio')
      Expectation = 'форму gerundio'
      ValidationMode = 'entries'
    },
    @{
      TitlePattern = 'Pretérito perfecto simple'
      RequiredSections = @('Pretérito perfecto simple')
      Expectation = 'форму pretérito perfecto simple'
      ValidationMode = 'entries'
    },
    @{
      TitlePattern = 'Pretérito perfecto:'
      RequiredSections = @('Pretérito perfecto')
      Expectation = 'форму pretérito perfecto'
      ValidationMode = 'entries'
    },
    @{
      TitlePattern = 'Imperfecto'
      RequiredSections = @('Imperfecto')
      Expectation = 'форму imperfecto'
      ValidationMode = 'entries'
    },
    @{
      TitlePattern = 'Futuro simple'
      RequiredSections = @('Futuro simple')
      Expectation = 'форму futuro simple'
      ValidationMode = 'future'
    }
  )
}

function Test-PhraseMatchesAnyEntry {
  param(
    [string]$Phrase,
    [object[]]$Entries
  )

  foreach ($entry in $Entries) {
    if ((Get-UsageCount -Matcher $entry.Matcher -Phrases @($Phrase)) -gt 0) {
      return $true
    }
  }

  return $false
}

function Test-HasNumericPhrase {
  param([string]$Phrase)

  $normalized = Get-NormalizedText $Phrase
  return ($normalized -match '\b(céro|úno|úna|dos|tres|cuátro|cínco|seis|siéte|ócho|nuéve|diez|ónce|dóce|tréce|catórce|quínce|dieciséis|diecisiéte|dieciócho|diecinuéve|véinte|veintiúno|veintidós|tréinta|cuarénta|cincuénta|sesénta|seténta|ochénta|novénta|cien|dosciéntos|tresciéntos|cuatrociéntos|quiniéntos|seisciéntos|seteciéntos|ochociéntos|noveciéntos|mil|priméro|segúndo|tercéro|cuárto|quínto|séxto|séptimo|octávo|novéno|décimo|undécimo|duodécimo|decimotercéro|decimocuárto|decimoquínto)\b')
}

function Test-HasTimeDateFormula {
  param([string]$Phrase)

  $normalized = Get-NormalizedText $Phrase
  return ($normalized -match '(son las|a las|qué hóra|a qué hóra|cuántos estámos|fécha|cumpleáños|mes estámos|lúnes que viéne|semána que viéne|de la mañána|de la tárde|de la nóche|en púnto|y média|ménos cuárto|y cuárto|hoy es)')
}

function Test-HasWeatherThemeForm {
  param([string]$Phrase)

  $normalized = Get-NormalizedText $Phrase
  return ($normalized -match '\b(hace|está|hay)\b')
}

function Test-HasFutureThemeForm {
  param([string]$Phrase)

  $normalized = Get-NormalizedText $Phrase
  return ($normalized -match '\b([a-záéíóú]+(é|[áa]s|[áa]|[ée]mos|[ée]is|[áa]n)|voy a|vas a|va a|vamos a|vais a|van a)\b')
}

function Get-TopicValidationFindings {
  param(
    [object[]]$PhraseSections,
    [object[]]$VocabularyEntries
  )

  $findings = New-Object System.Collections.Generic.List[object]
  $rules = Get-TopicValidationRules

  foreach ($phraseSection in $PhraseSections) {
    $rule = $rules | Where-Object { $phraseSection.Title -match $_.TitlePattern } | Select-Object -First 1
    if ($null -eq $rule) { continue }

    $requiredEntries = @(
      $VocabularyEntries |
      Where-Object { $_.Section -in $rule.RequiredSections }
    )
    if ($requiredEntries.Count -eq 0) { continue }

    foreach ($phrase in $phraseSection.Phrases) {
      $matchesRule = switch ($rule.ValidationMode) {
        'number' { Test-HasNumericPhrase -Phrase $phrase }
        'time_date' { Test-HasTimeDateFormula -Phrase $phrase }
        'weather' { Test-HasWeatherThemeForm -Phrase $phrase }
        'future' { Test-HasFutureThemeForm -Phrase $phrase }
        default { Test-PhraseMatchesAnyEntry -Phrase $phrase -Entries $requiredEntries }
      }

      if (-not $matchesRule) {
        $findings.Add([pscustomobject]@{
          Title = $phraseSection.Title
          Phrase = $phrase
          Expectation = $rule.Expectation
        }) | Out-Null
      }
    }
  }

  return $findings
}

function Get-TimeContextValidationRules {
  return @(
    @{ TitlePattern = 'Gerundio' },
    @{ TitlePattern = 'Pretérito perfecto:' },
    @{ TitlePattern = 'Imperfecto' },
    @{ TitlePattern = 'Pretérito perfecto simple' },
    @{ TitlePattern = 'Futuro simple' }
  )
}

function Test-HasTimeContext {
  param([string]$Phrase)

  $normalized = Get-NormalizedText $Phrase
  if ($normalized -eq '') { return $false }

  $patterns = @(
    '\bahora\b',
    '\bhoy\b',
    '\bmañ[áa]na\b',
    '\bayér\b',
    '\banteayér\b',
    '\banoche\b',
    '\btemprano\b',
    '\bt[áa]rde\b',
    '\bn[óo]che\b',
    '\bdesp[uú]és\b',
    '\bluego\b',
    '\bantes\b',
    '\btodav[ií]a\b',
    '\ba[uú]n\b',
    '\bya\b',
    '\bsi[ée]mpre\b',
    '\bn[uú]nca\b',
    '\botra vez\b',
    '\búna vez\b',
    '\bentónces\b',
    '\bde repénte\b',
    '\baquél día\b',
    '\besta mañ[áa]na\b',
    '\besta t[áa]rde\b',
    '\besta n[óo]che\b',
    '\bpor la mañ[áa]na\b',
    '\bpor la t[áa]rde\b',
    '\bpor la n[óo]che\b',
    '\besta sem[áa]na\b',
    '\bla sem[áa]na pas[áa]da\b',
    '\bel mes pas[áa]do\b',
    '\bel a[ñn]o pas[áa]do\b',
    '\beste fin de sem[áa]na\b',
    '\bla sem[áa]na que vi[ée]ne\b',
    '\bel (l[úu]nes|m[áa]rtes|mi[ée]rcoles|ju[ée]ves|vi[ée]rnes|s[áa]b[áa]do|dom[íi]ngo)\b',
    '\beste (l[úu]nes|m[áa]rtes|mi[ée]rcoles|ju[ée]ves|vi[ée]rnes|s[áa]b[áa]do|dom[íi]ngo)\b',
    '\ben (en[ée]ro|febr[ée]ro|m[áa]rzo|abr[íi]l|m[áa]yo|j[úu]nio|j[úu]lio|ag[óo]sto|septi[ée]mbre|oct[úu]bre|novi[ée]mbre|dici[ée]mbre|invi[ée]rno|primav[ée]ra|ver[áa]no|ot[óo]ño)\b',
    '\bun á[ñn]o\b',
    '\bh[aá]ce [a-záéíóú0-9 ]+\b',
    '\b[0-9]{4}\b'
  )

  foreach ($pattern in $patterns) {
    if ($normalized -match $pattern) {
      return $true
    }
  }

  return $false
}

function Get-TimeContextValidationFindings {
  param([object[]]$PhraseSections)

  $findings = New-Object System.Collections.Generic.List[object]
  $rules = Get-TimeContextValidationRules

  foreach ($phraseSection in $PhraseSections) {
    $rule = $rules | Where-Object { $phraseSection.Title -match $_.TitlePattern } | Select-Object -First 1
    if ($null -eq $rule) { continue }

    foreach ($phrase in $phraseSection.Phrases) {
      if (-not (Test-HasTimeContext -Phrase $phrase)) {
        $findings.Add([pscustomobject]@{
          Title = $phraseSection.Title
          Phrase = $phrase
          Expectation = 'уместное указание времени для этой темы'
        }) | Out-Null
      }
    }
  }

  return $findings
}

function Get-RussianTranslationValidationRules {
  return @(
    @{
      Pattern = '^В каком мы месяце\?$'
      Reason = 'слишком дословный русский перевод'
      Suggestion = 'Какой сейчас месяц?'
    },
    @{
      Pattern = '^Сегодня .+ здесь\.$'
      Reason = 'неестественный порядок слов в русском переводе'
      Suggestion = 'Перестроить фразу, например: "Здесь сегодня ..."'
    },
    @{
      Pattern = '^Это всё ещё утро\.$'
      Reason = 'слишком дословный русский перевод'
      Suggestion = 'Сейчас ещё утро.'
    },
    @{
      Pattern = '^Сегодня среда октября\.$'
      Reason = 'слишком дословный русский перевод'
      Suggestion = 'Сегодня одна из сред октября.'
    },
    @{
      Pattern = '^Я не хочу хотеть .+\.$'
      Reason = 'неестественная русская калька с `не хочу хотеть ...`'
      Suggestion = 'Перестроить по-русски естественно, например: "Я не хочу пить сегодня."'
    }
  )
}

function Get-RussianTranslationValidationFindings {
  param([object[]]$PhraseSections)

  $findings = New-Object System.Collections.Generic.List[object]
  $rules = Get-RussianTranslationValidationRules

  foreach ($phraseSection in $PhraseSections) {
    foreach ($row in $phraseSection.Rows) {
      foreach ($rule in $rules) {
        if ($row.Russian -match $rule.Pattern) {
          $findings.Add([pscustomobject]@{
            Title = $phraseSection.Title
            Spanish = $row.Spanish
            Russian = $row.Russian
            Reason = $rule.Reason
            Suggestion = $rule.Suggestion
          }) | Out-Null
          break
        }
      }
    }
  }

  return $findings
}

function Get-PhraseFormattingValidationFindings {
  param([object[]]$PhraseSections)

  $findings = New-Object System.Collections.Generic.List[object]

  foreach ($phraseSection in $PhraseSections) {
    foreach ($row in $phraseSection.Rows) {
      if ($row.Spanish -match '=') {
        $findings.Add([pscustomobject]@{
          Title = $phraseSection.Title
          Spanish = $row.Spanish
          Russian = $row.Russian
          Reason = 'псевдо-словарная запись вместо учебной фразы'
          Suggestion = 'Заменить на нормальное предложение без `=`'
        }) | Out-Null
        continue
      }

      if (($row.Spanish -match '[\\/]' ) -or ($row.Russian -match '[\\/]')) {
        $findings.Add([pscustomobject]@{
          Title = $phraseSection.Title
          Spanish = $row.Spanish
          Russian = $row.Russian
          Reason = 'строка с вариантами через слеш вместо отдельной фразы'
          Suggestion = 'Развернуть варианты в отдельные фразы без `/` и `\`'
        }) | Out-Null
      }
    }
  }

  return $findings
}

function Get-PlaceAdverbBalanceFindings {
  param(
    [object[]]$CanonicalEntries,
    [object[]]$CoveredEntries
  )

  $targets = @('acá', 'ahí', 'allá', 'allí', 'aquí')
  $relevantCanonical = @(
    $CanonicalEntries |
    Where-Object { $_.Section -eq 'Наречия места' -and $_.Entry -in $targets }
  )

  if ($relevantCanonical.Count -lt 3) {
    return @()
  }

  $counts = @{}
  foreach ($target in $targets) {
    $counts[$target] = 0
  }

  foreach ($entry in $CoveredEntries) {
    if ($entry.Section -eq 'Наречия места' -and $entry.Entry -in $targets) {
      $counts[$entry.Entry] = [int]$entry.Count
    }
  }

  $aquiCount = [int]$counts['aquí']
  $otherCounts = @(
    $targets |
    Where-Object { $_ -ne 'aquí' } |
    ForEach-Object { [int]$counts[$_] }
  )
  $maxOtherCount = [int](($otherCounts | Measure-Object -Maximum).Maximum)
  $sumOtherCounts = [int](($otherCounts | Measure-Object -Sum).Sum)

  if (($aquiCount -ge 10) -and ($aquiCount -gt ($maxOtherCount * 2.5)) -and ($aquiCount -ge ($sumOtherCounts + 6))) {
    return @(
      [pscustomobject]@{
        Focus = 'aquí'
        Counts = "acá=$($counts['acá']), ahí=$($counts['ahí']), allá=$($counts['allá']), allí=$($counts['allí']), aquí=$aquiCount"
        Reason = '`aquí` используется несоразмерно чаще остальных наречий места'
        Suggestion = 'Заменить часть нейтральных `aquí` на `ahí`, `allí`, `allá` или `acá`, где это естественно.'
      }
    )
  }

  return @()
}

function Format-UsageTable {
  param(
    [string]$CountHeader,
    [bool]$IncludeCount,
    [object[]]$Entries
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("| Раздел | Элемент | $CountHeader |") | Out-Null
  $lines.Add('| --- | --- | --- |') | Out-Null

  foreach ($entry in $Entries) {
    if ($IncludeCount) {
      $lines.Add("| $($entry.Section) | $($entry.Entry) | $($entry.Count) |") | Out-Null
    }
    else {
      $lines.Add("| $($entry.Section) | $($entry.Entry) |") | Out-Null
    }
  }

  return $lines
}

function Format-LegacyEntryTable {
  param([object[]]$Entries)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Раздел | Элемент | Причина |') | Out-Null
  $lines.Add('| --- | --- | --- |') | Out-Null
  foreach ($entry in $Entries) {
    $lines.Add("| $($entry.Section) | $($entry.Entry) | $($entry.LegacyReason) |") | Out-Null
  }
  return $lines
}

function Format-TenseLemmaCoverageTable {
  param([object[]]$Rows)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Время | Лемма | Покрыто |') | Out-Null
  $lines.Add('| --- | --- | --- |') | Out-Null
  foreach ($row in $Rows) {
    $lines.Add("| $($row.Tense) | $($row.Lemma) | $($row.Covered) |") | Out-Null
  }
  return $lines
}

function Format-TensePersonCoverageTable {
  param([object[]]$Rows)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Тема | Лицо | Покрыто |') | Out-Null
  $lines.Add('| --- | --- | --- |') | Out-Null
  foreach ($row in $Rows) {
    $lines.Add("| $($row.Title) | $($row.Person) | $($row.Covered) |") | Out-Null
  }
  return $lines
}

function Format-ReductionCandidatesTable {
  param([object[]]$Rows)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Тема | Испанский | Почему можно убрать |') | Out-Null
  $lines.Add('| --- | --- | --- |') | Out-Null
  foreach ($row in $Rows) {
    $lines.Add("| $($row.Title) | $($row.Spanish) | $($row.Reason) |") | Out-Null
  }
  return $lines
}

function Format-TopicValidationTable {
  param([object[]]$Findings)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Тема | Фраза | Ожидалось |') | Out-Null
  $lines.Add('| --- | --- | --- |') | Out-Null

  foreach ($finding in $Findings) {
    $lines.Add("| $($finding.Title) | $($finding.Phrase) | $($finding.Expectation) |") | Out-Null
  }

  return $lines
}

function Format-TimeContextValidationTable {
  param([object[]]$Findings)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Тема | Фраза | Ожидалось |') | Out-Null
  $lines.Add('| --- | --- | --- |') | Out-Null

  foreach ($finding in $Findings) {
    $lines.Add("| $($finding.Title) | $($finding.Phrase) | $($finding.Expectation) |") | Out-Null
  }

  return $lines
}

function Format-RussianTranslationValidationTable {
  param([object[]]$Findings)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Тема | Испанский | Русский | Проблема | Лучше так |') | Out-Null
  $lines.Add('| --- | --- | --- | --- | --- |') | Out-Null

  foreach ($finding in $Findings) {
    $lines.Add("| $($finding.Title) | $($finding.Spanish) | $($finding.Russian) | $($finding.Reason) | $($finding.Suggestion) |") | Out-Null
  }

  return $lines
}

function Format-PhraseFormattingValidationTable {
  param([object[]]$Findings)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Тема | Испанский | Русский | Проблема | Лучше так |') | Out-Null
  $lines.Add('| --- | --- | --- | --- | --- |') | Out-Null

  foreach ($finding in $Findings) {
    $lines.Add("| $($finding.Title) | $($finding.Spanish) | $($finding.Russian) | $($finding.Reason) | $($finding.Suggestion) |") | Out-Null
  }

  return $lines
}

function Format-PlaceAdverbBalanceTable {
  param([object[]]$Findings)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Фокус | Текущие счётчики | Проблема | Что сделать |') | Out-Null
  $lines.Add('| --- | --- | --- | --- |') | Out-Null

  foreach ($finding in $Findings) {
    $lines.Add("| $($finding.Focus) | $($finding.Counts) | $($finding.Reason) | $($finding.Suggestion) |") | Out-Null
  }

  return $lines
}

function Format-TensePersonBalanceTable {
  param([object[]]$Findings)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('| Тема | Перекос | Что проверить |') | Out-Null
  $lines.Add('| --- | --- | --- |') | Out-Null

  foreach ($finding in $Findings) {
    $lines.Add("| $($finding.Title) | $($finding.Skew) | $($finding.Reason) |") | Out-Null
  }

  return $lines
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

$vocabularyEntries = Get-VocabularyEntries -Path $VocabularyPath
$phraseRows = Get-PhraseRows -Path $PhrasesPath
$phraseSections = Get-PhraseSections -Path $PhrasesPath
$analysisPhraseSections = @($phraseSections | Where-Object { $_.Title -notmatch 'Числительные' })

$legacyEntries = @($vocabularyEntries | Where-Object { $_.IsLegacy } | Sort-Object Section, Entry -Unique)
$topicValidationEntries = @($vocabularyEntries | Where-Object { (-not $_.IsLegacy) -and ($_.Group -ne 'Числительные') })
$canonicalEntries = @($topicValidationEntries | Where-Object { $_.CountsTowardCoverage })
$supplementalEntries = @(
  $vocabularyEntries |
  Where-Object { Test-SupplementalEntry $_ } |
  Sort-Object Section, Entry -Unique
)

$results = @(
foreach ($entry in $canonicalEntries) {
  [pscustomobject]@{
    Group = $entry.Group
    Section = $entry.Section
    Entry = $entry.Entry
    Matcher = $entry.Matcher
    Count = Get-UsageCount -Matcher $entry.Matcher -Phrases $phraseRows
  }
}
)

$supplementalResults = @(
foreach ($entry in $supplementalEntries) {
  [pscustomobject]@{
    Group = $entry.Group
    Section = $entry.Section
    Entry = $entry.Entry
    Matcher = $entry.Matcher
    Count = Get-UsageCount -Matcher $entry.Matcher -Phrases $phraseRows
  }
}
)

$covered = @($results | Where-Object { $_.Count -gt 0 } | Sort-Object Section, Entry)
$unused = @($results | Where-Object { $_.Count -eq 0 } | Sort-Object Section, Entry)
$overuseThreshold = Get-OveruseThreshold -CoveredEntries $covered
$overused = @($covered | Where-Object { $_.Count -ge $overuseThreshold } | Sort-Object @{ Expression = 'Count'; Descending = $true }, Section, Entry)
$tenseCoverageSpecs = @(Get-TenseCoverageSpecs -Path $VocabularyPath)
$tenseLemmaCoverageRows = @(Get-TenseLemmaCoverageRows -PhraseSections $analysisPhraseSections -TenseCoverageSpecs $tenseCoverageSpecs)
$tensePersonCoverageRows = @(Get-TensePersonCoverageRows -PhraseSections $analysisPhraseSections -TenseCoverageSpecs $tenseCoverageSpecs)
$topicValidationFindings = @(
  Get-TopicValidationFindings -PhraseSections $analysisPhraseSections -VocabularyEntries $topicValidationEntries
)
$timeContextValidationFindings = @(
  Get-TimeContextValidationFindings -PhraseSections $analysisPhraseSections
)
$russianTranslationValidationFindings = @(
  Get-RussianTranslationValidationFindings -PhraseSections $analysisPhraseSections
)
$phraseFormattingValidationFindings = @(
  Get-PhraseFormattingValidationFindings -PhraseSections $analysisPhraseSections
)
$tensePersonBalanceFindings = @(
  Get-TensePersonBalanceFindings -PersonCoverageRows $tensePersonCoverageRows
)
$placeAdverbBalanceFindings = @(
  Get-PlaceAdverbBalanceFindings -CanonicalEntries $canonicalEntries -CoveredEntries $covered
)
$reductionCandidates = @(
  Get-ReductionCandidates -PhraseSections $analysisPhraseSections -CanonicalEntries $covered -PersonCoverageRows $tensePersonCoverageRows -TenseCoverageSpecs $tenseCoverageSpecs
)

$report = New-Object System.Collections.Generic.List[string]
$report.Add('# words usage') | Out-Null
$report.Add('') | Out-Null
$report.Add("Источник словаря: ``$([System.IO.Path]::GetFileName($VocabularyPath))``") | Out-Null
$report.Add("Источник фраз: ``$([System.IO.Path]::GetFileName($PhrasesPath))``") | Out-Null
$report.Add('') | Out-Null
$report.Add("Всего словарных элементов: $($results.Count)") | Out-Null
$report.Add("Покрыто: $($covered.Count)") | Out-Null
$report.Add("Неиспользовано: $($unused.Count)") | Out-Null
$report.Add("Порог перегрузки: $overuseThreshold") | Out-Null
$report.Add("Дополнительных слов длиной 3+ вне канонического покрытия: $($supplementalResults.Count)") | Out-Null
$report.Add("Нарушений по теме: $($topicValidationFindings.Count)") | Out-Null
$report.Add("Нарушений по временному контексту: $($timeContextValidationFindings.Count)") | Out-Null
$report.Add("Замечаний по русскому переводу: $($russianTranslationValidationFindings.Count)") | Out-Null
$report.Add("Замечаний по оформлению фраз: $($phraseFormattingValidationFindings.Count)") | Out-Null
$report.Add("Замечаний по балансу лиц во временных разделах: $($tensePersonBalanceFindings.Count)") | Out-Null
$report.Add("Замечаний по балансу наречий места: $($placeAdverbBalanceFindings.Count)") | Out-Null
$report.Add('') | Out-Null
$report.Add('## Покрытые элементы') | Out-Null
$report.Add('') | Out-Null
Add-ReportLines -Target $report -Lines (Format-UsageTable -CountHeader 'Использований' -IncludeCount $true -Entries $covered)
$report.Add('') | Out-Null
$report.Add('## Канонически неучитываемые legacy-элементы') | Out-Null
$report.Add('') | Out-Null
if ($legacyEntries.Count -eq 0) {
  $report.Add('Нет legacy-элементов.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-LegacyEntryTable -Entries $legacyEntries)
}
$report.Add('') | Out-Null
$report.Add('## Дополнительные слова вне канонического покрытия') | Out-Null
$report.Add('') | Out-Null
if ($supplementalResults.Count -eq 0) {
  $report.Add('Нет дополнительных слов.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-UsageTable -CountHeader 'Использований' -IncludeCount $true -Entries $supplementalResults)
}
$report.Add('') | Out-Null
$report.Add('## Неиспользованные элементы') | Out-Null
$report.Add('') | Out-Null
Add-ReportLines -Target $report -Lines (Format-UsageTable -CountHeader 'Статус' -IncludeCount $false -Entries $unused)
$report.Add('') | Out-Null
$report.Add('## Потенциально перегруженные элементы') | Out-Null
$report.Add('') | Out-Null
Add-ReportLines -Target $report -Lines (Format-UsageTable -CountHeader 'Использований' -IncludeCount $true -Entries $overused)
$report.Add('') | Out-Null
$report.Add('## Покрытие глаголов по временам') | Out-Null
$report.Add('') | Out-Null
if ($tenseLemmaCoverageRows.Count -eq 0) {
  $report.Add('Нет данных.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-TenseLemmaCoverageTable -Rows $tenseLemmaCoverageRows)
}
$report.Add('') | Out-Null
$report.Add('## Покрытие лиц по временным разделам') | Out-Null
$report.Add('') | Out-Null
if ($tensePersonCoverageRows.Count -eq 0) {
  $report.Add('Нет данных.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-TensePersonCoverageTable -Rows $tensePersonCoverageRows)
}
$report.Add('') | Out-Null
$report.Add('## Кандидаты на сокращение фраз') | Out-Null
$report.Add('') | Out-Null
if ($reductionCandidates.Count -eq 0) {
  $report.Add('Кандидатов не найдено.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-ReductionCandidatesTable -Rows $reductionCandidates)
}
$report.Add('') | Out-Null
$report.Add('## Проверка соответствия темам') | Out-Null
$report.Add('') | Out-Null
if ($topicValidationFindings.Count -eq 0) {
  $report.Add('Нарушений не найдено.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-TopicValidationTable -Findings $topicValidationFindings)
}
$report.Add('') | Out-Null
$report.Add('## Проверка временного контекста') | Out-Null
$report.Add('') | Out-Null
if ($timeContextValidationFindings.Count -eq 0) {
  $report.Add('Нарушений не найдено.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-TimeContextValidationTable -Findings $timeContextValidationFindings)
}
$report.Add('') | Out-Null
$report.Add('## Проверка русских переводов') | Out-Null
$report.Add('') | Out-Null
if ($russianTranslationValidationFindings.Count -eq 0) {
  $report.Add('Замечаний не найдено.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-RussianTranslationValidationTable -Findings $russianTranslationValidationFindings)
}
$report.Add('') | Out-Null
$report.Add('## Проверка оформления фраз') | Out-Null
$report.Add('') | Out-Null
if ($phraseFormattingValidationFindings.Count -eq 0) {
  $report.Add('Замечаний не найдено.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-PhraseFormattingValidationTable -Findings $phraseFormattingValidationFindings)
}
$report.Add('') | Out-Null
$report.Add('## Ребаланс лиц по временным разделам') | Out-Null
$report.Add('') | Out-Null
if ($tensePersonBalanceFindings.Count -eq 0) {
  $report.Add('Замечаний не найдено.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-TensePersonBalanceTable -Findings $tensePersonBalanceFindings)
}
$report.Add('') | Out-Null
$report.Add('## Ребаланс наречий места') | Out-Null
$report.Add('') | Out-Null
if ($placeAdverbBalanceFindings.Count -eq 0) {
  $report.Add('Замечаний не найдено.') | Out-Null
}
else {
  Add-ReportLines -Target $report -Lines (Format-PlaceAdverbBalanceTable -Findings $placeAdverbBalanceFindings)
}
$report.Add('') | Out-Null

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and (-not (Test-Path -LiteralPath $outputDirectory))) {
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllLines($OutputPath, [string[]]$report, [System.Text.Encoding]::UTF8)
