# Codex5.3

The document below was written by GPT-codex-5.3. Most of the issues are correctly identified but not points of concern in the workflow currently (like the crs overwrite, or the defensive checks). I'm recording the planning document output by GPT for future reference.

## Issues Review: Workflow Scripts 00-12

This document captures the consolidated review findings and implementation guidance for scripts 00-12. It is intended as a practical reference, not a mandate to add all defensive checks immediately.

Current preference reflected here:
- Keep immediate changes focused on correctness-impacting issues.
- Treat most input/existence/shape guards as optional hardening unless they unblock known failures.

### Scope
- Included: scripts 00 through 12, including script-level validation where present.
- Excluded: scripts 13+ and broader calibration/model-choice discussions.

### Review Philosophy
- Priority 1: defects that can change results, crash normal runs, or break data contracts.
- Priority 2: robustness improvements that reduce future breakage but may be unnecessary in controlled runs.
- Priority 3: documentation/clarity issues.

## Priority 1: Correctness-Impacting Issues

1. Script 00 field mismatch during ordering
- Risk: incorrect column reference can break or misorder selection logic.
- Issue: Propforested is created but Propforest is later referenced.
- Action: align column naming at usage site.

2. Script 01 schema drift before row binding
- Risk: CPCRW row receives non-matching field names, leading to inconsistent columns after bind.
- Issue: Propforest and Suppressio differ from workflow naming.
- Action: use Propforested and Suppression consistently.

3. Script 02 CRS metadata reassignment on disaggregated raster
- Risk: raster geometry appears in one CRS while data are in another, causing alignment errors downstream.
- Issue: direct CRS assignment after disagg instead of reprojection.
- Action: project raster to target grid/CRS explicitly.

4. Script 10 sapinit dictionary output location
- Risk: writing generated artifact into empirical input folder can overwrite reference data and blur source/output boundaries.
- Issue: sapinit_dict output path points to input area.
- Action: write to generated-output location and keep input data immutable.

5. Script 12 climate table-name contract ambiguity
- Risk: iLand climate lookup failure if env file names do not match SQLite table naming convention.
- Issue: RU-keyed vs climate-grid-keyed table naming is unresolved in code comments.
- Action: lock one contract and enforce it across climate DB creation and env.file writing.

## Priority 2: Optional Hardening (Useful, Not Urgent for Controlled Pipelines)

1. Scripts 05/06/11/12 input presence/cardinality checks
- Value: clearer failures when files are missing or duplicated.
- Current stance: optional unless failures are currently observed.

2. Script 03 climate day parsing validation
- Value: catches naming-format drift in climate layer names early.
- Current stance: optional if source naming is stable and controlled.

3. Script 08 NA and rounding policy
- Value: avoids semantic conversion of missing soil values to true zeros and better sum-to-100 handling.
- Current stance: optional if downstream assumptions intentionally treat missing as zero.

4. Script 09 water-mask alignment safeguards
- Value: reduces geometry mismatch failures in heterogeneous inputs.
- Current stance: optional if raster products are known to be co-registered.

5. Script 12 join coverage checks before global NA replacement
- Value: prevents silent masking of join/key mismatches.
- Current stance: optional if IDs are guaranteed consistent by upstream steps.

6. Script 11 no-data sentinel clarification
- Value: avoids confusion between comments and implementation (-1 vs -9999).
- Current stance: optional if -1 is accepted by target tooling and already standardized elsewhere.

## Suggested Execution Order (When You Choose to Implement)

1. Apply Priority 1 fixes in scripts 00, 01, 02, 10, 12.
2. Re-run one AK and one CA landscape through affected steps.
3. Only if needed, layer in selected Priority 2 hardening where failures or maintenance pain are highest.

## Verification Focus

1. Confirm outputs are generated in expected folders without mutating empirical source files.
2. Confirm spatial products align after script 02 changes.
3. Confirm climate table names in env files match actual SQLite table names used by iLand.
4. Confirm stand-grid and env-file artifacts are produced for both reviewed land-cover years.

## Notes
- This review intentionally separates correctness fixes from defensive engineering to match current implementation context.
- If pipeline assumptions are strongly controlled, many hardening checks can remain backlog items.