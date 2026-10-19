# CLAUDE.md — project context for Claude Code

## What this repo is
A CHD-prediction project on CDC NHANES 2013-2014 that became a data-leakage audit. Read `README.md` first; the findings table there is the ground truth for what the numbers should look like.

## Layout
- `notebooks/data_preprocessing.ipynb` — v2 pipeline, one row per participant. Writes `data/processed/`.
- `notebooks/nhanes_chd_audit_and_revalidation.ipynb` — audit + corrected models. Reads the **v1** artifacts in `data/` and writes `outputs/*.csv` (15 tables for Power BI).
- `notebooks/preprocessing_v1_original.ipynb` — the original (v1) preprocessing with the one-to-many join; produced `data/selected_features_v1.csv`. Kept as history, do not fix.
- `notebooks/baseline_v1_original.ipynb` — the original (leaky) modeling notebook. Do not "fix" it; it is kept as the "before".
- `analysis/svy_logistic.R` — OPTIONAL R cross-check of notebook sections 12-13. Writes `outputs/svy_prevalence_crosscheck.csv`, `outputs/svy_odds_ratios_R.csv`. The main analysis is Python; R is not required.
- `powerbi/` — `POWERBI_GUIDE.md` (three page specs), `measures.dax`, `theme.json`.
- `docs/` — PDF report, TRIPOD methods, README figures.

## Rules
- Never reintroduce the bug: every merge on `SEQN` must end with `assert df["SEQN"].is_unique`. `medications.csv` is one row per prescription and must be collapsed before joining.
- Do not report accuracy as a headline metric (4% prevalence). Report AUC, sensitivity, specificity.
- The notebooks in this repo were already executed (outputs are embedded) and `outputs/` is populated; re-running should reproduce the same numbers.
- Keep `data/selected_features_v1.csv`, `data/train_split_smote.csv`, `data/test_split.csv` untouched; the audit depends on them.
- `data/raw/` and `data/processed/` are git-ignored. Never commit them.
- Run notebooks with `jupyter nbconvert --to notebook --execute --inplace <nb>` from the repo root so relative paths resolve.
- Python env: `pip install -r requirements.txt`. If `imbalanced-learn` is missing, install it; do not stub SMOTE.
- Survey regression is implemented in numpy in section 13 (`svy_logit`). Do not replace it with statsmodels `GLM(freq_weights=...)` or sklearn `sample_weight` alone: point estimates would match but SEs would ignore strata/PSUs and be wrong.

## Expected numbers after a correct run (sanity checks)
- Audit funnel: 20,194 rows → 10,175 SEQN → 15,103 labeled rows → **5,751** labeled participants.
- Cohort: 232 CHD cases (4.0%), median age 48.
- Leakage: ~75% of original test rows have an exact copy in the SMOTE training set.
- Corrected AUC (5-fold, participant-level): LR 0.859, RF 0.858, KNN 0.748 (bootstrap CIs ±0.02). If RF comes back > 0.95, duplicates are back — stop and investigate.
- Threshold for ≥85% sensitivity (LR): 0.40 → sensitivity 0.86, specificity 0.72, 31% flagged.
- SMOTE inside fold vs class weights: LR 0.856 vs 0.859; RF 0.840 vs 0.858. SMOTE comes from the real `imbalanced-learn` package (`imblearn.pipeline.Pipeline`, verified with 0.14.2); the numbers may differ in the third decimal between imbalanced-learn versions.
- Top odds ratio: Age 3.67 per SD.
- Calibration (unweighted LR): mean predicted 0.0405 vs observed 0.0403, slope 0.94, Brier 0.0352. Class-weighted LR: mean predicted 0.30, Brier 0.151.
- Decision curve: unweighted LR beats treat-all/none at every threshold 0.01–0.30; class-weighted LR negative from 0.05.
- Missing-data sensitivity: all five strategies AUC 0.857–0.860; complete cases n = 2,335, 97 cases.
- Survey-weighted prevalence (all adults): 0.0365, SE 0.0043, 95% CI 0.0283–0.0469, 228.7 M adults represented, design df 15. 60+: 0.1071 (0.0840–0.1356).
- Survey-weighted logistic regression (section 13, MI m = 20): Age OR 3.59/SD (2.72–4.74), family history of diabetes 1.80 (1.39–2.34), total cholesterol 0.59/SD (0.41–0.86). Complete cases n = 4,760, 199 cases. Jackknife/sandwich SE ratio median 1.02. MI estimates can move in the second decimal across sklearn versions; complete-case estimates should not.
- If the optional R script is run, its prevalence cross-check must pass its built-in tolerance (prevalence 1e-4, SE 5e-4, CI 2e-3).
- v2 preprocessing: `selected_features.csv` has 10,175 rows (all participants), 5,751 with a label.
