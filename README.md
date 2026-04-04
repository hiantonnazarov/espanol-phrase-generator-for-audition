Система превращает ваш словарь испанского `1_vocabulary_raw.md` в учебные фразы `5_phrases_audio.md` и `5_phrases_audio.md` — чтобы учить материал и (опционально) генерировать аудио для аудирования. Во фразах скрипт старается покрыть **все** слова из словаря.

**Главная идея:** вы редактируете **только** словарь `1_vocabulary_raw.md`. Остальное обновляет AI coding agent (с помощью PowerShell-скриптов из `scripts/`).

## Что тут за файлы и папки
- папка `audio` — аудио с AI-прочтением фраз из `5_phrases_audio.md`, пока собрано вручную через [Elevenlabs](https://elevenlabs.io/app/speech-synthesis/text-to-speech)

- `1_vocabulary_raw.md` — исходный “грязный” конспект/словарь. Там могут быть дубли, ошибки и тд - это потом всё будет исправлено скриптами, поэтому можно не заморачиваться
- `2_vocabulary.md` — очищенный словарь + грамматические таблицы (генерируется из `1_vocabulary_raw.md`).
- `3_topics.md` — список тем для группировки фраз (генерируется из `2_vocabulary.md`).
- `4_words_usage.md` — вспомогательный отчёт для того, чтобы убедиться, что каждое слово из словаря хотя бы раз используется во фразах, это заложено в скрипты (генерируется из `2_vocabulary.md` и `5_phrases.md`).
- `5_phrases.md` — учебные фразы по темам (генерируется из `2_vocabulary.md` и `3_topics.md` с помощью `4_words_usage.md`). 
- `5_phrases_audio.md` — вспомогательный файл, аналог `5_phrases.md`, но там убрано форматирование, чтобы AI не тупил и не читал его 

## Как запускать обновления фраз (через coding agent)
Скачайте репозиторий, откройте папку проекта и отправьте агенту запрос:

> Я обновил `1_vocabulary_raw.md`.  
> 1) Пересобери `2_vocabulary.md`: `./scripts/build_vocabulary.ps1`.  
> 2) Запусти `./scripts/run_incremental_update.ps1` — он пересоберёт словарь, сформирует инкрементальный отчёт **во временный файл**, выведет его и удалит временные файлы автоматически. Этот шаг работает только со словарём и отчётом, он не обновляет `5_phrases.md` и `5_phrases_audio.md`.  
> 3) По отчёту обнови **только хвост** `3_topics.md` (сначала темы; не переписывай старое).  
> 4) Дальше обновляй **только хвост** `5_phrases.md` порциями. После каждой порции:  
>    - при необходимости прогони ударения: `./scripts/fix_phrases_accents.ps1 -Path ./5_phrases.md`;  
>    - пересобирай `5_phrases_audio.md`: `./scripts/build_phrases_audio.ps1`;  
>    - пересобирай `4_words_usage.md`: `./scripts/build_words_usage.ps1`;  
>    - смотри “Неиспользованные элементы” и предупреждения (перекос `yo`, перегрузы, узкие темы);  
>    - добавляй фразы/вариации, пока “Неиспользованные элементы” не пуст (числительные можно игнорировать, если отчёт помечает их как необязательные).  
> 5) После всех правок фраз ещё раз последовательно запусти:  
>    - `./scripts/fix_phrases_accents.ps1 -Path ./5_phrases.md`  
>    - `./scripts/build_phrases_audio.ps1`  
>    - `./scripts/build_words_usage.ps1`  
>    и проверь покрытие/предупреждения.  
> 6) Запусти тесты (всегда):  
>    `./scripts/test_build_vocabulary.ps1`  
>    `./scripts/test_build_phrases_audio.ps1`  
>    `./scripts/test_build_words_usage.ps1`  
>    `./scripts/test_build_incremental_update_report.ps1`  
>    `./scripts/test_fix_phrases_accents.ps1`  
>    `./scripts/test_run_incremental_update.ps1`

## Scripts (PowerShell)
- `scripts/build_vocabulary.ps1` — вход для пересборки `2_vocabulary.md` (обёртка).
- `scripts/build_vocabulary_sectioned.ps1` — фактический генератор словаря из `1_vocabulary_raw.md`.
- `scripts/build_phrases_audio.ps1` — генератор `5_phrases_audio.md` из `5_phrases.md`.
- `scripts/build_words_usage.ps1` — генератор `4_words_usage.md` по `2_vocabulary.md` и `5_phrases.md`.
- `scripts/build_incremental_update_report.ps1` — отчёт по новым элементам после обновления словаря.
- `scripts/run_incremental_update.ps1` — обёртка: временный файл отчёта + авто-удаление + вывод в stdout (для агентов).
- `scripts/fix_phrases_accents.ps1` — нормализация/исправление ударений и некоторых частых опечаток в тексте фраз.
- `scripts/test_build_vocabulary.ps1`, `scripts/test_build_phrases_audio.ps1`, `scripts/test_build_words_usage.ps1`, `scripts/test_build_incremental_update_report.ps1`, `scripts/test_fix_phrases_accents.ps1`, `scripts/test_run_incremental_update.ps1` — тесты скриптов.
