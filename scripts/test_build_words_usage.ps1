$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GeneratorPath = Join-Path $RootDir 'scripts\build_words_usage.ps1'

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

function Invoke-GeneratorForFixture {
  param(
    [string]$VocabularyText,
    [string]$PhrasesText
  )

  $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("words-usage-test-" + [System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  try {
    $vocabularyPath = Join-Path $tempRoot '2_vocabulary.md'
    $phrasesPath = Join-Path $tempRoot '5_phrases.md'
    $outputPath = Join-Path $tempRoot '4_words_usage.md'

    [System.IO.File]::WriteAllText($vocabularyPath, ($VocabularyText.Trim() + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($phrasesPath, ($PhrasesText.Trim() + [Environment]::NewLine), [System.Text.Encoding]::UTF8)

    & $GeneratorPath -VocabularyPath $vocabularyPath -PhrasesPath $phrasesPath -OutputPath $outputPath

    return [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::UTF8)
  }
  finally {
    if (Test-Path -LiteralPath $tempRoot) {
      Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
  }
}

function Test-CountsSingleWordsAndMultiwordEntries {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Глаголы

### Глаголы все

| Испанский | Перевод на русский |
| --- | --- |
| hablár | говорить |
| pensár en | думать о |
| a ver | дай подумать |
| ¿Qué hóra es? | сколько времени? |
'@ -PhrasesText @'
# Фразы

## 1. Старт

| Испанский | Перевод |
| --- | --- |
| Yo quiero hablár despácio. | Я хочу говорить медленно. |
| Ahora voy a pensár en ti. | Сейчас я подумаю о тебе. |
| A ver, ¿qué hóra es? | Дай подумать, который час? |
| A ver si compréndes. | Посмотрим, понимаешь ли ты. |
'@

  Assert-Contains $report '| Глаголы все | hablár | 1 |'
  Assert-Contains $report '| Глаголы все | pensár en | 1 |'
  Assert-Contains $report '| Глаголы все | a ver | 2 |'
  Assert-Contains $report '| Глаголы все | ¿Qué hóra es? | 1 |'
}

function Test-ListsUnusedEntriesSeparately {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Предлоги

### Предлоги

| Испанский | Перевод на русский |
| --- | --- |
| con | с |
| sin | без |
| para | для |
'@ -PhrasesText @'
# Фразы

## 1. Предлоги

| Испанский | Перевод |
| --- | --- |
| Café con leche para mí. | Кофе с молоком для меня. |
'@

  Assert-Contains $report '## Неиспользованные элементы'
  Assert-Contains $report '| Предлоги | sin |'
  $unusedPart = $report.Split('## Неиспользованные элементы', 2)[1]
  Assert-NotContains $unusedPart '| Предлоги | con |'
}

function Test-CountsMultiwordEntriesIgnoringVowelAccents {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Предлоги места

### Предлоги места

| Испанский | Перевод на русский |
| --- | --- |
| A la derecha | справа |
'@ -PhrasesText @'
# Фразы

## 1. Предлоги места

| Испанский | Перевод |
| --- | --- |
| El sofá está a la derécha. | Диван справа. |
'@

  Assert-Contains $report '| Предлоги места | A la derecha | 1 |'
  $unusedPart = $report.Split('## Неиспользованные элементы', 2)[1]
  Assert-NotContains $unusedPart '| Предлоги места | A la derecha |'
}

function Test-CountsSingleWordEntriesIgnoringVowelAccentsForFunctionWordSections {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Союзы

### Союзы

| Испанский | Перевод на русский |
| --- | --- |
| aunque | хотя |
'@ -PhrasesText @'
# Фразы

## 1. Союзы

| Испанский | Перевод |
| --- | --- |
| Áunque víves aquí, no vas. | Хотя ты живёшь здесь, ты не идёшь. |
'@

  Assert-Contains $report '| Союзы | aunque | 1 |'
  $unusedPart = $report.Split('## Неиспользованные элементы', 2)[1]
  Assert-NotContains $unusedPart '| Союзы | aunque |'
}

function Test-CountsEntriesIgnoringArticlesAndPrepositionsWhenSafe {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Дом

### Дом

| Испанский | Перевод на русский |
| --- | --- |
| el sofá | диван |

## Предлоги места

### Предлоги места

| Испанский | Перевод на русский |
| --- | --- |
| A la derecha | справа |
'@ -PhrasesText @'
# Фразы

## 1. Дом

| Испанский | Перевод |
| --- | --- |
| Un sofá está aquí. | Диван здесь. |

## 2. Предлоги места

| Испанский | Перевод |
| --- | --- |
| El sofá está a la derécha. | Диван справа. |
'@

  Assert-Contains $report '| Дом | el sofá | 2 |'
  Assert-Contains $report '| Предлоги места | A la derecha | 1 |'
}

function Test-DoesNotLoosenShortContentTokenEntries {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Фразы

### Фразы

| Испанский | Перевод на русский |
| --- | --- |
| a ver | дай подумать |
'@ -PhrasesText @'
# Фразы

## 1. Старт

| Испанский | Перевод |
| --- | --- |
| Quiero ver el mar hoy. | Я хочу сегодня увидеть море. |
'@

  Assert-Contains $report '## Неиспользованные элементы'
  Assert-Contains $report '| Фразы | a ver |'
  Assert-NotContains $report '| Фразы | a ver | 1 |'
}

function Test-FlagsOverusedEntries {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Фразы

### Фразы

| Испанский | Перевод на русский |
| --- | --- |
| a ver | дай подумать |
| por éso | поэтому |
| de acuérdo | договорились |
'@ -PhrasesText @'
# Фразы

## 1. Связки

| Испанский | Перевод |
| --- | --- |
| A ver, ven aquí. | Дай подумать, иди сюда. |
| A ver qué pasa. | Посмотрим, что происходит. |
| A ver si vienes hoy. | Посмотрим, придёшь ли ты сегодня. |
| Por éso no voy. | Поэтому я не иду. |
| De acuérdo, vamos. | Договорились, идём. |
'@

  Assert-Contains $report '## Потенциально перегруженные элементы'
  Assert-Contains $report '| Фразы | a ver | 3 |'
}

function Test-ReadsConjugationTablesWithoutLabelColumns {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Грамматические таблицы

### Presente

| Лицо | hablar | comer |
| --- | --- | --- |
| yo | háblo | cómo |
| tú | háblas | cómes |
'@ -PhrasesText @'
# Фразы

## 1. Presente

| Испанский | Перевод |
| --- | --- |
| Yo háblo con Ana. | Я говорю с Аной. |
'@

  Assert-Contains $report 'Всего словарных элементов: 0'
  Assert-Contains $report '## Дополнительные слова вне канонического покрытия'
  Assert-Contains $report '| Presente | háblo | 1 |'
  Assert-Contains $report '| Presente | cómo | 0 |'
  Assert-NotContains $report '| Presente | yo |'
  Assert-NotContains $report '| Presente | tú |'
}

function Test-IgnoresTopicInfoTablesAndReadsTrailingPhraseBlock {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Фразы

### Фразы

| Испанский | Перевод на русский |
| --- | --- |
| hablo | говорю |
| me llamo | меня зовут |
'@ -PhrasesText @'
# Фразы

## 1. Presente

|   |   |
| --- | --- |
| yo | hablo |
| tú | hablas |

| Me llamo Pablo. | Меня зовут Пабло. |
| Me llamo Ana. | Меня зовут Аня. |
'@

  Assert-Contains $report '| Фразы | me llamo | 2 |'
  Assert-Contains $report '## Неиспользованные элементы'
  Assert-Contains $report '| Фразы | hablo |'
  Assert-NotContains $report '| Фразы | hablo | 1 |'
}

function Test-ValidatesThemeSpecificPhrases {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Числительные

### Количественные

| Испанский | Перевод на русский |
| --- | --- |
| úno | один |
| dos | два |

### Порядковые

| Испанский | Перевод на русский |
| --- | --- |
| priméro | первый |
| segúndo | второй |
| undécimo | одиннадцатый |

## Грамматические таблицы

### Gerundio

| Infinitivo | Gerundio |
| --- | --- |
| hablár | hablándo |
| comér | comiéndo |
'@ -PhrasesText @'
# Фразы

## 12. Числительные

| Испанский | Перевод |
| --- | --- |
| dos | два |
| priméro | первый |
| undécimo | одиннадцатый |
| libros | книги |

## 19. Gerundio

| Испанский | Перевод |
| --- | --- |
| Estoy hablándo con Ana ahora. | Я сейчас говорю с Аной. |
| Estoy con Ana aquí. | Я с Аной здесь. |
'@

  Assert-Contains $report '## Проверка соответствия темам'
  Assert-Contains $report '| 19. Gerundio | Estoy con Ana aquí. | форму gerundio |'
  Assert-NotContains $report '| 12. Числительные |'
  Assert-NotContains $report '| 19. Gerundio | Estoy hablándo con Ana ahora. |'
  Assert-Contains $report '## Проверка оформления фраз'
  Assert-NotContains $report '| dos | два |'
  Assert-NotContains $report '| priméro | первый |'
  Assert-NotContains $report '| undécimo | одиннадцатый |'
  Assert-NotContains $report '| Количественные | úno |'
  Assert-NotContains $report '| Количественные | dos |'
  Assert-NotContains $report '| Порядковые | priméro |'
  Assert-NotContains $report '| Порядковые | undécimo |'
}

function Test-FlagsLiteralRussianTranslations {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Фразы про время и даты

### Фразы про время и даты

| Испанский | Перевод на русский |
| --- | --- |
| mes | месяц |
'@ -PhrasesText @'
# Фразы

## 14. Время и даты

| Испанский | Перевод |
| --- | --- |
| ¿En qué mes estámos? | В каком мы месяце? |
| Hoy es Miércoles aquí. | Сегодня среда здесь. |
| Es de la mañána todavía. | Это всё ещё утро. |
'@

  Assert-Contains $report '## Проверка русских переводов'
  Assert-Contains $report '| 14. Время и даты | ¿En qué mes estámos? | В каком мы месяце? | слишком дословный русский перевод | Какой сейчас месяц? |'
  Assert-Contains $report '| 14. Время и даты | Hoy es Miércoles aquí. | Сегодня среда здесь. | неестественный порядок слов в русском переводе | Перестроить фразу, например: "Здесь сегодня ..." |'
  Assert-Contains $report '| 14. Время и даты | Es de la mañána todavía. | Это всё ещё утро. | слишком дословный русский перевод | Сейчас ещё утро. |'
}

function Test-FlagsPhraseFormattingAntiPatterns {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Фразы

### Фразы

| Испанский | Перевод на русский |
| --- | --- |
| a ver | дай подумать |
'@ -PhrasesText @'
# Фразы

## 9. Место: предлоги места + ориентация

| Испанский | Перевод |
| --- | --- |
| Cerca = al lado. | Рядом = возле. |
| Dentro \ fuera. | Внутри / снаружи. |
'@

  Assert-Contains $report '## Проверка оформления фраз'
  Assert-Contains $report '| 9. Место: предлоги места + ориентация | Cerca = al lado. | Рядом = возле. | псевдо-словарная запись вместо учебной фразы | Заменить на нормальное предложение без `=` |'
  Assert-Contains $report '| 9. Место: предлоги места + ориентация | Dentro \ fuera. | Внутри / снаружи. | строка с вариантами через слеш вместо отдельной фразы | Развернуть варианты в отдельные фразы без `/` и `\` |'
}

function Test-FlagsUnnaturalRussianWantToWantPattern {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Состояния

### Tener + существительное / ощущение

| Испанский | Перевод на русский |
| --- | --- |
| tenér sed | хотеть пить |
'@ -PhrasesText @'
# Фразы

## 5. Estar + Tener: состояния и потребности

| Испанский | Перевод |
| --- | --- |
| No quiero tenér sed hoy. | Я не хочу хотеть пить сегодня. |
'@

  Assert-Contains $report '| 5. Estar + Tener: состояния и потребности | No quiero tenér sed hoy. | Я не хочу хотеть пить сегодня. | неестественная русская калька с `не хочу хотеть ...` | Перестроить по-русски естественно, например: "Я не хочу пить сегодня." |'
}

function Test-FlagsMissingTimeContextInTenseTopics {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Грамматические таблицы

### Futuro simple

| Лицо | Окончание | Ejemplo con comer |
| --- | --- | --- |
| yo | -é | comeré |

### Gerundio

| Infinitivo | Gerundio |
| --- | --- |
| hablár | hablándo |
'@ -PhrasesText @'
# Фразы

## 19. Gerundio

| Испанский | Перевод |
| --- | --- |
| Estóy hablándo con Ana. | Я разговариваю с Аной. |
| Estóy hablándo con Ana ahora. | Я сейчас разговариваю с Аной. |

## 24. Futuro simple + “voy a …”

| Испанский | Перевод |
| --- | --- |
| Mañána comeré en cása. | Завтра я поем дома. |
| Comeré en cása. | Я поем дома. |
'@

  Assert-Contains $report '## Проверка временного контекста'
  Assert-Contains $report '| 19. Gerundio | Estóy hablándo con Ana. | уместное указание времени для этой темы |'
  Assert-Contains $report '| 24. Futuro simple + “voy a …” | Comeré en cása. | уместное указание времени для этой темы |'
  $timePart = $report.Split('## Проверка временного контекста', 2)[1].Split('## Проверка русских переводов', 2)[0]
  Assert-NotContains $timePart '| 19. Gerundio | Estóy hablándo con Ana ahora. |'
  Assert-NotContains $timePart '| 24. Futuro simple + “voy a …” | Mañána comeré en cása. |'
}

function Test-ExcludesLegacyAggregateEntriesFromRequiredCoverage {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Предлоги места

### Предлоги места

| Испанский | Перевод на русский |
| --- | --- |
| Cerca = Al lado | близко, рядом |
| cerca | близко |
| al lado | рядом |
'@ -PhrasesText @'
# Фразы

## 9. Место

| Испанский | Перевод |
| --- | --- |
| El bar está cerca. | Бар рядом. |
| El libro está al lado de la mésa. | Книга рядом со столом. |
'@

  Assert-Contains $report '## Канонически неучитываемые legacy-элементы'
  Assert-Contains $report '| Предлоги места | Cerca = Al lado | legacy-агрегат с `=` или вариантами |'
  $unusedPart = $report.Split('## Неиспользованные элементы', 2)[1].Split('## Потенциально перегруженные элементы', 2)[0]
  Assert-NotContains $unusedPart '| Предлоги места | Cerca = Al lado |'
  Assert-NotContains $unusedPart '| Предлоги места | cerca |'
  Assert-NotContains $unusedPart '| Предлоги места | al lado |'
  $supplementalPart = $report.Split('## Дополнительные слова вне канонического покрытия', 2)[1].Split('## Неиспользованные элементы', 2)[0]
  Assert-NotContains $supplementalPart '| Предлоги места | Cerca = Al lado |'
}

function Test-KeepsSeparateSynonymsAsSeparateCoverageUnits {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Предлоги места

### Предлоги места

| Испанский | Перевод на русский |
| --- | --- |
| cerca | близко |
| al lado | рядом |
'@ -PhrasesText @'
# Фразы

## 9. Место

| Испанский | Перевод |
| --- | --- |
| El bar está cerca. | Бар рядом. |
'@

  $unusedPart = $report.Split('## Неиспользованные элементы', 2)[1].Split('## Потенциально перегруженные элементы', 2)[0]
  Assert-NotContains $unusedPart '| Предлоги места | cerca |'
  Assert-Contains $unusedPart '| Предлоги места | al lado |'
}

function Test-ReportsTenseLemmaAndPersonCoverage {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Грамматические таблицы

### Presente

| Лицо | hablár | comér | vivír |
| --- | --- | --- | --- |
| yo | háblo | cómo | vívo |
| tú | háblas | cómes | víves |
| él / ella / usted | hábla | cóme | víve |
| nosotros/as | hablámos | comémos | vivimos |
| vosotros/as | habláis | coméis | vivís |
| ellos / ellas / ustedes | háblan | cómen | víven |

### Futuro simple

| Лицо | Окончание | Ejemplo con comer |
| --- | --- | --- |
| yo | -é | comeré |
| tú | -ás | comerás |
| él / ella / usted | -á | comerá |
| nosotros/as | -emos | comerémos |
| vosotros/as | -éis | comeréis |
| ellos / ellas / ustedes | -án | comerán |

| Infinitivo | Raíz irregular | Перевод |
| --- | --- | --- |
| comér | com | есть |
| venír | vendr | приходить |
'@ -PhrasesText @'
# Фразы

## 1. Presente: окончания + формы + стартовые глаголы

| Испанский | Перевод |
| --- | --- |
| Yo háblo aquí. | Я говорю здесь. |
| Tú cómes con Ana. | Ты ешь с Аной. |
| Nosotros vivimos cerca. | Мы живём рядом. |
| Vosotros habláis despácio. | Вы говорите медленно. |
| Éllos cómen después. | Они едят потом. |

## 24. Futuro simple + “voy a …”

| Испанский | Перевод |
| --- | --- |
| Yo comeré aquí mañána. | Я завтра поем здесь. |
| Tú vendrás más tárde. | Ты придёшь позже. |
| Nosotros comerémos en cása mañána. | Мы завтра поедим дома. |
| Vosotros comeréis aquí mañána. | Вы завтра поедите здесь. |
| Éllos comerán después. | Они поедят потом. |
'@

  Assert-Contains $report '## Покрытие глаголов по временам'
  Assert-Contains $report '| Presente | hablár | да |'
  Assert-Contains $report '| Presente | vivír | да |'
  Assert-Contains $report '| Futuro simple | comér | да |'
  Assert-Contains $report '## Покрытие лиц по временным разделам'
  Assert-Contains $report '| 1. Presente: окончания + формы + стартовые глаголы | yo | да |'
  Assert-Contains $report '| 1. Presente: окончания + формы + стартовые глаголы | él / ella / usted | нет |'
  Assert-Contains $report '| 24. Futuro simple + “voy a …” | yo | да |'
  Assert-Contains $report '| 24. Futuro simple + “voy a …” | tú | да |'
  Assert-Contains $report '| 24. Futuro simple + “voy a …” | él / ella / usted | нет |'
}

function Test-ReportsReductionCandidatesWithoutBreakingCoverage {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Предлоги

### Предлоги

| Испанский | Перевод на русский |
| --- | --- |
| con | с |
| para | для |
'@ -PhrasesText @'
# Фразы

## 7. Предлоги

| Испанский | Перевод |
| --- | --- |
| Voy con Ana para cenár hoy. | Я иду с Аной ужинать сегодня. |
| Hoy voy con Ana para cenár. | Сегодня я иду с Аной ужинать. |
| Voy sin mi móvil. | Я иду без телефона. |
'@

  Assert-Contains $report '## Кандидаты на сокращение фраз'
  Assert-Contains $report '| 7. Предлоги | Hoy voy con Ana para cenár. |'
  Assert-NotContains $report '| 7. Предлоги | Voy sin mi móvil. |'
}

function Test-FlagsPlaceAdverbBalanceSkew {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Наречия места

### Наречия места

| Испанский | Перевод на русский |
| --- | --- |
| acá | здесь |
| ahí | там |
| allá | вон там |
| allí | там |
| aquí | здесь |
'@ -PhrasesText @'
# Фразы

## 8. Место: указательные + aquí/ahí/allí

| Испанский | Перевод |
| --- | --- |
| Estoy aquí ahora. | Я сейчас здесь. |
| Trabajo aquí hoy. | Я работаю здесь сегодня. |
| Como aquí ahora. | Я ем здесь сейчас. |
| Vivo aquí todavía. | Я всё ещё живу здесь. |
| Sigo aquí mañana. | Я останусь здесь завтра. |
| Duermo aquí esta noche. | Я сплю здесь этой ночью. |
| Espero aquí ahora. | Я жду здесь сейчас. |
| Entro aquí después. | Я войду сюда потом. |
| Estudio aquí hoy. | Я учусь здесь сегодня. |
| Descanso aquí ahora. | Я отдыхаю здесь сейчас. |
| El café está allí hoy. | Кофе там сегодня. |
| El pasillo está ahí ahora. | Коридор там сейчас. |
| La playa está allá hoy. | Пляж вон там сегодня. |
| El comedor está acá ahora. | Столовая здесь сейчас. |
'@

  Assert-Contains $report 'Замечаний по балансу наречий места: 1'
  Assert-Contains $report '## Ребаланс наречий места'
  Assert-Contains $report '| aquí | acá=1, ahí=1, allá=1, allí=1, aquí=10 |'
}

function Test-DoesNotFlagModeratePlaceAdverbDistribution {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Наречия места

### Наречия места

| Испанский | Перевод на русский |
| --- | --- |
| acá | здесь |
| ahí | там |
| allá | вон там |
| allí | там |
| aquí | здесь |
'@ -PhrasesText @'
# Фразы

## 8. Место: указательные + aquí/ahí/allí

| Испанский | Перевод |
| --- | --- |
| Estoy aquí ahora. | Я сейчас здесь. |
| Trabajo aquí hoy. | Я работаю здесь сегодня. |
| El café está allí hoy. | Кофе там сегодня. |
| Vivo allí todavía. | Я всё ещё живу там. |
| El pasillo está ahí ahora. | Коридор там сейчас. |
| Vamos ahí mañana. | Мы пойдём туда завтра. |
| La playa está allá hoy. | Пляж вон там сегодня. |
| Descanso allá ahora. | Я отдыхаю вон там сейчас. |
| El comedor está acá ahora. | Столовая здесь сейчас. |
| Sigo acá mañana. | Я останусь здесь завтра. |
'@

  Assert-Contains $report 'Замечаний по балансу наречий места: 0'
  $placePart = $report.Split('## Ребаланс наречий места', 2)[1]
  Assert-Contains $placePart 'Замечаний не найдено.'
}

function Test-FlagsYoHeavySkewInTenseSections {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Грамматические таблицы

### Pretérito perfecto simple

| Лицо | ir | tenér | querér | dar | decír | estár | comér |
| --- | --- | --- | --- | --- | --- | --- | --- |
| yo | fui | túve | quíse | di | díje | estúve | comí |
| tú | fuíste | tuvíste | quisíste | díste | dijíste | estuvíste | comíste |
| él / ella / usted | fue | túvo | quíso | dio | díjo | estúvo | comió |
| nosotros/as | fuímos | tuvimos | quisímos | dimos | dijímos | estuvímos | comimos |
| vosotros/as | fuísteis | tuvísteis | quisísteis | disteis | dijísteis | estuvísteis | comisteis |
| ellos / ellas / ustedes | fuéron | tuviéron | quisiéron | diéron | dijéron | estuviéron | comiéron |
'@ -PhrasesText @'
# Фразы

## 23. Pretérito perfecto simple

| Испанский | Перевод |
| --- | --- |
| Ayér fui al mar. | Вчера я ходил к морю. |
| Háce dos días túve frío. | Два дня назад мне было холодно. |
| Entónces quíse salír. | Тогда я захотел выйти. |
| Anoche di la cuénta. | Вчера вечером я отдал счёт. |
| Luego díje la verdád. | Потом я сказал правду. |
| Aquél día tú estuvíste en el pátio. | В тот день ты был во дворе. |
| Éllos comiéron después. | Они поели потом. |
'@

  Assert-Contains $report 'Замечаний по балансу лиц во временных разделах: 1'
  Assert-Contains $report '## Ребаланс лиц по временным разделам'
  Assert-Contains $report '| 23. Pretérito perfecto simple | yo=5, tú=1, él / ella / usted=0, nosotros/as=0, vosotros/as=0, ellos / ellas / ustedes=1 | стартовый блок слишком концентрируется на `yo`; перераспределить часть фраз на другие лица |'
}

function Test-DoesNotFlagBalancedTensePersonDistribution {
  $report = Invoke-GeneratorForFixture -VocabularyText @'
# vocabulary

## Грамматические таблицы

### Pretérito perfecto simple

| Лицо | ir | tenér | podér | hablár | comér | venír |
| --- | --- | --- | --- | --- | --- | --- |
| yo | fui | túve | púde | hablé | comí | víne |
| tú | fuíste | tuvíste | pudíste | habláste | comíste | viníste |
| él / ella / usted | fue | túvo | púdo | habló | comió | víno |
| nosotros/as | fuímos | tuvimos | pudimos | hablámos | comimos | vinimos |
| vosotros/as | fuísteis | tuvísteis | pudísteis | hablásteis | comisteis | vinísteis |
| ellos / ellas / ustedes | fuéron | tuviéron | pudiéron | habláron | comiéron | viniéron |
'@ -PhrasesText @'
# Фразы

## 23. Pretérito perfecto simple

| Испанский | Перевод |
| --- | --- |
| Ayér fui al mar. | Вчера я ходил к морю. |
| Háce dos días tú tuvíste frío. | Два дня назад тебе было холодно. |
| Úna vez él púdo respondér. | Однажды он смог ответить. |
| Entónces nosotros hablámos con élla. | Тогда мы поговорили с ней. |
| Anoche vosotros comisteis muy poco. | Вчера вечером вы поели очень мало. |
| Éllos viniéron después. | Они пришли потом. |
'@

  Assert-Contains $report 'Замечаний по балансу лиц во временных разделах: 0'
  $balancePart = $report.Split('## Ребаланс лиц по временным разделам', 2)[1].Split('## Ребаланс наречий места', 2)[0]
  Assert-Contains $balancePart 'Замечаний не найдено.'
}

$tests = @(
  'Test-CountsSingleWordsAndMultiwordEntries',
  'Test-ListsUnusedEntriesSeparately',
  'Test-CountsMultiwordEntriesIgnoringVowelAccents',
  'Test-CountsSingleWordEntriesIgnoringVowelAccentsForFunctionWordSections',
  'Test-CountsEntriesIgnoringArticlesAndPrepositionsWhenSafe',
  'Test-DoesNotLoosenShortContentTokenEntries',
  'Test-FlagsOverusedEntries',
  'Test-ReadsConjugationTablesWithoutLabelColumns',
  'Test-IgnoresTopicInfoTablesAndReadsTrailingPhraseBlock',
  'Test-ValidatesThemeSpecificPhrases',
  'Test-FlagsLiteralRussianTranslations',
  'Test-FlagsPhraseFormattingAntiPatterns',
  'Test-FlagsUnnaturalRussianWantToWantPattern',
  'Test-FlagsMissingTimeContextInTenseTopics',
  'Test-ExcludesLegacyAggregateEntriesFromRequiredCoverage',
  'Test-KeepsSeparateSynonymsAsSeparateCoverageUnits',
  'Test-ReportsTenseLemmaAndPersonCoverage',
  'Test-ReportsReductionCandidatesWithoutBreakingCoverage',
  'Test-FlagsYoHeavySkewInTenseSections',
  'Test-DoesNotFlagBalancedTensePersonDistribution',
  'Test-FlagsPlaceAdverbBalanceSkew',
  'Test-DoesNotFlagModeratePlaceAdverbDistribution'
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
