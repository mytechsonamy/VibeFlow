# <Product Name> — Canonical Terminology Glossary (single source of truth)

Rule: no variant outside this table may appear in user-visible strings.
New term? Add it here FIRST, then use it in code. Banned variants found in
the codebase also get a rule in rules.json.

## Status taxonomy

| Key | <locale-1> | <locale-2> | Visual (color+icon) | Banned variants |
|---|---|---|---|---|
| example_state | ... | ... | filled green diamond | "..." , "..." |

## Core domain concepts

| Key | <locale-1> | <locale-2> | Notes / banned variants |
|---|---|---|---|

## User-visible report / line-item labels

| Code | <locale-1> | <locale-2> |
|---|---|---|

## Internal jargon → user language (binding)

| Banned (internal) | Write instead |
|---|---|

## Format rules

- <locale-1> number: `1.234,56` · date (UI): `31.03.2026`
- <locale-2> number: `1,234.56` · date (UI): `Mar 31, 2026`
- ISO formats only in APIs, logs, file names.
- Abbreviations get tooltip/expansion on first use per page.

## Standardized footer / trust line (verbatim, every page)

<locale-1>: `...`
<locale-2>: `...`
