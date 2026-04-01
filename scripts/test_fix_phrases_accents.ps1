$ErrorActionPreference = 'Stop'

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$phrasesPath = Join-Path $RootDir '5_phrases.md'
$tmp = Join-Path $env:TEMP ("phrases.accents.test.{0}.md" -f ([Guid]::NewGuid().ToString('N')))

Copy-Item -LiteralPath $phrasesPath -Destination $tmp -Force
try {
  & (Join-Path $PSScriptRoot 'fix_phrases_accents.ps1') -Path $tmp

  function HasAccent([string]$s) { return $s -match '[áéíóúÁÉÍÓÚ]' }
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

  $wordRegex = [regex]'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+(?:-[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+)*'
  $text = Get-Content -LiteralPath $tmp -Raw
  $bad = New-Object System.Collections.Generic.List[string]

  foreach ($m in $wordRegex.Matches($text)) {
    $w = $m.Value
    if (HasAccent $w) { continue }
    $nuclei = @(Nuclei $w)
    if ($nuclei.Count -le 1) { continue }
    $bad.Add($w) | Out-Null
    if ($bad.Count -ge 50) { break }
  }

  if ($bad.Count -gt 0) {
    $unique = $bad | Group-Object | Sort-Object Count -Descending | Select-Object -First 20
    Write-Host "Found words without accents (top 20):"
    $unique | ForEach-Object { Write-Host ("- {0} x{1}" -f $_.Name, $_.Count) }
    throw "Some multi-vowel words still have no accents in 5_phrases.md (or are not fixed by fix_phrases_accents.ps1)."
  }

  Write-Host "PASS Test-FixPhrasesAccentsLeavesNoMultiVowelWordsUnaccented"
}
finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
