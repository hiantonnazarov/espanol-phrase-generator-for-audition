$ErrorActionPreference = 'Stop'

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RawPath = Join-Path $RootDir '1_vocabulary_raw.md'
$OutPath = Join-Path $RootDir '2_vocabulary.md'

$EsFixes = @{
  'aqu'               = 'aquí'
  'manana'            = 'mañana'
  'anos'              = 'años'
  'frequencia'        = 'frecuencia'
  'piqueno'           = 'pequeño'
  'ordenator'         = 'ordenador'
  'cuestar'           = 'costar'
  'viente'            = 'viento'
  'otono'             = 'otoño'
  'montana'           = 'montaña'
  'el son'            = 'el sol'
  'bañéra'            = 'bañera'
  'cáma'              = 'cama'
  'cocína'            = 'cocina'
  'fregadéro'         = 'fregadero'
  'lavadóra'          = 'lavadora'
  'mesílla'           = 'mesilla'
  'microóndas'        = 'microondas'
  'mueble de cocína'  = 'mueble de cocina'
  'secadóra'          = 'secadora'
  'solir'             = 'soler'
  'pedisom'           = 'pedimos'
  'frio'              = 'frío'
  'subrise'           = 'subirse'
  'cuarto de bano'    = 'cuarto de baño'
  'balcon'            = 'balcón'
  'salon'             = 'salón'
  'espana'            = 'España'
  'pasillo'           = 'pasillo'
  'pajaros'           = 'pájaros'
  'arboles'           = 'árboles'
}

$FurnitureArticles = @{
  'armario'            = 'el armario'
  'bañera'             = 'la bañera'
  'cama'               = 'la cama'
  'cocina'             = 'la cocina'
  'ducha'              = 'la ducha'
  'estantería'         = 'la estantería'
  'escritorio'         = 'el escritorio'
  'fregadero'          = 'el fregadero'
  'frigorífico'        = 'el frigorífico'
  'lavabo'             = 'el lavabo'
  'lavadora'           = 'la lavadora'
  'mesa'               = 'la mesa'
  'mesilla'            = 'la mesilla'
  'microondas'         = 'el microondas'
  'mueble de cocina'   = 'el mueble de cocina'
  'secadora'           = 'la secadora'
  'silla'              = 'la silla'
  'sillón'             = 'el sillón'
  'sofá'               = 'el sofá'
  'ventana'            = 'la ventana'
  'techo'              = 'el techo'
  'suelo'              = 'el suelo'
  'pared'              = 'la pared'
  'puerta'             = 'la puerta'
}

$ConjugationPronouns = @('yo', 'tú', 'él / ella / usted', 'nosotros/as', 'vosotros/as', 'ellos / ellas / ustedes')
$QuestionWordAllow = @('¿Qué?','¿Por qué?','¿Para qué?','¿De qué?','¿Quién?','¿Con quién?','¿Cuál?','¿Cuánto?','¿Cuánta?','¿Cómo?','¿Dónde?','¿Adónde?','¿De dónde?','¿Cuándo?')

function Clean([string]$s) {
  if ($null -eq $s) { return '' }
  $t = $s
  $t = $t -replace '!\[[^\]]*]\([^)]+\)', ''
  $t = $t -replace '\[[^\]]+]\([^)]+\)', ''
  $t = $t.Replace('**', '').Replace('__', '').Replace('*', '').Replace('_', '').Replace('`', '')
  $t = ($t -replace '\s+', ' ').Trim()
  return $t
}

function CleanRu([string]$s) {
  $t = Clean $s
  if ($t.Contains('например:')) { $t = $t.Substring(0, $t.IndexOf('например:')).Trim() }
  $t = $t.TrimEnd(',').TrimEnd(';').Trim()
  return $t
}

function ApplyEsFixes([string]$s) {
  $text = Clean $s
  if ($text -eq '') { return '' }
  $lower = $text.ToLowerInvariant()
  if ($EsFixes.ContainsKey($lower)) {
    $fixed = $EsFixes[$lower]
    if ([char]::IsUpper($text[0])) { return $fixed.Substring(0,1).ToUpperInvariant() + $fixed.Substring(1) }
    return $fixed
  }
  $parts = $text.Split(' ')
  for ($i = 0; $i -lt $parts.Length; $i++) {
    $part = $parts[$i]
    $key = $part.ToLowerInvariant()
    if ($EsFixes.ContainsKey($key)) {
      $parts[$i] = $EsFixes[$key]
    }
  }
  return ($parts -join ' ')
}

function NormalizeKey([string]$s) {
  return (Clean $s).ToLowerInvariant()
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

function AccentText([string]$text) {
  $tokens = [regex]::Split($text, '(\s+)')
  for ($i = 0; $i -lt $tokens.Count; $i++) {
    $token = $tokens[$i]
    if ($token -match '^\s+$' -or $token -eq '') { continue }
    $match = [regex]::Match($token, '^(?<prefix>[^0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ]*)(?<core>[0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ\-]+)(?<suffix>[^0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ]*)$')
    if (-not $match.Success) { continue }
    $prefix = $match.Groups['prefix'].Value
    $core = $match.Groups['core'].Value
    $suffix = $match.Groups['suffix'].Value
    if (HasAccent $core) { continue }
    $nuclei = @(Nuclei $core)
    if ($nuclei.Count -le 1) { continue }
    $last = ([string]$core[$core.Length - 1]).ToLowerInvariant()
    $nucleusIndex = if ($last -match '[aeiouáéíóúns]') { $nuclei.Count - 2 } else { $nuclei.Count - 1 }
    if ($nucleusIndex -lt 0) { continue }
    $pos = $nuclei[$nucleusIndex]
    $accented = $core.Substring(0, $pos) + (AccentVowel $core[$pos]) + $core.Substring($pos + 1)
    $tokens[$i] = $prefix + $accented + $suffix
  }
  return ($tokens -join '')
}

function FormatEs([string]$text, [string]$mode) {
  $clean = ApplyEsFixes $text
  if ($mode -eq 'preserve') { return $clean }
  return AccentText $clean
}

function Test-CanonicalDictionaryRow([string]$Spanish) {
  $clean = Clean $Spanish
  if ($clean -eq '') { return $false }
  if ($clean -match '\s=\s') { return $false }
  return $true
}

function TryParseInlinePair([string]$line) {
  $clean = Clean $line
  if ($clean -eq '' -or $clean -notmatch '[А-Яа-яЁё]') { return $null }
  $matches = [regex]::Matches($clean, '\s(?:—|-|=)\s')
  if ($matches.Count -eq 0) { return $null }

  $chosen = $null
  for ($i = $matches.Count - 1; $i -ge 0; $i--) {
    $candidate = $matches[$i]
    $suffix = $clean.Substring($candidate.Index + $candidate.Length).Trim()
    if ($suffix -match '[А-Яа-яЁё]') {
      $chosen = $candidate
      break
    }
  }
  if ($null -eq $chosen) { return $null }

  $es = $clean.Substring(0, $chosen.Index).Trim()
  $ru = $clean.Substring($chosen.Index + $chosen.Length).Trim()

  if ($es.Contains('?')) {
    $questionEnd = $es.IndexOf('?')
    if ($questionEnd -ge 0 -and $questionEnd -lt $es.Length - 1) {
      $es = $es.Substring(0, $questionEnd + 1).Trim()
    }
  }

  if ($es -notmatch '[A-Za-zÁÉÍÓÚÜÑáéíóúüñ¿¡]') { return $null }
  if ($ru -notmatch '[А-Яа-яЁё]') { return $null }

  return [pscustomobject]@{
    Es = $es
    Ru = $ru
  }
}

function SplitRow([string]$line) {
  $text = $line.Trim()
  if ($text.StartsWith('|')) { $text = $text.Substring(1) }
  if ($text.EndsWith('|')) { $text = $text.Substring(0, $text.Length - 1) }
  $parts = $text.Split('|')
  $trimmed = New-Object string[] $parts.Length
  for ($i = 0; $i -lt $parts.Length; $i++) { $trimmed[$i] = $parts[$i].Trim() }
  return $trimmed
}

function FindHeadingIndex([string[]]$lines, [string]$heading) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ((Clean $lines[$i]) -eq $heading) { return $i }
  }
  return -1
}

function GetSectionLines([string[]]$lines, [string]$heading) {
  $start = FindHeadingIndex $lines $heading
  if ($start -lt 0) { return @() }
  $end = $lines.Count
  for ($i = $start + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^#') { $end = $i; break }
  }
  return $lines[($start + 1)..($end - 1)]
}

function GetTableBlocks([string[]]$sectionLines) {
  $blocks = @()
  $i = 0
  while ($i -lt $sectionLines.Count) {
    if (-not $sectionLines[$i].Contains('|')) { $i++; continue }
    $align = -1
    for ($look = 1; $look -le 6; $look++) {
      if ($i + $look -ge $sectionLines.Count) { break }
      if ($sectionLines[$i + $look] -match '^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$') { $align = $i + $look; break }
      if (-not $sectionLines[$i + $look].Contains('|')) { break }
    }
    if ($align -lt 0) { $i++; continue }
    $header = $sectionLines[$i..($align - 1)]
    $rows = @()
    $j = $align + 1
    while ($j -lt $sectionLines.Count) {
      $line = $sectionLines[$j]
      if ($line.Trim() -eq '' -or ($line -match '^#')) { break }
      if (-not $line.Contains('|')) { break }
      $rows += $line
      $j++
    }
    $blocks += [pscustomobject]@{
      Header = $header
      Rows   = $rows
      Title  = Clean (($header -join ' '))
    }
    $i = $j
  }
  return $blocks
}

function NewEntryBucket() {
  return [ordered]@{}
}

$Buckets = [ordered]@{
  'Глаголы' = [ordered]@{
    'Глаголы все' = (NewEntryBucket)
    'Прошлое законченное время (preterito perfecto simple)' = (NewEntryBucket)
  }
  'Местоимения и притяжательные' = [ordered]@{
    'меня тебя' = (NewEntryBucket)
  }
  'Состояния и потребности (estar/tener)' = [ordered]@{
    'Estar + прилагательное / состояние' = (NewEntryBucket)
    'Tener + существительное / ощущение' = (NewEntryBucket)
  }
  'Предлоги' = [ordered]@{
    'Предлоги' = (NewEntryBucket)
  }
  'Предлоги места' = [ordered]@{
    'Предлоги места' = (NewEntryBucket)
  }
  'Союзы' = [ordered]@{
    'Союзы' = (NewEntryBucket)
  }
  'Вопросительные слова' = [ordered]@{
    'Вопросительные слова' = (NewEntryBucket)
  }
  'Указательные и место/направление' = [ordered]@{
    'Указательные местоимения' = (NewEntryBucket)
    'Наречия места' = (NewEntryBucket)
  }
  'Наречия и частотность' = [ordered]@{
    'Частотность' = (NewEntryBucket)
  }
  'Числительные' = [ordered]@{
    'Порядковые' = (NewEntryBucket)
    'Количественные' = (NewEntryBucket)
  }
  'Время и даты' = [ordered]@{
    'Месяцы и дни недели' = (NewEntryBucket)
    'Фразы про время и даты' = (NewEntryBucket)
  }
  'Погода' = [ordered]@{
    'Hace' = (NewEntryBucket)
    'Está' = (NewEntryBucket)
    'Hay' = (NewEntryBucket)
    'Осадки и явления' = (NewEntryBucket)
    'Времена года' = (NewEntryBucket)
  }
  'Дом: комнаты и мебель' = [ordered]@{
    'Комнаты' = (NewEntryBucket)
    'Мебель и предметы' = (NewEntryBucket)
  }
  'Цвета' = [ordered]@{
    'Цвета' = (NewEntryBucket)
  }
  'Природа' = [ordered]@{
    'Природа' = (NewEntryBucket)
  }
  'Фразы (разговорное / кафе / быт)' = [ordered]@{
    'Фразы' = (NewEntryBucket)
  }
}

$Grammar = [ordered]@{
  'Presente: regular' = @()
  'Presente: cambios' = @()
  'Presente: ejemplos' = @()
  'Ser / llamarse / posesivos' = @()
  'Pretérito perfecto: haber' = @()
  'Pretérito perfecto: participios' = @()
  'Gerundio' = @()
  'Imperfecto: регулярные формы' = @()
  'Imperfecto: ser / ir / ver' = @()
  'Futuro simple: regular' = @()
  'Futuro simple: irregulares' = @()
  'Pretérito perfecto simple: маркеры' = @()
  'Pretérito perfecto simple: regular' = @()
  'Pretérito perfecto simple: irregulares' = @()
  'Resumen de tiempos' = @()
  'Artículos' = @()
  'Género: reglas' = @()
  'Muy / Mucho' = @()
}

function AddEntry(
  [string]$section,
  [string]$subsection,
  [string]$es,
  [string]$ru,
  [string]$accentMode = 'accent'
) {
  if (-not $Buckets.Contains($section)) { return }
  if (-not $Buckets[$section].Contains($subsection)) { return }
  $esClean = FormatEs $es $accentMode
  $ruClean = CleanRu $ru
  if ($esClean -eq '' -or $ruClean -eq '') { return }
  if ($esClean -match '\[[^\]]+\]') { return }
  if ($esClean -match '[А-Яа-яЁё]' -or $ruClean -notmatch '[А-Яа-яЁё]') { return }
  if ($esClean.Contains('|') -or $ruClean.Contains('|')) { return }
  if ($esClean.Length -eq 1 -and $ruClean.Length -eq 1) { return }
  $bucket = $Buckets[$section][$subsection]
  $key = NormalizeKey $esClean
  if (-not $bucket.Contains($key)) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    $null = $set.Add($ruClean)
    $bucket[$key] = [pscustomobject]@{ Es = $esClean; Rus = $set }
    return
  }
  $null = $bucket[$key].Rus.Add($ruClean)
}

function AddGrammarRow([string]$name, [string[]]$cells) {
  $Grammar[$name] += ,$cells
}

function RemoveEntry([string]$section, [string]$subsection, [string]$es, [string]$mode = 'preserve') {
  if (-not $Buckets.Contains($section)) { return }
  if (-not $Buckets[$section].Contains($subsection)) { return }
  $key = NormalizeKey (FormatEs $es $mode)
  $Buckets[$section][$subsection].Remove($key) | Out-Null
}

function AddDictionaryFromTwoColTable([string]$section, [string]$subsection, [object]$table, [string]$accentMode = 'accent', [string[]]$allowEs = @(), [string[]]$denyEs = @()) {
  foreach ($row in $table.Rows) {
    $cells = SplitRow $row
    if ($cells.Length -lt 2) { continue }
    $es = Clean $cells[0]
    $ru = CleanRu $cells[1]
    if ($allowEs.Count -gt 0 -and ($allowEs -notcontains $es)) { continue }
    if ($denyEs -contains $es) { continue }
    AddEntry $section $subsection $es $ru $accentMode
  }
}

if (-not (Test-Path $RawPath)) { throw "Not found: $RawPath" }

$raw = Get-Content -Raw -Encoding utf8 $RawPath
$lines = $raw -split "\r?\n"

# Глаголы
$verbsSection = GetSectionLines $lines '## Глаголы все'
$verbTables = GetTableBlocks $verbsSection
if ($verbTables.Count -gt 0) {
  AddDictionaryFromTwoColTable 'Глаголы' 'Глаголы все' $verbTables[0] 'accent'
}
RemoveEntry 'Глаголы' 'Глаголы все' 'conducir' 'accent'
AddEntry 'Глаголы' 'Глаголы все' 'conducír' 'водить транспорт' 'accent'
RemoveEntry 'Глаголы' 'Глаголы все' 'manejar' 'accent'
AddEntry 'Глаголы' 'Глаголы все' 'manejár' 'водить транспорт' 'accent'
RemoveEntry 'Глаголы' 'Глаголы все' 'conocer' 'accent'
AddEntry 'Глаголы' 'Глаголы все' 'conocér' 'быть знакомым; знать лично' 'accent'
RemoveEntry 'Глаголы' 'Глаголы все' 'ducharse' 'accent'
AddEntry 'Глаголы' 'Глаголы все' 'duchárse' 'мыться / принимать душ' 'accent'
RemoveEntry 'Глаголы' 'Глаголы все' 'montar' 'accent'
AddEntry 'Глаголы' 'Глаголы все' 'montár' 'ездить на чём-то / садиться верхом' 'accent'
RemoveEntry 'Глаголы' 'Глаголы все' 'ir' 'accent'
AddEntry 'Глаголы' 'Глаголы все' 'ir' 'идти / ехать (не к говорящему)' 'accent'
RemoveEntry 'Глаголы' 'Глаголы все' 'venir' 'accent'
AddEntry 'Глаголы' 'Глаголы все' 'venír' 'приходить / приезжать (к говорящему)' 'accent'
RemoveEntry 'Глаголы' 'Глаголы все' 'llevar' 'accent'
AddEntry 'Глаголы' 'Глаголы все' 'llevár' 'относить / нести' 'accent'

# Presente
foreach ($row in @(
  @('yo', '-o', '-o', '-o'),
  @('tú', '-as', '-es', '-es'),
  @('él / ella / usted', '-a', '-e', '-e'),
  @('nosotros/as', '-amos', '-emos', '-imos'),
  @('vosotros/as', '-áis', '-éis', '-ís'),
  @('ellos / ellas / ustedes', '-an', '-en', '-en')
)) {
  AddGrammarRow 'Presente: regular' $row
}
foreach ($row in @(
  @('e → ie', 'pensar', 'pienso, piensas, piensa, pensamos, pensáis, piensan'),
  @('o → ue', 'poder', 'puedo, puedes, puede, podemos, podéis, pueden'),
  @('e → i', 'pedir', 'pido, pides, pide, pedimos, pedís, piden'),
  @('cer / cir → zco', 'conocer', 'conozco'),
  @('-uir → uyo', 'construir', 'construyo, construyes, construye, construimos, construís, construyen')
)) {
  AddGrammarRow 'Presente: cambios' @($row[0], (FormatEs $row[1] 'accent'), (FormatEs $row[2] 'accent'))
}
foreach ($row in @(
  @('yo', 'hablo', 'como', 'vivo', 'me levanto', 'voy'),
  @('tú', 'hablas', 'comes', 'vives', 'te levantas', 'vas'),
  @('él / ella / usted', 'habla', 'come', 'vive', 'se levanta', 'va'),
  @('nosotros/as', 'hablamos', 'comemos', 'vivimos', 'nos levantamos', 'vamos'),
  @('vosotros/as', 'habláis', 'coméis', 'vivís', 'os levantáis', 'vais'),
  @('ellos / ellas / ustedes', 'hablan', 'comen', 'viven', 'se levantan', 'van')
)) {
  AddGrammarRow 'Presente: ejemplos' @(
    $row[0],
    (FormatEs $row[1] 'accent'),
    (FormatEs $row[2] 'accent'),
    (FormatEs $row[3] 'accent'),
    (FormatEs $row[4] 'accent'),
    (FormatEs $row[5] 'accent')
  )
}
foreach ($row in @(
  @('yo', 'soy', 'me llamo', 'mi / mis', 'mío / míos'),
  @('tú', 'eres', 'te llamas', 'tu / tus', 'tuyo / tuyos'),
  @('él / ella / usted', 'es', 'se llama', 'su / sus', 'suyo / suyos'),
  @('nosotros/as', 'somos', 'nos llamamos', 'nuestro / nuestros', 'nuestro / nuestros'),
  @('vosotros/as', 'sois', 'os llamáis', 'vuestro / vuestros', 'vuestro / vuestros'),
  @('ellos / ellas / ustedes', 'son', 'se llaman', 'su / sus', 'suyo / suyos')
)) {
  AddGrammarRow 'Ser / llamarse / posesivos' $row
}

$perfectSimpleSection = GetSectionLines $lines '## Прошлое законченное время (preterito perfecto simple)'
$perfectTables = GetTableBlocks $perfectSimpleSection
if ($perfectTables.Count -gt 0) {
  AddDictionaryFromTwoColTable 'Глаголы' 'Прошлое законченное время (preterito perfecto simple)' $perfectTables[0] 'accent'
}

# Местоимения
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'a mí' 'мне' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'a ti' 'тебе' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'a él / ella / usted' 'ему' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'a nosotros' 'нам' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'a vosotros' 'вам (неформ.)' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'a ellos / ellas / ustedes' 'им' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'me' 'мне; меня' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'te' 'тебе; тебя' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'le' 'ему' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'nos' 'нам; нас' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'os' 'вам (неформ.); вас (неформ.)' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'les' 'им' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'lo / la' 'его / её / это' 'preserve'
AddEntry 'Местоимения и притяжательные' 'меня тебя' 'los / las' 'их' 'preserve'

# Estar / tener
$statesSection = GetSectionLines $lines '## Estar tener'
$stateTables = GetTableBlocks $statesSection
if ($stateTables.Count -ge 2) {
  foreach ($row in $stateTables[1].Rows) {
    $cells = SplitRow $row
    if ($cells.Length -ge 4) {
      $estarWord = Clean $cells[0]
      $tenerWord = Clean $cells[2]
      if ($estarWord -ne '') {
        $estarRu = CleanRu $cells[1]
        switch ($estarWord.ToLowerInvariant()) {
          'sentada' { $estarWord = 'sentado'; $estarRu = 'сидя / сидящий' }
          'sucios'  { $estarWord = 'sucio' }
          'contento' { $estarRu = 'доволен / рад' }
          'enfermo' { $estarRu = 'болен' }
          'sentado' { $estarRu = 'сидя / сидящий' }
          'soltero' { $estarRu = 'холостой / не женат' }
        }
        AddEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' ("estar $estarWord") $estarRu 'accent'
      }
      if ($tenerWord -ne '') {
        $tenerRu = CleanRu $cells[3]
        switch ($tenerWord.ToLowerInvariant()) {
          'caliente' {
            AddEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' 'estar caliente' 'горячий / тёплый' 'accent'
          }
          'calor' { AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' ("tener $tenerWord") 'мне жарко' 'accent' }
          'frio' { AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' ("tener $tenerWord") 'мне холодно' 'accent' }
          'hambre' { AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' ("tener $tenerWord") 'голод / хочу есть' 'accent' }
          'sed' { AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' ("tener $tenerWord") 'жажда / хочу пить' 'accent' }
          'sueño' { AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' ("tener $tenerWord") 'сонно / хочется спать' 'accent' }
          'miedo' { AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' ("tener $tenerWord") 'страх / боюсь' 'accent' }
          'prisa' { AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' ("tener $tenerWord") 'спешка / я спешу' 'accent' }
          default { AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' ("tener $tenerWord") $tenerRu 'accent' }
        }
      }
    }
  }
}
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'estoy un poco cansado' 'немного устал' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'tengo mucho trabajo' 'много работы' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'muchísimo' 'очень много' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'no tengo hambre ni sed' 'не хочу ни есть, ни пить' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿De dónde eres?' 'откуда ты?' 'preserve'

# Косметическая чистка состояний
RemoveEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' 'estar aburrido' 'accent'
AddEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' 'estár aburrído' 'мне скучно / скучающий' 'accent'
RemoveEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' 'estar cansado' 'accent'
AddEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' 'estár cansádo' 'уставший' 'accent'
RemoveEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' 'estar caliente' 'accent'
AddEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' 'estár caliénte' 'горячий / тёплый' 'accent'
RemoveEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' 'estar enfermo' 'accent'
AddEntry 'Состояния и потребности (estar/tener)' 'Estar + прилагательное / состояние' 'estár enférmo' 'больной / болен' 'accent'
RemoveEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tener hambre' 'accent'
AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tenér hámbre' 'быть голодным / хотеть есть' 'accent'
RemoveEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tener miedo' 'accent'
AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tenér miédo' 'бояться / испытывать страх' 'accent'
RemoveEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tener prisa' 'accent'
AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tenér prísa' 'торопиться / спешить' 'accent'
RemoveEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tener sed' 'accent'
AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tenér sed' 'хотеть пить' 'accent'
RemoveEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tener sueño' 'accent'
AddEntry 'Состояния и потребности (estar/tener)' 'Tener + существительное / ощущение' 'tenér suéño' 'хотеть спать / быть сонным' 'accent'

# Грамматические таблицы
$ppSection = GetSectionLines $lines '## Прошедшее законченное время (pretérito perfecto)'
$ppTables = GetTableBlocks $ppSection
if ($ppTables.Count -ge 1) {
  for ($i = 0; $i -lt [Math]::Min($ConjugationPronouns.Count, $ppTables[0].Rows.Count); $i++) {
    $cells = SplitRow $ppTables[0].Rows[$i]
    if ($cells.Length -ge 2) {
      AddGrammarRow 'Pretérito perfecto: haber' @($ConjugationPronouns[$i], (FormatEs $cells[1] 'accent'))
    }
  }
}
if ($ppTables.Count -ge 2) {
  foreach ($row in $ppTables[1].Rows) {
    $cells = SplitRow $row
    if ($cells.Length -ge 2 -and (Clean $cells[0]) -ne '' -and (Clean $cells[1]) -ne '') {
      AddGrammarRow 'Pretérito perfecto: participios' @((FormatEs $cells[0] 'accent'), (FormatEs $cells[1] 'accent'), '')
    }
    if ($cells.Length -ge 4 -and (Clean $cells[2]) -ne '' -and (Clean $cells[3]) -ne '') {
      $translation2 = if ($cells.Length -ge 5) { CleanRu $cells[4] } else { '' }
      AddGrammarRow 'Pretérito perfecto: participios' @((FormatEs $cells[2] 'accent'), (FormatEs $cells[3] 'accent'), $translation2)
    }
  }
}

$gerundSection = GetSectionLines $lines '## Герундий'
foreach ($pair in @(
  @('hablar','hablando'),
  @('comer','comiendo'),
  @('escribir','escribiendo'),
  @('leer','leyendo'),
  @('pedir','pidiendo'),
  @('dormir','durmiendo'),
  @('ir','yendo'),
  @('poder','pudiendo'),
  @('sonreír','sonriendo')
)) {
  AddGrammarRow 'Gerundio' @((FormatEs $pair[0] 'accent'), (FormatEs $pair[1] 'accent'))
}

$impSection = GetSectionLines $lines '## Прошедшее просто (inperfecto )'
$impTables = GetTableBlocks $impSection
if ($impTables.Count -ge 1) {
  foreach ($row in $impTables[0].Rows) {
    $cells = SplitRow $row
    if ($cells.Length -ge 4) {
      AddGrammarRow 'Imperfecto: регулярные формы' @((Clean $cells[0]), (FormatEs $cells[1] 'accent'), (Clean $cells[2]), (FormatEs $cells[3] 'accent'))
    }
  }
}
if ($impTables.Count -ge 2) {
  for ($i = 0; $i -lt [Math]::Min($ConjugationPronouns.Count, $impTables[1].Rows.Count); $i++) {
    $cells = SplitRow $impTables[1].Rows[$i]
    if ($cells.Length -ge 4) {
      AddGrammarRow 'Imperfecto: ser / ir / ver' @($ConjugationPronouns[$i], (FormatEs $cells[1] 'accent'), (FormatEs $cells[2] 'accent'), (FormatEs $cells[3] 'accent'))
    }
  }
}

# Futuro simple
foreach ($row in @(
  @('yo', '-é', 'comeré'),
  @('tú', '-ás', 'comerás'),
  @('él / ella / usted', '-á', 'comerá'),
  @('nosotros/as', '-emos', 'comeremos'),
  @('vosotros/as', '-éis', 'comeréis'),
  @('ellos / ellas / ustedes', '-án', 'comerán')
)) {
  AddGrammarRow 'Futuro simple: regular' @($row[0], $row[1], (FormatEs $row[2] 'accent'))
}
foreach ($row in @(
  @('decir', 'dir', 'сказать'),
  @('caber', 'cabr', 'помещаться'),
  @('haber', 'habr', 'быть / иметься'),
  @('hacer', 'har', 'делать'),
  @('poner', 'pondr', 'класть'),
  @('poder', 'podr', 'мочь'),
  @('querer', 'querr', 'хотеть'),
  @('saber', 'sabr', 'знать'),
  @('salir', 'saldr', 'выходить'),
  @('tener', 'tendr', 'иметь'),
  @('valer', 'valdr', 'стоить'),
  @('venir', 'vendr', 'приходить')
)) {
  AddGrammarRow 'Futuro simple: irregulares' @((FormatEs $row[0] 'accent'), $row[1], $row[2])
}

# Pretérito perfecto simple
foreach ($row in @(
  @('ayer', 'вчера'),
  @('anteayer', 'позавчера'),
  @('la semana / mes / año pasada', 'на прошлой неделе / в прошлом месяце / году'),
  @('hace dos días / años', 'два дня / года назад'),
  @('en 1990 / en mayo', 'в 1990-м / в мае'),
  @('entonces', 'тогда'),
  @('de repente', 'вдруг'),
  @('una vez', 'однажды'),
  @('aquel día', 'в тот день')
)) {
  AddGrammarRow 'Pretérito perfecto simple: маркеры' @((FormatEs $row[0] 'accent'), $row[1])
}
foreach ($row in @(
  @('-é', 'hablé', '-í', 'comí / viví'),
  @('-aste', 'hablaste', '-iste', 'comiste / viviste'),
  @('-ó', 'habló', '-ió', 'comió / vivió'),
  @('-amos', 'hablamos', '-imos', 'comimos / vivimos'),
  @('-asteis', 'hablasteis', '-isteis', 'comisteis / vivisteis'),
  @('-aron', 'hablaron', '-ieron', 'comieron / vivieron')
)) {
  AddGrammarRow 'Pretérito perfecto simple: regular' @($row[0], (FormatEs $row[1] 'accent'), $row[2], (FormatEs $row[3] 'accent'))
}
foreach ($row in @(
  @('yo', 'fui', 'di', 'dije', 'estuve', 'hice', 'pude', 'puse', 'quise', 'supe', 'tuve', 'traje', 'vine'),
  @('tú', 'fuiste', 'diste', 'dijiste', 'estuviste', 'hiciste', 'pudiste', 'pusiste', 'quisiste', 'supiste', 'tuviste', 'trajiste', 'viniste'),
  @('él / ella / usted', 'fue', 'dio', 'dijo', 'estuvo', 'hizo', 'pudo', 'puso', 'quiso', 'supo', 'tuvo', 'trajo', 'vino'),
  @('nosotros/as', 'fuimos', 'dimos', 'dijimos', 'estuvimos', 'hicimos', 'pudimos', 'pusimos', 'quisimos', 'supimos', 'tuvimos', 'trajimos', 'vinimos'),
  @('vosotros/as', 'fuisteis', 'disteis', 'dijisteis', 'estuvisteis', 'hicisteis', 'pudisteis', 'pusisteis', 'quisisteis', 'supisteis', 'tuvisteis', 'trajisteis', 'vinisteis'),
  @('ellos / ellas / ustedes', 'fueron', 'dieron', 'dijeron', 'estuvieron', 'hicieron', 'pudieron', 'pusieron', 'quisieron', 'supieron', 'tuvieron', 'trajeron', 'vinieron')
)) {
  AddGrammarRow 'Pretérito perfecto simple: irregulares' @(
    $row[0],
    (FormatEs $row[1] 'accent'),
    (FormatEs $row[2] 'accent'),
    (FormatEs $row[3] 'accent'),
    (FormatEs $row[4] 'accent'),
    (FormatEs $row[5] 'accent'),
    (FormatEs $row[6] 'accent'),
    (FormatEs $row[7] 'accent'),
    (FormatEs $row[8] 'accent'),
    (FormatEs $row[9] 'accent'),
    (FormatEs $row[10] 'accent'),
    (FormatEs $row[11] 'accent'),
    (FormatEs $row[12] 'accent')
  )
}

# Все времена
foreach ($row in @(
  @('yo', 'me', '-o', '-o', '-o', 'he', '-aba', '-ía', '-é', '-í', '-é'),
  @('tú', 'te', '-as', '-es', '-es', 'has', '-abas', '-ías', '-aste', '-iste', '-ás'),
  @('él / ella', 'se', '-a', '-e', '-e', 'ha', '-aba', '-ía', '-ó', '-ió', '-á'),
  @('nosotros/as', 'nos', '-amos', '-emos', '-imos', 'hemos', '-ábamos', '-íamos', '-amos', '-imos', '-emos'),
  @('vosotros/as', 'os', '-áis', '-éis', '-ís', 'habéis', '-abais', '-íais', '-asteis', '-isteis', '-éis'),
  @('ellos / ellas', 'se', '-an', '-en', '-en', 'han', '-aban', '-ían', '-aron', '-ieron', '-án')
)) {
  AddGrammarRow 'Resumen de tiempos' $row
}

# Предлоги / союзы / вопросительные / наречия
$prepSection = GetSectionLines $lines '# Предлоги'
$prepTables = GetTableBlocks $prepSection
if ($prepTables.Count -ge 1) {
  $allowedPreps = @('a','con','de','desde','en','entre','hacia','hasta','para','por','sin','sobre','tras')
  AddDictionaryFromTwoColTable 'Предлоги' 'Предлоги' $prepTables[0] 'preserve' $allowedPreps
}
if ($prepTables.Count -ge 2) {
  AddDictionaryFromTwoColTable 'Союзы' 'Союзы' $prepTables[1] 'preserve'
}

$questionSection = GetSectionLines $lines '## вопросительные слова'
$questionTables = GetTableBlocks $questionSection
if ($questionTables.Count -ge 1) {
  AddDictionaryFromTwoColTable 'Вопросительные слова' 'Вопросительные слова' $questionTables[0] 'preserve' $QuestionWordAllow
}
if ($questionTables.Count -ge 2) {
  $rows = $questionTables[1].Rows
  if ($rows.Count -ge 3) {
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'este' 'этот' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'esta' 'эта' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'estos' 'эти' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'estas' 'эти' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'esto' 'это' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'ese' 'тот' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'esa' 'та' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'esos' 'те' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'esas' 'те' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'eso' 'то' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'aquel' 'вон тот' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'aquella' 'вон та' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'aquellos' 'вон те' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'aquellas' 'вон те' 'preserve'
    AddEntry 'Указательные и место/направление' 'Указательные местоимения' 'aquello' 'вон то' 'preserve'
  }
}
if ($questionTables.Count -ge 3) {
  AddEntry 'Указательные и место/направление' 'Наречия места' 'aquí' 'здесь' 'preserve'
  AddEntry 'Указательные и место/направление' 'Наречия места' 'acá' 'сюда' 'preserve'
  AddEntry 'Указательные и место/направление' 'Наречия места' 'ahí' 'там (рядом с собеседником)' 'preserve'
  AddEntry 'Указательные и место/направление' 'Наречия места' 'allí' 'там (далеко)' 'preserve'
  AddEntry 'Указательные и место/направление' 'Наречия места' 'allá' 'туда (далеко)' 'preserve'
}
AddEntry 'Наречия и частотность' 'Частотность' 'nunca / casi nunca' 'никогда' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'rara vez / raramente' 'редко' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'a veces' 'иногда' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'normalmente' 'обычно' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'a menudo / con frecuencia' 'часто' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'siempre' 'всегда' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'todos los dias' 'каждый день' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'todas las semanas' 'каждую неделю' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'todos los fines de semana' 'каждые выходные' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'una vez a la semana' 'раз в неделю' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'dos veces al dia / al mes / al ano' 'два раза в день / месяц / год' 'accent'
AddEntry 'Наречия и частотность' 'Частотность' 'varios / varias' 'несколько' 'accent'

# Muy / Mucho
foreach ($row in @(
  @('muy + прилагательное', 'muy rico', 'очень вкусный'),
  @('muy + наречие', 'muy bien', 'очень хорошо'),
  @('mucho + глагол', 'no como mucho', 'я не ем много'),
  @('mucho + существительное', 'muchas manzanas', 'много яблок'),
  @('comparativos', 'mayor, menor, mejor, peor', 'больший, меньший, лучше, хуже'),
  @('otros', 'más, menos, antes, después', 'больше, меньше, раньше, после')
)) {
  AddGrammarRow 'Muy / Mucho' @($row[0], (FormatEs $row[1] 'accent'), $row[2])
}

# Предлоги места
$placeSection = GetSectionLines $lines '## Предлоги места'
$placeTables = GetTableBlocks $placeSection
if ($placeTables.Count -gt 0) {
  AddDictionaryFromTwoColTable 'Предлоги места' 'Предлоги места' $placeTables[0] 'preserve'
}

# Артикли и род
foreach ($row in @(
  @('неопределённый, ед. ч.', 'un', 'una'),
  @('неопределённый, мн. ч.', 'unos', 'unas'),
  @('определённый, ед. ч.', 'el', 'la'),
  @('определённый, мн. ч.', 'los', 'las')
)) {
  AddGrammarRow 'Artículos' $row
}
foreach ($row in @(
  @('-o', 'обычно мужской род', '-a', 'обычно женский род'),
  @('-ma / -ta', 'часто мужской род', '-dad', 'часто женский род'),
  @('', '', '-ción / -sión', 'обычно женский род'),
  @('ingeniero', 'la ingeniera', 'profesor', 'la profesora'),
  @('-e / -ista', 'род часто меняется только артиклем', 'a + el', 'al')
)) {
  AddGrammarRow 'Género: reglas' $row
}

# Числительные
foreach ($row in @(
  @('primero', 'первый'),
  @('segundo', 'второй'),
  @('tercero', 'третий'),
  @('cuarto', 'четвёртый'),
  @('quinto', 'пятый'),
  @('sexto', 'шестой'),
  @('séptimo', 'седьмой'),
  @('octavo', 'восьмой'),
  @('noveno', 'девятый'),
  @('décimo', 'десятый')
)) {
  AddEntry 'Числительные' 'Порядковые' $row[0] $row[1] 'accent'
}
foreach ($row in @(
  @('cero', 'ноль'),
  @('uno', 'один'),
  @('dos', 'два'),
  @('tres', 'три'),
  @('cuatro', 'четыре'),
  @('cinco', 'пять'),
  @('seis', 'шесть'),
  @('siete', 'семь'),
  @('ocho', 'восемь'),
  @('nueve', 'девять'),
  @('diez', 'десять'),
  @('once', 'одиннадцать'),
  @('doce', 'двенадцать'),
  @('trece', 'тринадцать'),
  @('catorce', 'четырнадцать'),
  @('quince', 'пятнадцать'),
  @('dieciséis', 'шестнадцать'),
  @('diecisiete', 'семнадцать'),
  @('dieciocho', 'восемнадцать'),
  @('diecinueve', 'девятнадцать'),
  @('veinte', 'двадцать'),
  @('veintiuno', 'двадцать один'),
  @('veintidós', 'двадцать два'),
  @('veintitrés', 'двадцать три'),
  @('veinticuatro', 'двадцать четыре'),
  @('veinticinco', 'двадцать пять'),
  @('veintiséis', 'двадцать шесть'),
  @('veintisiete', 'двадцать семь'),
  @('veintiocho', 'двадцать восемь'),
  @('veintinueve', 'двадцать девять'),
  @('treinta', 'тридцать'),
  @('treinta y uno', 'тридцать один'),
  @('cuarenta', 'сорок'),
  @('cincuenta', 'пятьдесят'),
  @('sesenta', 'шестьдесят'),
  @('setenta', 'семьдесят'),
  @('ochenta', 'восемьдесят'),
  @('noventa', 'девяносто'),
  @('cien', 'сто'),
  @('ciento uno', 'сто один'),
  @('doscientos', 'двести'),
  @('trescientos', 'триста'),
  @('cuatrocientos', 'четыреста'),
  @('quinientos', 'пятьсот'),
  @('seiscientos', 'шестьсот'),
  @('setecientos', 'семьсот'),
  @('ochocientos', 'восемьсот'),
  @('novecientos', 'девятьсот'),
  @('mil', 'тысяча')
)) {
  AddEntry 'Числительные' 'Количественные' $row[0] $row[1] 'accent'
}

# Время и даты
$timeSection = GetSectionLines $lines '## Месяцы, дни недели'
$timeTables = GetTableBlocks $timeSection
if ($timeTables.Count -gt 0) {
  foreach ($row in $timeTables[0].Rows) {
    $cells = SplitRow $row
    if ($cells.Length -ge 4) {
      AddEntry 'Время и даты' 'Месяцы и дни недели' $cells[0] $cells[1] 'accent'
      if ((Clean $cells[3]) -ne '') { AddEntry 'Время и даты' 'Месяцы и дни недели' $cells[3] $cells[2] 'accent' }
    }
  }
}
foreach ($line in $timeSection) {
  $pair = TryParseInlinePair $line
  if ($null -ne $pair) {
    $es = $pair.Es
    $ru = $pair.Ru
    $timeKey = NormalizeKey $es
    if ($timeKey -eq '¿cuándo es tu cumpleaños?') {
      $ru = 'когда день рождения?'
    } elseif ($timeKey -eq 'a (que día)/cuantos estamos?') {
      $es = '¿A cuántos estamos?'
      $ru = 'какое сегодня число?'
    } elseif ($timeKey -eq 'a que hora') {
      $es = '¿A qué hora?'
      $ru = 'во сколько?'
    } elseif ($timeKey -eq 'cual es tu fecha de nacimiento?') {
      $es = '¿Cuál es tu fecha de nacimiento?'
      $ru = 'дата рождения'
    } elseif ($timeKey -eq 'hoy es martes\30 de junio…') {
      $es = 'Hoy es martes / 30 de junio'
      $ru = 'сегодня вторник / 30 июня'
    } elseif ($timeKey -eq 'en que mes estamos?') {
      $es = '¿En qué mes estamos?'
      $ru = 'какой сейчас месяц?'
    } elseif ($timeKey -eq 'hoy es miércoles') {
      $ru = 'сегодня среда'
    } elseif ($timeKey -eq 'la lunes que viene') {
      $es = 'el lunes que viene'
      $ru = 'в следующий понедельник'
    } elseif ($timeKey -eq 'la semana que viene') {
      $ru = 'следующая неделя'
    } elseif ($timeKey -eq 'que hora es?') {
      $es = '¿Qué hora es?'
      $ru = 'сколько времени?'
    } elseif ($timeKey -eq 'de la manana \ de la tarde (12-20) \ de la noche (20-1)') {
      $ru = 'утра / дня / ночи'
    }
    AddEntry 'Время и даты' 'Фразы про время и даты' $es $ru 'accent'
  }
}

# Косметическая чистка времени
RemoveEntry 'Время и даты' 'Фразы про время и даты' '¿Cuál es tu fecha de nacimiento?' 'accent'
AddEntry 'Время и даты' 'Фразы про время и даты' '¿Cuál es tu fécha de nacimiénto?' 'какая у тебя дата рождения?' 'accent'
RemoveEntry 'Время и даты' 'Фразы про время и даты' '¿Cuándo es tu cumpleaños?' 'accent'
AddEntry 'Время и даты' 'Фразы про время и даты' '¿Cuándo es tu cumpleáños?' 'когда у тебя день рождения?' 'accent'
RemoveEntry 'Время и даты' 'Фразы про время и даты' 'en punto' 'accent'
AddEntry 'Время и даты' 'Фразы про время и даты' 'en púnto' 'ровно' 'accent'
RemoveEntry 'Время и даты' 'Фразы про время и даты' 'y cuarto' 'accent'
AddEntry 'Время и даты' 'Фразы про время и даты' 'y cuárto' 'четверть' 'accent'
RemoveEntry 'Время и даты' 'Фразы про время и даты' 'y media' 'accent'
AddEntry 'Время и даты' 'Фразы про время и даты' 'y média' 'половина часа' 'accent'

# Погода
$weatherSection = GetSectionLines $lines '## Погода'
$weatherTables = GetTableBlocks $weatherSection
if ($weatherTables.Count -gt 0) {
  foreach ($row in $weatherTables[0].Rows) {
    $cells = SplitRow $row
    if ($cells.Length -ge 7) {
      if ((Clean $cells[0]) -match '^(?<es>.+?)\s*-\s*(?<ru>.+)$') { AddEntry 'Погода' 'Hace' $Matches['es'] $Matches['ru'] 'accent' }
      if ((Clean $cells[1]) -ne '' -and (CleanRu $cells[2]) -ne '') { AddEntry 'Погода' 'Está' $cells[1] $cells[2] 'accent' }
      if ((Clean $cells[3]) -ne '' -and (CleanRu $cells[4]) -ne '') { AddEntry 'Погода' 'Hay' $cells[3] $cells[4] 'accent' }
      if ((Clean $cells[5]) -match '^(?<es>.+?)\s*-\s*(?<ru>.+)$') {
        AddEntry 'Погода' 'Осадки и явления' $Matches['es'] $Matches['ru'] 'accent'
      } elseif ((Clean $cells[5]) -ne '' -and (CleanRu $cells[6]) -ne '') {
        AddEntry 'Погода' 'Осадки и явления' $cells[5] $cells[6] 'accent'
      }
      if ((Clean $cells[2]) -match '^(primavera|verano|otono|invierno)$' -and (CleanRu $cells[3]) -ne '') {
        AddEntry 'Погода' 'Времена года' $cells[2] $cells[3] 'accent'
      }
    }
  }
}
AddEntry 'Погода' 'Hace' 'buen tiempo' 'хорошая погода' 'accent'
AddEntry 'Погода' 'Hace' 'mal tiempo' 'плохая погода' 'accent'
AddEntry 'Погода' 'Hace' '¿Qué tiempo hace?' 'какая погода?' 'preserve'

# Дом и мебель
$homeSection = GetSectionLines $lines '## Комнаты и мебель'
$homeTables = GetTableBlocks $homeSection
if ($homeTables.Count -ge 1) {
  foreach ($row in $homeTables[0].Rows) {
    $cells = SplitRow $row
    if ($cells.Length -lt 2) { continue }
    $es = Clean $cells[0]
    $ru = CleanRu $cells[1]
    $roomKey = NormalizeKey $es
    if ($roomKey -eq 'el salon') {
      $ru = 'гостиная'
    } elseif ($roomKey -eq 'el pasillo') {
      $ru = 'коридор'
    }
    AddEntry 'Дом: комнаты и мебель' 'Комнаты' $es $ru 'accent'
  }
}
if ($homeTables.Count -ge 2) {
  foreach ($row in $homeTables[1].Rows) {
    $cells = SplitRow $row
    if ($cells.Length -lt 2) { continue }
    $es = ApplyEsFixes $cells[0]
    $esKey = $es.ToLowerInvariant()
    if ($FurnitureArticles.ContainsKey($esKey)) { $es = $FurnitureArticles[$esKey] }
    AddEntry 'Дом: комнаты и мебель' 'Мебель и предметы' $es $cells[1] 'accent'
  }
}

# Цвета
$colorsSection = GetSectionLines $lines '## Цвета'
foreach ($line in $colorsSection) {
  if (-not $line.Contains('|')) { continue }
  $cells = SplitRow $line
  if ($cells.Length -lt 3) { continue }
  if ($cells[0] -match '^-+$') { continue }
  $es = Clean $cells[0]
  $ru = CleanRu $cells[2]
  if ($es -eq '' -or $ru -eq '') { continue }
  AddEntry 'Цвета' 'Цвета' $es $ru 'accent'
}

# Природа
$natureSection = GetSectionLines $lines '## Природа'
$natureTables = GetTableBlocks $natureSection
if ($natureTables.Count -gt 0) {
  AddDictionaryFromTwoColTable 'Природа' 'Природа' $natureTables[0] 'accent'
}

# Фразы
$phrasesSection = GetSectionLines $lines '# Примеры слов'
$phraseWhitelist = @('muchísimo')
foreach ($line in $phrasesSection) {
  if ($line -match '!\[') { continue }
  $pair = TryParseInlinePair $line
  if ($null -eq $pair) { continue }
  $es = Clean $pair.Es
  $ru = CleanRu $pair.Ru
  $isPhrase = $es.Contains(' ') -or $es.Contains('\') -or $es.Contains('+') -or $es.Contains('?') -or $phraseWhitelist -contains $es.ToLowerInvariant()
  if (-not $isPhrase) { continue }
  AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' $es $ru 'accent'
}

RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'Cuánto es'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿Cuánto es?' 'сколько с меня?' 'preserve'

# Косметическая чистка фраз и явных дублей
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'hace viento' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿Cómo te llamas?' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿Cómo te llamas?' 'как тебя зовут?' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿Dónde vives?' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿Dónde vives?' 'где ты живёшь?' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿En qué ciudad vives?' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿En qué ciudad vives?' 'в каком городе ты живёшь?' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'a ver' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'a ver' 'дай подумать' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'acabar de' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'acabár de' 'только что' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'algo mas' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'álgo más' 'что-то ещё' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'asi que' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'ási que' 'так что' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'de acuerdo' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'de acuérdo' 'согласен / договорились' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'gato\gatita' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'gáto / gatíta' 'кот / котик' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'no (lo) se' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'no (lo) sé' 'я не знаю' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'no lo estoy ya' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'ya no lo estóy' 'я уже не такой / не в таком состоянии' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'No Me da pena' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'no me da péna' 'мне не жалко / не обидно' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'no sabemos si tienen casa o no' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'no sabémos si tiénen cása o no' 'не знаем, есть ли у них дом' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'oir oye' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'óir / óye' 'слышать / слушай' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'papa quien' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿Pára quién?' 'для кого?' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'para mi\el\ella' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'pára mí / él / élla' 'для меня / него / неё' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'pare comer\beber' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'pára comér / bebér' 'поесть / попить' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'que le\te pongo' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' '¿Qué le / te póngo?' 'что вам / тебе положить?' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'sentar \ sentarse' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'sentár / sentárse' 'сажать / садиться' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'sentir \ sentirse' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'sentír / sentírse' 'чувствовать / чувствовать себя' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'te echar de menos classes' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'echár de ménos' 'скучать по кому-то / чему-то' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'tengo que' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'téngo que' 'мне нужно / я должен' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'Tranquilo - tranquil' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'tranquílo' 'спокойно / не волнуйся' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'un dia laborable \ entre semana' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'un día laboráble / éntre semána' 'будний день / по будням' 'preserve'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'valer = costar' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'valér = costár' 'стоить (о цене)' 'accent'
RemoveEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'y tu también' 'accent'
AddEntry 'Фразы (разговорное / кафе / быт)' 'Фразы' 'y tú también' 'и ты тоже' 'preserve'

# Рендер
$out = New-Object System.Collections.Generic.List[string]
$out.Add('# vocabulary') | Out-Null
$out.Add('') | Out-Null
$out.Add('Автосборка из 1_vocabulary_raw.md с удалением дублей, мусора и битых строк. Учебные ударения через áéíóú добавляются только многосложным словам; служебные короткие формы сохраняются без искусственных акцентов.') | Out-Null
$out.Add('') | Out-Null

$renderedEs = New-Object 'System.Collections.Generic.HashSet[string]'

function RenderDictSection([string]$title, $subsections) {
  $out.Add("## $title") | Out-Null
  $out.Add('') | Out-Null
  foreach ($subName in $subsections.Keys) {
    $bucket = $subsections[$subName]
    if ($bucket.Count -eq 0) { continue }
    $out.Add("### $subName") | Out-Null
    $out.Add('') | Out-Null
    $out.Add('| Испанский | Перевод на русский |') | Out-Null
    $out.Add('| --- | --- |') | Out-Null
    $rows = $bucket.Values | Sort-Object { NormalizeKey $_.Es }
    foreach ($row in $rows) {
      $key = NormalizeKey $row.Es
      if ($renderedEs.Contains($key)) { continue }
      if (-not (Test-CanonicalDictionaryRow $row.Es)) { continue }
      $rus = ($row.Rus | Sort-Object { $_.ToLowerInvariant() } -Unique) -join '; '
      if ($rus -eq '') { continue }
      $out.Add("| $($row.Es) | $rus |") | Out-Null
      $null = $renderedEs.Add($key)
    }
    $out.Add('') | Out-Null
  }
}

RenderDictSection 'Глаголы' $Buckets['Глаголы']

$out.Add('## Грамматические таблицы') | Out-Null
$out.Add('') | Out-Null
$out.Add('### Presente') | Out-Null
$out.Add('') | Out-Null
$out.Add('| Лицо | -AR | -ER | -IR |') | Out-Null
$out.Add('| --- | --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Presente: regular']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('| Паттерн | Глагол | Пример форм |') | Out-Null
$out.Add('| --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Presente: cambios']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('| Лицо | hablar | comer | vivir | levantarse | ir |') | Out-Null
$out.Add('| --- | --- | --- | --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Presente: ejemplos']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) | $($row[4]) | $($row[5]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('| Лицо | ser | llamarse | Притяжат. перед сущ. | Притяжат. после сущ. |') | Out-Null
$out.Add('| --- | --- | --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Ser / llamarse / posesivos']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) | $($row[4]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('### Pretérito perfecto') | Out-Null
$out.Add('') | Out-Null
$out.Add('| Лицо | Haber |') | Out-Null
$out.Add('| --- | --- |') | Out-Null
foreach ($row in $Grammar['Pretérito perfecto: haber']) { $out.Add("| $($row[0]) | $($row[1]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('| Infinitivo | Participio | Перевод |') | Out-Null
$out.Add('| --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Pretérito perfecto: participios']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('### Gerundio') | Out-Null
$out.Add('') | Out-Null
$out.Add('| Infinitivo | Gerundio |') | Out-Null
$out.Add('| --- | --- |') | Out-Null
foreach ($row in $Grammar['Gerundio']) { $out.Add("| $($row[0]) | $($row[1]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('### Imperfecto') | Out-Null
$out.Add('') | Out-Null
$out.Add('| -AR | Ejemplo | -ER / -IR | Ejemplo |') | Out-Null
$out.Add('| --- | --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Imperfecto: регулярные формы']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('| Лицо | Ser | Ir | Ver |') | Out-Null
$out.Add('| --- | --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Imperfecto: ser / ir / ver']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('### Futuro simple') | Out-Null
$out.Add('') | Out-Null
$out.Add('| Лицо | Окончание | Ejemplo con comer |') | Out-Null
$out.Add('| --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Futuro simple: regular']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('| Infinitivo | Raíz irregular | Перевод |') | Out-Null
$out.Add('| --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Futuro simple: irregulares']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('### Pretérito perfecto simple') | Out-Null
$out.Add('') | Out-Null
$out.Add('| Маркер | Перевод |') | Out-Null
$out.Add('| --- | --- |') | Out-Null
foreach ($row in $Grammar['Pretérito perfecto simple: маркеры']) { $out.Add("| $($row[0]) | $($row[1]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('| -AR | Ejemplo | -ER / -IR | Ejemplo |') | Out-Null
$out.Add('| --- | --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Pretérito perfecto simple: regular']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('| Лицо | ser / ir | dar | decir | estar | hacer | poder | poner | querer | saber | tener | traer | venir |') | Out-Null
$out.Add('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Pretérito perfecto simple: irregulares']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) | $($row[4]) | $($row[5]) | $($row[6]) | $($row[7]) | $($row[8]) | $($row[9]) | $($row[10]) | $($row[11]) | $($row[12]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('### Все времена') | Out-Null
$out.Add('') | Out-Null
$out.Add('| Лицо | Возвр. местоимение | Presente -ar | Presente -er | Presente -ir | Pretérito perfecto | Imperfecto -ar | Imperfecto -er/-ir | Pretérito simple -ar | Pretérito simple -er/-ir | Futuro simple |') | Out-Null
$out.Add('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Resumen de tiempos']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) | $($row[4]) | $($row[5]) | $($row[6]) | $($row[7]) | $($row[8]) | $($row[9]) | $($row[10]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('### Artículos y género') | Out-Null
$out.Add('') | Out-Null
$out.Add('| Тип | Муж. род | Жен. род |') | Out-Null
$out.Add('| --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Artículos']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('| Паттерн / пример | Значение / пара | Паттерн / пример | Значение / пара |') | Out-Null
$out.Add('| --- | --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Género: reglas']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) |") | Out-Null }
$out.Add('') | Out-Null
$out.Add('### Muy / Mucho') | Out-Null
$out.Add('') | Out-Null
$out.Add('| Правило | Пример | Перевод / смысл |') | Out-Null
$out.Add('| --- | --- | --- |') | Out-Null
foreach ($row in $Grammar['Muy / Mucho']) { $out.Add("| $($row[0]) | $($row[1]) | $($row[2]) |") | Out-Null }
$out.Add('') | Out-Null

RenderDictSection 'Местоимения и притяжательные' $Buckets['Местоимения и притяжательные']
RenderDictSection 'Состояния и потребности (estar/tener)' $Buckets['Состояния и потребности (estar/tener)']
RenderDictSection 'Предлоги' $Buckets['Предлоги']
RenderDictSection 'Предлоги места' $Buckets['Предлоги места']
RenderDictSection 'Союзы' $Buckets['Союзы']
RenderDictSection 'Вопросительные слова' $Buckets['Вопросительные слова']
RenderDictSection 'Указательные и место/направление' $Buckets['Указательные и место/направление']
RenderDictSection 'Наречия и частотность' $Buckets['Наречия и частотность']
RenderDictSection 'Числительные' $Buckets['Числительные']
RenderDictSection 'Время и даты' $Buckets['Время и даты']
RenderDictSection 'Погода' $Buckets['Погода']
RenderDictSection 'Дом: комнаты и мебель' $Buckets['Дом: комнаты и мебель']
RenderDictSection 'Цвета' $Buckets['Цвета']
RenderDictSection 'Природа' $Buckets['Природа']
RenderDictSection 'Фразы (разговорное / кафе / быт)' $Buckets['Фразы (разговорное / кафе / быт)']

$text = ($out -join "`n")
$postReplacements = [ordered]@{
  '| comér | есть еду |' = '| comér | есть |'
  '| conducír | водить авто\мото\.. |' = '| conducír | водить транспорт |'
  '| conocér | быть знакомым с кем-то; знать (быть знакомым) |' = '| conocér | быть знакомым; знать лично |'
  '| dejár | оставлять/позволять |' = '| dejár | оставлять / позволять |'
  '| duchárse | мыться (душ), купаться |' = '| duchárse | мыться / принимать душ |'
  '| ir | идти (говорящий НЕ в пункте назначения) |' = '| ir | идти / ехать (не к говорящему) |'
  '| llevár | отнести (говорящий НЕ в пункте назначения) |' = '| llevár | относить / нести |'
  '| manejár | водить авто\мото\.. |' = '| manejár | водить транспорт |'
  '| montár | ездить на чёмто |' = '| montár | ездить на чём-то / садиться верхом |'
  '| sabér | знать, уметь что-то делать |' = '| sabér | знать; уметь что-то делать |'
  '| venír | идти, приходить (говорящий В пункте назначения) |' = '| venír | приходить / приезжать (к говорящему) |'
  '| estár aburrído | скучно |' = '| estár aburrído | скучно / скучаю |'
  '| estár sentádo | сидя / сидящий |' = '| estár sentádo | сидеть / сидящий |'
  '| tenér hámbre | голод / хочу есть |' = '| tenér hámbre | быть голодным / хотеть есть |'
  '| tenér miédo | страх / боюсь |' = '| tenér miédo | бояться / испытывать страх |'
  '| tenér prísa | спешка / я спешу |' = '| tenér prísa | торопиться / спешить |'
  '| tenér sed | жажда / хочу пить |' = '| tenér sed | хотеть пить |'
  '| tenér suéño | сонно / хочется спать |' = '| tenér suéño | хотеть спать / быть сонным |'
  '| ¿Cuál es tu fécha de nacimiénto? | дата рождения |' = '| ¿Cuál es tu fécha de nacimiénto? | какая у тебя дата рождения? |'
  '| ¿Cuándo es tu cumpleáños? | когда день рождения? |' = '| ¿Cuándo es tu cumpleáños? | когда у тебя день рождения? |'
  '| en púnto | 0 мин |' = '| en púnto | ровно |'
  '| y cuárto | 15 мин |' = '| y cuárto | четверть |'
  '| y média | 30 мин |' = '| y média | половина часа |'
  '| ¿Cómo te llámas? | Как тебя зовут? |' = '| ¿Cómo te llámas? | как тебя зовут? |'
  '| ¿Dónde víves? | Где ты живёшь? |' = '| ¿Dónde víves? | где ты живёшь? |'
  '| ¿En qué ciudád víves? | В каком городе ты живёшь? |' = '| ¿En qué ciudád víves? | в каком городе ты живёшь? |'
  '| a ver | дай подумать, в начале разговора |' = '| a ver | дай подумать |'
  '| Acabár de | только что (потом глагол в инфинитиве) |' = '| Acabár de | только что |'
  '| álgo mas | что-то ещё? |' = '| álgo más | что-то ещё |'
  '| ási que | so в англ |' = '| ási que | так что |'
  '| de acuérdo | согласен |' = '| de acuérdo | согласен / договорились |'
  '| gato\gatita | уменьш ласк суффикс |' = '| gáto / gatíta | кот / котик |'
  '| háce viénto | ветрено |' = ''
  '| no (lo) se | я не знаю |' = '| no (lo) sé | я не знаю |'
  '| no lo estóy ya | уже не estoy |' = '| ya no lo estóy | я уже не такой / не в таком состоянии |'
  '| No Me da péna | мне не обидно\ не жалко |' = '| no me da péna | мне не жалко / не обидно |'
  '| no sabémos si tiénen cása o no | не знаем есть дом или нет |' = '| no sabémos si tiénen cása o no | не знаем, есть ли у них дом |'
  '| Oir óye | слышать |' = '| óir / óye | слышать / слушай |'
  '| pápa quien | для кого? |' = '| ¿Pára quién? | для кого? |'
  '| pára mi\el\ella | для … |' = '| pára mí / él / élla | для меня / него / неё |'
  '| páre comer\beber | поесть \ попить … (блюда) |' = '| pára comér / bebér | поесть / попить |'
  '| que le\te póngo | что вам? |' = '| ¿Qué le / te póngo? | что вам / тебе положить? |'
  '| sentár \ sentárse | усаживать кого-то \ сидеть самому |' = '| sentár / sentárse | сажать / садиться |'
  '| sentír \ sentírse | чувствовать (себя) |' = '| sentír / sentírse | чувствовать / чувствовать себя |'
  '| te echár de ménos clásses | скучать по тебе\классам |' = '| echár de ménos | скучать по кому-то / чему-то |'
  '| téngo que | чтобы .. мне нужно |' = '| téngo que | мне нужно / я должен |'
  '| Tranquílo - tranquíl | спокойнее |' = '| tranquílo | спокойно / не волнуйся |'
  '| un dia laboráble \ éntre semána | будни |' = '| un día laboráble / éntre semána | будний день / по будням |'
  '| valér = costár | стоИть (в деньгах) |' = '| valér = costár | стоить (о цене) |'
  '| y tu también | и тебе |' = '| y tú también | и ты тоже |'
}
foreach ($entry in $postReplacements.GetEnumerator()) {
  $text = $text.Replace($entry.Key, $entry.Value)
}
$text = $text -replace '(?m)^\| comér \| есть еду \|$','| comér | есть |'
$text = $text -replace '(?m)^\| dejár \| оставлять/позволять \|$','| dejár | оставлять / позволять |'
$text = $text -replace '(?m)^\| estár casádo \| женат\\замужем \|$','| estár casádo | женат / замужем |'
$text = $text -replace '(?m)^\| abuelo\\abuela \| дедушка\\бабушка \|$','| abuélo / abuéla | дедушка / бабушка |'
$text = $text -replace '(?m)^\| aun no \| ещё нет \|$','| aún no | ещё нет |'
$text = $text -replace '(?m)^\| la cuénta\. pago\\invito yo \| счёт, я плачу \|$','| la cuénta / págo / invíto yo | счёт / плачу / угощаю я |'
$text = $text -replace '(?m)^\| plánta bája \| 0 этаж \|$','| plánta bája | нулевой этаж |'
$text = $text.Replace('| estár casádo | женат\замужем |','| estár casádo | женат / замужем |')
$text = $text.Replace('| abuelo\abuela | дедушка\бабушка |','| abuélo / abuéla | дедушка / бабушка |')
$text = $text.Replace('| aun no | ещё нет |','| aún no | ещё нет |')
$text = $text.Replace('| la cuénta. pago\invito yo | счёт, я плачу |','| la cuénta / págo / invíto yo | счёт / плачу / угощаю я |')
$text = $text.Replace('| plánta bája | 0 этаж |','| plánta bája | нулевой этаж |')
Set-Content -Encoding utf8 -Path $OutPath -Value $text
Write-Host "Wrote: $OutPath"
