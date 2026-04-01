---
name: incremental-spanish-update
description: Use when working in the `Espanol audio` repository after new material was added to `1_vocabulary_raw.md` and Codex must incrementally sync derived study files without rewriting existing learning content. Trigger for requests to update `2_vocabulary.md`, append only to `3_topics.md` and `5_phrases.md`, rebuild `4_words_usage.md`, or preserve old phrases while adding only new topics and coverage.
---

# Incremental Spanish Update

Apply this skill only inside the `Espanol audio` repository.

## Core Rule

Keep the workflow append-only for study content:

- Rebuild `2_vocabulary.md`.
- Append only new tail material to `3_topics.md`.
- Append only new tail sections and rows to `5_phrases.md`.
- Rebuild `4_words_usage.md` only after phrase additions.

Do not reorder topics. Do not rewrite old phrases. Do not mass-regenerate the file.

Exception:

- If the user explicitly asks for normalization, deduplication, redistribution between topics, or reduction of phrase count, historical rows in `5_phrases.md` may be edited or removed.
- In that mode, keep the existing topic order, but allow shrinking or rewriting old rows when it improves canonical coverage and reduces redundant person-by-person verb duplication.
- In that mode, also rebalance `Presente` away from overusing `yo` when the same lemmas can be covered naturally by other persons.
- In that mode, do not default to `aquí` for place phrases if `ahí`, `allí`, `allá`, or `acá` fit naturally and improve distribution.

## Invocation

Invoke this repo-local skill explicitly by path, for example:

`Use skill at d:\Work\AI\Espanol audio\.agents\skills\incremental-spanish-update to sync the repo after changes in 1_vocabulary_raw.md`

## Workflow

1. Read `AGENTS.md` and preserve the repository rules.
2. Create a temporary snapshot copy of the current `2_vocabulary.md` before rebuilding.
   - Recommended: store snapshots under `.\.tmp\` (gitignored) with a timestamped name.
3. Run:
   - `.\scripts\build_vocabulary.ps1`
4. Run the incremental analyzer against the snapshot and current files:
   - `.\scripts\build_incremental_update_report.ps1 -OldVocabularyPath <snapshot-path>`
   - Tip: use `-OutputPath .\.tmp\incremental_update_report.md` to persist the report.
5. Read the report and use it as the only source for new work:
   - `Новые элементы словаря`
   - `Новые темы для 3_topics.md`
   - `Новые элементы без покрытия`
   - `Рекомендации для новых фраз`
   - `Предупреждения по узким темам`
6. Update `3_topics.md` only by appending new numbered topics at the end.
   - Keep the existing topic text unchanged.
   - Use the report sections as source markers and focus lists.
7. Update `5_phrases.md` only by appending new theme sections and new phrase rows at the end.
   - Do not edit historical rows unless the user explicitly asks or the task is an explicit deduplication / normalization pass.
   - Cover every new non-numeric element at least once.
   - Treat `Количественные` and `Порядковые` gaps as optional, not blocking.
   - For narrow themes, every new phrase must visibly contain the theme material itself.
   - In tense themes, do not keep the same verb across many persons unless that is needed for section-level person coverage or for unique vocabulary coverage.
   - In `Presente`, distribute persons reasonably across the section instead of clustering the opening rows on `yo`.
   - When rebalancing place adverbs, prefer natural redistribution among `acá / ahí / allá / allí / aquí` over repeatedly reusing `aquí`.
8. (Optional) If the task explicitly includes accent/stress normalization, run:
   - `.\scripts\fix_phrases_accents.ps1 -Path .\5_phrases.md`
   - Note: this may touch historical lines; review the diff and keep changes orthographic only.
9. Rebuild:
   - `.\scripts\build_words_usage.ps1`
10. Review the resulting `4_words_usage.md`.
   - Remaining non-numeric uncovered entries are blockers.
   - Overuse of articles and other function words is not a blocker by itself.
11. If script logic changed, run:
   - `.\scripts\test_build_vocabulary.ps1` when vocabulary build logic changed
   - `.\scripts\test_build_words_usage.ps1` when usage-report logic changed
   - `.\scripts\test_build_incremental_update_report.ps1` when incremental analyzer logic changed
   - `.\scripts\test_fix_phrases_accents.ps1` when accent fixer logic changed

## Required Editing Discipline

- Never replace the full body of `3_topics.md` or `5_phrases.md`.
- Never regenerate old phrase sections from scratch.
- Prefer covering new unused vocabulary before adding stylistic variation.
- Keep phrases natural, short, and ordered by the existing progression rules from `AGENTS.md`.
- When the report says there are no new topics, do not append filler sections.
- When the task is explicit minimization, use the report's reduction candidates and preserve only the rows needed for canonical coverage, tense coverage, and section-level person coverage.
- When the task is explicit minimization, remove duplicate conversational rows from section `25` before cutting rows from earlier thematic sections, if the same state or lexeme is already covered above.

## Expected Outputs

After a normal run, the repo should have:

- rebuilt `2_vocabulary.md`,
- optionally appended tail topics in `3_topics.md`,
- optionally appended tail phrase sections in `5_phrases.md`,
- rebuilt `4_words_usage.md`.

The final user summary should mention:

- which new sections or entries were detected,
- which topics were appended,
- which phrase sections were appended,
- whether any non-numeric uncovered entries still remain.

