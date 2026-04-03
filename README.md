Система превращает ваш словарь испанского в учебные фразы — чтобы учить материал и (опционально) генерировать аудио для аудирования.

Главная идея: вы редактируете **только** `1_vocabulary_raw.md`. Остальное обновляет AI coding agent (с помощью PowerShell-скриптов из `scripts/`). Результат:


## Как запускать обновления (через coding agent)

Скачайте репозиторий, откройте папку проекта и отправьте агенту запрос:

> Я обновил `1_vocabulary_raw.md`.  
> 1) Пересобери `2_vocabulary.md`: `.\scripts\build_vocabulary.ps1`.  
> 2) Запусти `.\scripts\run_incremental_update.ps1` — он пересоберёт словарь, сформирует инкрементальный отчёт **во временный файл**, выведет его и удалит временные файлы автоматически.  
> 3) По отчёту обнови **только хвост** `3_topics.md` (сначала темы; не переписывай старое).  
> 4) Дальше обновляй **только хвост** `5_phrases.md` порциями. После каждой порции:
>    - пересобирай `4_words_usage.md`: `.\scripts\build_words_usage.ps1`;
>    - смотри “Неиспользованные элементы” и предупреждения (перекос `yo`, перегрузы, узкие темы);
>    - добавляй фразы/вариации, пока “Неиспользованные элементы” не пуст (числительные можно игнорировать, если отчёт помечает их как необязательные).  
> 5) После всех правок фраз прогони ударения: `.\scripts\fix_phrases_accents.ps1 -Path .\5_phrases.md`.  
> 6) Ещё раз пересобери `4_words_usage.md`: `.\scripts\build_words_usage.ps1` и проверь покрытие/предупреждения.  
> 7) Запусти тесты (всегда):  
>    `.\scripts\test_build_vocabulary.ps1`  
>    `.\scripts\test_build_words_usage.ps1`  
>    `.\scripts\test_build_incremental_update_report.ps1`  
>    `.\scripts\test_fix_phrases_accents.ps1`  
>    `.\scripts\test_run_incremental_update.ps1`


## Структура репозитория

### Markdown-файлы (данные/контент)
- `1_vocabulary_raw.md` — исходный “грязный” конспект/словарь (вход).
- `2_vocabulary.md` — очищенный словарь + грамматические таблицы (генерируется из `1_vocabulary_raw.md`).
- `3_topics.md` — список тем и прогрессия (обычно обновляется агентом инкрементально, append-only).
- `5_phrases.md` — учебные фразы по темам (обычно обновляется агентом инкрементально, append-only).
- `4_words_usage.md` — отчёт покрытия словаря фразами (генерируется из `2_vocabulary.md` и `5_phrases.md`).
- `AGENTS.md` — для codex AI coding agent 

### Scripts (PowerShell)
- `scripts/build_vocabulary.ps1` — вход для пересборки `2_vocabulary.md` (обёртка).
- `scripts/build_vocabulary_sectioned.ps1` — фактический генератор словаря из `1_vocabulary_raw.md`.
- `scripts/build_words_usage.ps1` — генератор `4_words_usage.md` по `2_vocabulary.md` и `5_phrases.md`.
- `scripts/build_incremental_update_report.ps1` — отчёт по новым элементам после обновления словаря.
- `scripts/run_incremental_update.ps1` — обёртка: временный файл отчёта + авто-удаление + вывод в stdout (для агентов).
- `scripts/fix_phrases_accents.ps1` — нормализация/исправление ударений и некоторых частых опечаток в тексте фраз.
- `scripts/test_build_vocabulary.ps1`, `scripts/test_build_words_usage.ps1`, `scripts/test_build_incremental_update_report.ps1`, `scripts/test_fix_phrases_accents.ps1`, `scripts/test_run_incremental_update.ps1` — тесты скриптов.
