# Bug Report: `QSqlQuery::exec: database not open` in iLand 2.1

**Title:** `QSqlQuery::exec: database not open` (×2) at end of model creation in iLand 2.1 — regression from 2.0

## Description

iLand 2.1 emits two `QSqlQuery::exec: database not open` warnings at the end of the model creation phase, immediately before `*** running model`. The model proceeds and runs correctly; outputs are written as expected. This does not occur in iLand 2.0.

## To Reproduce

Run any project file via `ilandc`. The error appears regardless of:
- Platform (reproduced on Windows/MINGW64 and Linux/HPC)
- Whether the management JS file is enabled (`<file></file>` blanked — error persists, ruling out `saveWorkflow.js`)
- Project configuration

## Observed Output (2.1)

```
HH:MM:SS: *** creating model...
HH:MM:SS: **************************************************
[~5 minutes later]
HH:MM:SS: QSqlQuery::exec: database not open
HH:MM:SS: QSqlQuery::exec: database not open
HH:MM:SS: **************************************************
HH:MM:SS: *** running model for N years
```

## Expected Output (2.0)

```
HH:MM:SS: *** creating model...
HH:MM:SS: **************************************************
[~5 minutes later]
HH:MM:SS: **************************************************
HH:MM:SS: *** running model for N years
```

## Version Information

| | Version | Commit | Shows error |
|---|---|---|---|
| iLand 2.0 | 2.0 | `ff092eae` (2026-02-23) | No |
| iLand 2.1 (local) | 2.1 | `10d9d774` (07.08.2025) | Yes |
| iLand 2.1 (HPC) | 2.1 | `2dcc1300` (2026-04-28) | Yes |

## Interpretation

The timing (end of model creation, two occurrences) suggests iLand 2.1 queries the output database during the initialization sequence before the connection has been formally opened. iLand recovers and opens the connection successfully, so the warnings are non-fatal.
