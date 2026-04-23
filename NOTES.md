# NOTES

Running log of decisions, gotchas, and non-obvious implementation details.
Full spatial methodology is in `description.qmd`.

---

## Template

```
### YYYY-MM-DD — Short title
**Context:** What was being worked on.
**Decision/Finding:** What was decided or discovered.
**Why:** Reason or constraint.
```

---

## Resolved Spatial Challenges

### Grid alignment (stand.grid ↔ env.grid)
- A snap grid (100×100 and 10×10) was introduced to ensure pixel-exact alignment between the stand grid and environment grid.
- Direct CRS reassignment after `disagg()` caused misalignment; solution uses explicit reprojection.
- Details: `description.qmd`, scripts `02` and `10–11`.

### Landscape buffering
- Landscapes are buffered during selection/processing to avoid edge effects; see `00_landscape_selection.r`.

### terra quirks
- Various `terra` version-specific behaviours encountered and resolved; specifics documented inline in scripts.

---

## Known Fragilities (from `issues-codex5.3.md`)

Not urgent for controlled pipeline runs, but worth awareness:

- **Script 00/01:** Column name inconsistency (`Propforested` vs `Propforest`, `Suppression` spelling)
- **Script 02:** CRS reassignment after `disagg()` should be explicit reprojection (already addressed via snap grid approach)
- **Script 10:** `sapinit_dict` written to empirical input folder — should go to output folder
- **Script 12:** Climate table-name contract (RU-keyed vs climate-grid-keyed) needs locking
- **Scripts 05/06/11/12:** Missing input validation (optional hardening)
