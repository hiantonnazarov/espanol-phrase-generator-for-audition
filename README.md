# Spanish Listening Practice & Phrase Generator — Испанские фразы для аудирования

**Generate personalized Spanish learning sentences from your vocabulary, organize them by grammar topic, and prepare text for Spanish listening comprehension and text-to-speech (TTS).** The repository includes Spanish–Russian practice phrases, PowerShell vocabulary-processing scripts, vocabulary coverage checks, and example MP3 audio lessons.

**Генератор испанских учебных фраз по собственному словарю** — для изучения испанского языка, тренировки грамматики, запоминания слов в контексте и аудирования. Проект содержит испанские фразы с переводом на русский, вспомогательные PowerShell-скрипты и готовые MP3-записи по темам.

[Русский: как пользоваться](#быстрый-старт) · [English: overview and usage](#english-overview) · [Примеры фраз](5_phrases.md) · [Аудиоуроки](audio/) · [Лицензия MIT](LICENSE)

## Возможности

- **Фразы из личного словаря:** исходные слова и выражения из `1_vocabulary_raw.md` превращаются в учебные предложения по темам.
- **Испанский с русским переводом:** `5_phrases.md` подходит для изучения лексики, грамматики и практики перевода.
- **Материалы для аудирования:** `5_phrases_audio.md` содержит версию фраз без лишнего Markdown-форматирования для передачи в сервисы синтеза речи (text-to-speech).
- **Контроль покрытия словаря:** отчёт `4_words_usage.md` помогает обнаруживать слова, которые ещё не встретились в упражнениях.
- **Инкрементальные обновления:** скрипты обнаруживают новые элементы словаря, а AI coding agent может дополнять темы и фразы без полной переработки старого материала.

> **Важно:** здесь нет полностью автономного генератора фраз или встроенного TTS API. PowerShell-скрипты обрабатывают словарь и формируют вспомогательные файлы, а новые учебные фразы составляет и дополняет **AI coding agent** по инструкциям проекта. MP3 в папке [`audio/`](audio/) были созданы отдельно через [ElevenLabs](https://elevenlabs.io/app/speech-synthesis/text-to-speech); автоматическая генерация MP3 скриптами проекта не предусмотрена.

## Быстрый старт

**Что понадобится:** Git (или скачанный ZIP репозитория), PowerShell для запуска скриптов и AI coding agent с доступом к файлам проекта (например, в редакторе кода). Для воспроизведения уже готовых аудиоуроков ничего из этого устанавливать не нужно.

1. Скачайте проект или клонируйте репозиторий:

   ```powershell
   git clone https://github.com/hiantonnazarov/espanol-phrase-generator-for-audition.git
   cd espanol-phrase-generator-for-audition
   ```

2. Добавьте свои испанские слова, переводы и заметки в [`1_vocabulary_raw.md`](1_vocabulary_raw.md). Допускаются дубли и неструктурированные записи.
3. Откройте папку проекта в среде с AI coding agent и попросите его обновить учебные материалы по инструкции ниже. Агент должен учитывать правила из [`AGENTS.md`](AGENTS.md).
4. Изучайте [фразы с переводом](5_phrases.md), используйте [текст для озвучки](5_phrases_audio.md) или слушайте [готовые MP3](audio/).

**Главный принцип:** обычно вы редактируете только `1_vocabulary_raw.md`. Скрипты и агент приводят данные к нужному формату, распределяют лексику по темам и проверяют её использование во фразах.

## Как обновлять фразы с AI coding agent

После изменения `1_vocabulary_raw.md` отправьте агенту следующее задание:

> Я обновил `1_vocabulary_raw.md`.
>
> 1. Пересобери `2_vocabulary.md` командой `./scripts/build_vocabulary.ps1`.
> 2. Запусти `./scripts/run_incremental_update.ps1`. Скрипт создаст временный отчёт об изменениях словаря, выведет его и удалит временные файлы. Сам по себе он не обновляет учебные фразы.
> 3. По отчёту дополни **только конец** `3_topics.md` новыми темами; существующие разделы сохраняй.
> 4. Дополняй **только конец** `5_phrases.md` небольшими порциями. После каждой порции:
>    - при необходимости нормализуй ударения командой `./scripts/fix_phrases_accents.ps1 -Path ./5_phrases.md`;
>    - обнови `5_phrases_audio.md` командой `./scripts/build_phrases_audio.ps1`;
>    - обнови отчёт `4_words_usage.md` командой `./scripts/build_words_usage.ps1`;
>    - проверь неиспользованные элементы словаря и предупреждения о повторениях или перекосах;
>    - добавляй фразы, пока обязательные неиспользованные элементы не закончатся (необязательные числительные можно пропускать).
> 5. В конце снова последовательно запусти `./scripts/fix_phrases_accents.ps1 -Path ./5_phrases.md`, `./scripts/build_phrases_audio.ps1` и `./scripts/build_words_usage.ps1`; проверь отчёт покрытия.
> 6. Обязательно запусти все тесты:
>    `./scripts/test_build_vocabulary.ps1`,
>    `./scripts/test_build_phrases_audio.ps1`,
>    `./scripts/test_build_words_usage.ps1`,
>    `./scripts/test_build_incremental_update_report.ps1`,
>    `./scripts/test_fix_phrases_accents.ps1`,
>    `./scripts/test_run_incremental_update.ps1`.

**Оговорка:** если `5_phrases_audio.md` редактировался вручную, не перезаписывайте его генератором без проверки. Подробные правила синхронизации указаны в [`AGENTS.md`](AGENTS.md).

## Файлы и структура проекта

| Файл / папка | Назначение |
| --- | --- |
| [`1_vocabulary_raw.md`](1_vocabulary_raw.md) | Исходные записи: испанские слова, переводы и грамматические заметки. |
| [`2_vocabulary.md`](2_vocabulary.md) | Очищенный и сгруппированный словарь с грамматическими таблицами. |
| [`3_topics.md`](3_topics.md) | Порядок учебных тем и последовательность освоения грамматики. |
| [`4_words_usage.md`](4_words_usage.md) | Отчёт о том, какие элементы словаря используются во фразах. |
| [`5_phrases.md`](5_phrases.md) | Испанские предложения с русскими переводами, сгруппированные по темам. |
| [`5_phrases_audio.md`](5_phrases_audio.md) | Подготовленный текст для TTS/озвучки без Markdown-таблиц. |
| [`audio/`](audio/) | Готовые MP3-уроки для практики восприятия испанского на слух. |
| [`scripts/`](scripts/) | PowerShell-обработка словаря, отчёты, преобразование фраз и тесты. |
| [`AGENTS.md`](AGENTS.md) | Правила, по которым AI coding agent работает с учебными файлами. |

### PowerShell-скрипты

| Скрипт | Что делает |
| --- | --- |
| `build_vocabulary.ps1` | Запускает сборку очищенного словаря. |
| `build_vocabulary_sectioned.ps1` | Реализует обработку и структурирование исходного словаря. |
| `build_incremental_update_report.ps1` | Готовит отчёт о добавленных словах и их покрытии. |
| `run_incremental_update.ps1` | Запускает инкрементальный отчёт с временными файлами и выводом в консоль. |
| `build_phrases_audio.ps1` | Подготавливает аудио-версию текста из `5_phrases.md`. |
| `build_words_usage.ps1` | Проверяет использование словаря в учебных фразах. |
| `fix_phrases_accents.ps1` | Исправляет отдельные опечатки и нормализует обозначение ударений в фразах. |
| `test_*.ps1` | Проверяют работу соответствующих сборочных и вспомогательных скриптов. |

Скрипты запускаются из корня репозитория через PowerShell, например:

```powershell
./scripts/build_vocabulary.ps1
./scripts/build_phrases_audio.ps1
./scripts/build_words_usage.ps1
```

## English overview

**Spanish Phrase Generator for Listening Practice** is an open-source Spanish study-material workflow for learners who want to practise listening, Spanish vocabulary in context, and grammar using their **own vocabulary list**.

### How it works

1. Add Spanish words, phrases, and notes to [`1_vocabulary_raw.md`](1_vocabulary_raw.md).
2. Use the included PowerShell scripts to clean and organize the vocabulary and generate an incremental coverage report.
3. Have an AI coding agent extend the topic-based Spanish practice sentences with Russian translations. The agent follows [`AGENTS.md`](AGENTS.md) and checks vocabulary coverage.
4. Study the sentences in [`5_phrases.md`](5_phrases.md), export TTS-friendly text from [`5_phrases_audio.md`](5_phrases_audio.md), or listen to the existing [Spanish MP3 audio lessons](audio/).

### Who is this for?

- **Spanish learners** looking for personalized Spanish listening exercises, example sentences, and Russian translations.
- **Language tutors and self-learners** creating topic-based exercises from a custom vocabulary list.
- **Developers and AI-agent users** interested in a PowerShell-assisted workflow for generating language-learning content and checking vocabulary coverage.

**Scope:** This is not a hosted Spanish learning app, a real-time audio generator, or a fully automated text-to-speech pipeline. Sentence writing requires an AI coding agent; the included MP3 files were generated externally. The workflow uses an existing vocabulary file, Markdown learning materials, and PowerShell scripts.

**Related terms:** Spanish listening comprehension, learn Spanish with audio, Spanish vocabulary practice, Spanish example sentences, Spanish grammar exercises, Spanish–Russian translations, custom vocabulary, AI-assisted language learning, text-to-speech preparation, PowerShell automation.

## Лицензия / License

Проект распространяется по [лицензии MIT](LICENSE). / Source code is available under the [MIT License](LICENSE).
