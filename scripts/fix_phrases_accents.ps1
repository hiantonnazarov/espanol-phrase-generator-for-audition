param(
  [string]$Path
)

$ErrorActionPreference = 'Stop'

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($Path -eq '') {
  $Path = (Join-Path $RootDir '5_phrases.md')
}

if (-not (Test-Path -LiteralPath $Path)) {
  throw "File not found: $Path"
}

$EsFixes = @{
  'aqu'        = 'aquí'
  'manana'     = 'mañana'
  'anos'       = 'años'
  'frio'       = 'frío'
  'crer'       = 'creér'
  'durmio'     = 'durmió'
  'pidio'      = 'pidió'

  # Pretérito: -yó / -yeron
  'leyo'       = 'leyó'
  'leyeron'    = 'leyéron'
  'cayo'       = 'cayó'
  'cayeron'    = 'cayéron'
  'oyo'        = 'oyó'
  'oyeron'     = 'oyéron'
  'creyo'      = 'creyó'
  'creyeron'   = 'creyéron'
}

function RemoveAcuteAccents([string]$s) {
  return ($s `
    -replace 'á','a' -replace 'é','e' -replace 'í','i' -replace 'ó','o' -replace 'ú','u' `
    -replace 'Á','A' -replace 'É','E' -replace 'Í','I' -replace 'Ó','O' -replace 'Ú','U')
}

function HasAccent([string]$s) {
  return $s -match '[áéíóúÁÉÍÓÚ]'
}

function IsVowel([char]$ch, [bool]$allowY) {
  $s = [string]$ch
  if ($s -match '[aeiouáéíóúüAEIOUÁÉÍÓÚÜ]') { return $true }
  if ($allowY -and ($s -eq 'y' -or $s -eq 'Y')) { return $true }
  return $false
}

function Strength([char]$ch) {
  $s = ([string]$ch).ToLowerInvariant()
  $s = $s -replace 'á','a' -replace 'é','e' -replace 'í','i' -replace 'ó','o' -replace 'ú','u' -replace 'ü','u'
  if ($s -in @('a','e','o')) { return 'strong' }
  if ($s -in @('i','u','y')) { return 'weak' }
  return 'other'
}

function AccentVowel([char]$ch) {
  switch ([string]$ch) {
    'a' { return 'á' }
    'e' { return 'é' }
    'i' { return 'í' }
    'o' { return 'ó' }
    'u' { return 'ú' }
    'A' { return 'Á' }
    'E' { return 'É' }
    'I' { return 'Í' }
    'O' { return 'Ó' }
    'U' { return 'Ú' }
    default { return [string]$ch }
  }
}

function Nuclei([string]$word) {
  $indices = New-Object System.Collections.Generic.List[int]
  $i = 0
  while ($i -lt $word.Length) {
    if (-not (IsVowel $word[$i] ($i -eq $word.Length - 1))) { $i++; continue }
    $cluster = New-Object System.Collections.Generic.List[int]
    $cluster.Add($i) | Out-Null
    $j = $i + 1
    while ($j -lt $word.Length) {
      if (-not (IsVowel $word[$j] ($j -eq $word.Length - 1))) { break }
      if ((Strength $word[$cluster[$cluster.Count - 1]]) -eq 'strong' -and (Strength $word[$j]) -eq 'strong') { break }
      $cluster.Add($j) | Out-Null
      $j++
    }
    $target = $cluster[$cluster.Count - 1]
    foreach ($idx in $cluster) {
      if ((Strength $word[$idx]) -eq 'strong') { $target = $idx; break }
    }
    $indices.Add($target) | Out-Null
    $i = $j
  }
  return $indices
}

function ApplyWordFixes([string]$word) {
  $key = (RemoveAcuteAccents $word).ToLowerInvariant()
  if (-not $EsFixes.ContainsKey($key)) { return $word }
  $fixed = $EsFixes[$key]

  # Preserve simple TitleCase (sentence starts, names).
  if ($word.Length -gt 0 -and ($word[0] -cmatch '[A-ZÁÉÍÓÚÜÑ]') -and ($word.Substring(1) -cmatch '^[a-záéíóúüñ]+$')) {
    return ($fixed.Substring(0, 1).ToUpperInvariant() + $fixed.Substring(1))
  }

  return $fixed
}

function ApplyStressMarkers([string]$word) {
  if ($word.Length -lt 2) { return $word }

  $chars = $word.ToCharArray()
  for ($i = 1; $i -lt $chars.Length; $i++) {
    switch ([string]$chars[$i]) {
      'A' { $chars[$i] = [char]'á' }
      'E' { $chars[$i] = [char]'é' }
      'I' { $chars[$i] = [char]'í' }
      'O' { $chars[$i] = [char]'ó' }
      'U' { $chars[$i] = [char]'ú' }
    }
  }

  return -join $chars
}

function AccentWord([string]$word) {
  if (HasAccent $word) { return $word }
  $nuclei = @(Nuclei $word)
  if ($nuclei.Count -le 1) { return $word }

  $last = ([string]$word[$word.Length - 1]).ToLowerInvariant()
  $nucleusIndex = if ($last -match '[aeiouáéíóúns]') { $nuclei.Count - 2 } else { $nuclei.Count - 1 }
  if ($nucleusIndex -lt 0) { return $word }

  $pos = $nuclei[$nucleusIndex]
  return ($word.Substring(0, $pos) + (AccentVowel $word[$pos]) + $word.Substring($pos + 1))
}

function PreserveTitleCase([string]$original, [string]$replacement) {
  if ($original.Length -eq 0 -or $replacement.Length -eq 0) { return $replacement }
  if (($original[0] -cmatch '[A-ZÁÉÍÓÚÜÑ]') -and ($original.Substring(1) -cmatch '^[a-záéíóúüñ]+$')) {
    return ($replacement.Substring(0, 1).ToUpperInvariant() + $replacement.Substring(1))
  }
  return $replacement
}

function BuildVocabularyAccentMap([string]$vocabularyPath) {
  $map = @{}
  if (-not (Test-Path -LiteralPath $vocabularyPath)) { return $map }

  $vocabText = Get-Content -LiteralPath $vocabularyPath -Raw
  $wordRegex = [regex]'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+(?:-[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+)*'

  foreach ($m in $wordRegex.Matches($vocabText)) {
    $w = $m.Value
    if (-not (HasAccent $w)) { continue }
    if ($w.Length -lt 3) { continue } # avoid ambiguous monosyllables: el/él, tu/tú, mi/mí, si/sí

    $key = (RemoveAcuteAccents $w).ToLowerInvariant()
    if (-not $map.ContainsKey($key)) {
      $map[$key] = $w
      continue
    }

    # Prefer the variant with more explicit accents (usually more informative).
    $current = $map[$key]
    $currentAccents = ([regex]::Matches($current, '[áéíóúÁÉÍÓÚ]').Count)
    $newAccents = ([regex]::Matches($w, '[áéíóúÁÉÍÓÚ]').Count)
    if ($newAccents -gt $currentAccents) {
      $map[$key] = $w
    }
  }

  return $map
}

function FixWord {
  param(
    [string]$word,
    [hashtable]$VocabAccentMap,
    [System.Collections.Generic.HashSet[string]]$ProperNounKeys
  )
  if ($word -notmatch '[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]') { return $word }

  $value = ApplyStressMarkers $word

  # Normalize any previously over-accented words, then rebuild accent consistently.
  $base = (RemoveAcuteAccents $value)
  $key = $base.ToLowerInvariant()

  if ($VocabAccentMap.ContainsKey($key)) {
    $out = $VocabAccentMap[$key]
  }
  else {
    if ($base.Contains('-')) {
      $out = (($base -split '-') | ForEach-Object { AccentWord $_ }) -join '-'
    }
    else {
      $out = AccentWord $base
    }
  }

  $out = ApplyWordFixes $out

  $outLower = $out.ToLowerInvariant()
  if ($ProperNounKeys.Contains($key)) {
    return $out
  }
  return $outLower
}

function NormalizeSpanishTextCasing {
  param(
    [string]$text,
    [hashtable]$ProperNounDisplayMap
  )

  if ($text -notmatch '[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]') { return $text }
  if ($text -match '[А-Яа-яЁё]') { return $text }

  $m = [regex]::Match($text, '^(?<lead>\s*)(?<core>.*?)(?<trail>\s*)$')
  if (-not $m.Success) { return $text }
  $lead = $m.Groups['lead'].Value
  $core = $m.Groups['core'].Value
  $trail = $m.Groups['trail'].Value

  $core = $core.ToLowerInvariant()

  # Restore proper noun capitalization (match ignoring acute accents).
  $wordRegex = [regex]'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+(?:-[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+)*'
  $core = $wordRegex.Replace($core, {
    param($mm)
    $w = $mm.Value
    $wKey = (RemoveAcuteAccents $w).ToLowerInvariant()
    if (-not $ProperNounDisplayMap.ContainsKey($wKey)) { return $w }
    return $ProperNounDisplayMap[$wKey]
  })

  # Sentence case when it looks like a sentence/question (punctuation or spaces).
  if ($core -match '[\.\!\?\¿\¡]' -or $core -match '\s') {
    $core = [regex]::Replace($core, '^(?<p>\s*)(?<c>[a-záéíóúüñ])', { param($mm) $mm.Groups['p'].Value + $mm.Groups['c'].Value.ToUpperInvariant() })
    $core = [regex]::Replace($core, '([¿¡]\s*)([a-záéíóúüñ])', { param($mm) $mm.Groups[1].Value + $mm.Groups[2].Value.ToUpperInvariant() })
    $core = [regex]::Replace($core, '([\.!\?]\s+)([a-záéíóúüñ])', { param($mm) $mm.Groups[1].Value + $mm.Groups[2].Value.ToUpperInvariant() })
  }

  return $lead + $core + $trail
}

function NormalizePhrasesMarkdownCasing {
  param(
    [string]$text,
    [hashtable]$ProperNounDisplayMap
  )

  $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lines = $text -split "\r?\n", -1

  for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]

    # Keep headings as-is (they might be intentionally capitalized).
    if ($line -match '^\s*#') { continue }

    # Markdown tables: normalize each Spanish cell.
    if ($line -match '^\s*\|') {
      # Skip separator rows like | --- | --- |
      if ($line -match '^\s*\|\s*[-:\s]+\|\s*[-:\s]+\|\s*$') { continue }

      $parts = [regex]::Split($line, '\|')
      if ($parts.Length -lt 4) { continue }

      for ($c = 1; $c -lt $parts.Length - 1; $c++) {
        $parts[$c] = NormalizeSpanishTextCasing $parts[$c] $ProperNounDisplayMap
      }

      $lines[$i] = '|' + (($parts[1..($parts.Length - 2)]) -join '|') + '|'
      continue
    }

    # Spanish-only bullet lines: keep them lowercased (no forced sentence case).
    if ($line -match '^\s*-\s+' -and $line -match '[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]' -and $line -notmatch '[А-Яа-яЁё]') {
      $lines[$i] = (NormalizeSpanishTextCasing $line $ProperNounDisplayMap)
      continue
    }
  }

  return ($lines -join $newline)
}

# Replace word-like Spanish tokens (keeps punctuation intact).
$content = Get-Content -LiteralPath $Path -Raw
$VocabAccentMap = BuildVocabularyAccentMap (Join-Path $RootDir '2_vocabulary.md')
$ProperNounKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$ProperNounKeys.Add('pablo') | Out-Null
$ProperNounKeys.Add('españa') | Out-Null
$ProperNounDisplayMap = @{}
foreach ($key in $ProperNounKeys) {
  $base = $key.Substring(0, 1).ToUpperInvariant() + $key.Substring(1)
  $fixed = ApplyWordFixes $base
  $accented = if ($fixed.Contains('-')) {
    (($fixed -split '-') | ForEach-Object { AccentWord $_ }) -join '-'
  }
  else {
    AccentWord $fixed
  }
  $ProperNounDisplayMap[$key] = $accented
}
$wordRegex = [regex]'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+(?:-[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+)*'
$updated = $wordRegex.Replace($content, { param($m) FixWord $m.Value $VocabAccentMap $ProperNounKeys })
$updated = NormalizePhrasesMarkdownCasing $updated $ProperNounDisplayMap

if ($updated -cne $content) {
  Set-Content -LiteralPath $Path -Value $updated -Encoding utf8
}
