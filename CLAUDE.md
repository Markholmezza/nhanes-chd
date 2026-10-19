# CLAUDE.md — project context for Claude Code

## What this repo is
A CHD-prediction project on CDC NHANES 2013-2014 that became a data-leakage audit. Read `README.md` first; the findings table there is the ground truth for what the numbers should look like.

## Layout
- `notebooks/data_preprocessing.ipynb` — v2 pipeline, one row per participant. Writes `data/processed/`.
- `notebooks/nhanes_chd_audit_and_revalidation.ipynb` — audit + corrected models. Reads the **v1** artifacts in `data/` and writes `outputs/*.csv` (15 tables for Power BI).
- `notebooks/preprocessing_v1_original.ipynb` — the original (v1) preprocessing with the one-to-many join; produced `data/selected_features_v1.csv`. Kept as history, do not fix.
- `notebooks/baseline_v1_original.ipynb` — the original (leaky) modeling notebook. Do not "fix" it; it is kept as the "before".
- `notebooks/external_validation.ipynb` — temporal external validation (trained once on 2013-2014, applied to 2015-2016 and 2017-March 2020) and pooled 2013-March 2020 survey analysis. Reads `data/processed/selected_features.csv`, `data/raw/demographic.csv` and `data/raw_xpt/`; writes 8 CSVs in `outputs/`, `docs/external_validation.png`, `docs/pooled_forest.png`. Independent post-course work, not part of the BIOL 485 project.
- `analysis/svy_logistic.R` — OPTIONAL R cross-check of notebook sections 12-13. Writes `outputs/svy_prevalence_crosscheck.csv`, `outputs/svy_odds_ratios_R.csv`. The main analysis is Python; R is not required.
- `powerbi/` — `POWERBI_GUIDE.md` (three page specs), `measures.dax`, `theme.json`.
- `docs/` — TRIPOD methods, README figures.

## Rules
- Never reintroduce the bug: every merge on `SEQN` must end with `assert df["SEQN"].is_unique`. `medications.csv` is one row per prescription and must be collapsed before joining.
- Do not report accuracy as a headline metric (4% prevalence). Report AUC, sensitivity, specificity.
- The notebooks in this repo were already executed (outputs are embedded) and `outputs/` is populated; re-running should reproduce the same numbers.
- Keep `data/selected_features_v1.csv`, `data/train_split_smote.csv`, `data/test_split.csv` untouched; the audit depends on them.
- `data/raw/`, `data/raw_xpt/`, `data/processed/` and `data/processed_v1/` are git-ignored. Never commit them.
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
- External validation (class-weighted LR, trained once on 2013-2014): internal CV AUC 0.859; external AUC 0.868 (2015-2016, 244 cases) and 0.857 (2017-2020, 423 cases). The notebook's built-in asserts must pass.
- Pooled 2013-March 2020: 20,469 examined adults, 891 cases, 54 strata, design df 55 (2017-2020 has 24 strata, one with 3 PSUs); weighted prevalence 0.0384. MI odds ratios may move in the second decimal across sklearn versions.
- Leave-one-cycle-out (`outputs/iecv.csv`), AUC: held out 2013-2014 (trained on 667 cases) class-weighted LR 0.868 (0.846-0.887), unweighted LR 0.867 (slope 0.98, O/E 1.04), RF 0.865; held out 2015-2016 (655 cases) 0.872 (0.854-0.891), unweighted 0.872 (slope 1.00, O/E 1.03), RF 0.867; held out 2017-2020 (476 cases) 0.860 (0.844-0.875), unweighted 0.859 (slope 0.98, O/E 0.90), RF 0.854. Means: class-weighted LR 0.867, unweighted LR 0.866, RF 0.862. Tolerance 0.003 for LR, 0.01 for RF.
- Two cycles vs 2013-2014 only (`outputs/iecv_vs_2013only.csv`), class-weighted LR AUC: 2013-2014 0.859 -> 0.868; 2015-2016 0.868 -> 0.872; 2017-2020 0.857 -> 0.860. Unweighted LR slope on 2013-2014: 0.94 -> 0.98.
- Final model (`outputs/final_model_coefficients.csv`, unweighted LR on all cycles): 20,648 adults, 899 cases, 33 coefficients + intercept. It includes 179 interview-only 2013-2014 adults (8 cases), so it has 899 cases vs 891 in the pooled survey analysis (examined only).
