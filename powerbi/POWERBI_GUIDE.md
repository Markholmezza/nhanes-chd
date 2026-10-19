# Power BI report: "CHD on NHANES — Cohort Audit & Model Revalidation"

Three pages. Page 1 is the clinical story (who has CHD). Page 2 is the data-science story (why the original 0.999 AUC was wrong and what the honest numbers are). Page 3 is the biostatistics story (U.S. population estimates with survey weights, calibration, decision curve). Pages 2 and 3 are the ones to screenshot for a resume or portfolio.

All inputs come from `outputs/` after running `notebooks/nhanes_chd_audit_and_revalidation.ipynb`.

## 1. Load the data

Home > Get data > Text/CSV, one query per file. Keep the query names equal to the file names (the DAX in `measures.dax` relies on them).

| Query | File | Grain | Notes |
|---|---|---|---|
| `nhanes_chd_cohort` | `nhanes_chd_cohort.csv` | one row per participant | **fact table**. Set `SEQN` as Whole number, `CHD_Flag` as Whole number, lab columns and `WTMEC2YR` as Decimal. |
| `prevalence_by_group` | `prevalence_by_group.csv` | factor × level | pre-aggregated; optional if you compute prevalence live from the fact table |
| `missingness` | `missingness.csv` | one row per lab | `MissingShare` as Percentage |
| `funnel` | `funnel.csv` | one row per audit step | sort `Step` by `Order` (Column tools > Sort by column) |
| `model_comparison` | `model_comparison.csv` | model × setup | |
| `auc_bootstrap_ci` | `auc_bootstrap_ci.csv` | one row per model | error bars |
| `threshold_curve` | `threshold_curve.csv` | model × threshold | |
| `balancing_comparison` | `balancing_comparison.csv` | model × balancing | |
| `lr_odds_ratios` | `lr_odds_ratios.csv` | one row per feature | |
| `weighted_prevalence` | `weighted_prevalence.csv` | one row per factor level | weighted + unweighted prevalence, design-based CIs |
| `calibration_summary` | `calibration_summary.csv` | one row per model | |
| `calibration_curve` | `calibration_curve.csv` | model × risk decile | |
| `decision_curve` | `decision_curve.csv` | strategy × threshold | |
| `missing_sensitivity` | `missing_sensitivity.csv` | one row per strategy | |
| `svy_odds_ratios` | `svy_odds_ratios.csv` | model × term | survey-weighted ORs (filter `Model` to the multiple-imputation model) |

**Relationships:** none are required. The cohort table is self-contained and the analytic tables are small disconnected tables. Do **not** let Power BI auto-create relationships between `Model` columns (Model view > Manage relationships > delete any it inferred), otherwise cross-filtering between the comparison visuals produces blanks.

**Sorting category labels:** the cohort categories are prefixed with a digit (`1 Normal`, `2 Elevated`, …) so they sort clinically. To hide the digit in axis labels, add a calculated column:

```DAX
BPCategory Label = MID ( nhanes_chd_cohort[BPCategory], 3, 100 )
```

then Column tools > Sort by column > `BPCategory`. Same for `HbA1cCategory` and `CholesterolCategory`.

## 2. Measures

Paste the blocks in `measures.dax` (Modeling > New measure, one block at a time). The ones you need on page 1 are `Participants`, `CHD Cases`, `CHD Prevalence`, `CHD Prevalence (All Adults)`, `Median Age`; page 2 uses the model and threshold measures.

## 3. Page 1 — "Cohort & risk groups" (1280 × 720)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ Coronary heart disease in NHANES 2013-2014 adults        [Sex ▾] [Age group ▾]│
│ Unweighted, one row per participant, n = 5,751                                │
├──────────────┬──────────────┬──────────────┬──────────────┬──────────────────┤
│ 5,751        │ 232          │ 4.0%         │ 48           │ 52% female       │
│ Adults 20-80 │ CHD cases    │ CHD prevalence│ Median age  │                  │
├──────────────┴──────────────┴──────────────┴──────────────┴──────────────────┤
│ CHD prevalence by risk group (bar, horizontal)   │ Missing lab values (bar)   │
│  Age 60+ ............................ 10.1%     │  Triglycerides ...... 55.7%│
│  Stroke history: Yes ................ xx %      │  Blood pressure ..... 11.4%│
│  HbA1c diabetes range ............... 11.6%     │  Chemistry panel .... 7.7% │
│  Self-reported diabetes: Yes ........ xx %      │  Blood count ........ 6.5% │
│  …   (dashed line = all adults 4.0%)            │                            │
├─────────────────────────────────────────────────┴────────────────────────────┤
│ Small multiples: prevalence by Blood pressure | HbA1c | Cholesterol  (3 bars) │
└──────────────────────────────────────────────────────────────────────────────┘
```

Visual-by-visual:

1. **Slicers** (top right): `Sex`, `AgeGroup` from the cohort table, style "Tile". Everything on this page responds to them.
2. **KPI cards** (row 2): `Participants`, `CHD Cases`, `CHD Prevalence` (format 0.0%), `Median Age`, `Share Female`. Card subtitle via `CHD Cases Label`.
3. **Prevalence by risk group** (clustered bar, horizontal). Build it from the fact table so it responds to slicers: Y-axis = a *field parameter* over `AgeGroup`, `StrokeHistory`, `HbA1cCategory`, `DiabetesSelfReport` (Modeling > New parameter > Fields), X = `CHD Prevalence`. Add an **analytics constant line** at the value of `CHD Prevalence (All Adults)` (Analytics pane > Constant line, or a line visual overlay). Visual-level filter: exclude `Missing` and `Unknown`, and `Group Is Large Enough = 1`. Conditional formatting: bars ≥ 10% in accent blue `#1A73E8`, others `#BDC1C6`.
4. **Missing lab values** (bar, horizontal) from `missingness`, X = `MissingShare`, sorted descending, data labels on. Title: "Triglycerides are missing for more than half of participants".
5. **Small multiples** (clustered column, one visual with Small multiples = category field): three panels for `BPCategory Label`, `HbA1cCategory Label`, `CholesterolCategory Label`, Y = `CHD Prevalence`. Caption under the cholesterol panel: "Lower prevalence at high cholesterol is consistent with statin treatment after diagnosis (cross-sectional data)."
6. **Footnote** (text box, 9 pt grey): "Source: CDC NHANES 2013-2014, MCQ160C self-reported CHD. Unweighted sample prevalence; survey weights not applied."

## 4. Page 2 — "Data audit & model revalidation" (1280 × 720)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ The original 0.999 AUC came from duplicated participants, not from the model  │
├──────────────────────────┬───────────────────────────────────────────────────┤
│ Funnel: rows → people    │ AUC, original vs corrected (dumbbell / clustered) │
│  20,194 rows merged      │  Random forest   0.999 ●────────────● 0.858       │
│  15,103 labeled rows     │  KNN             0.987 ●──────● 0.748             │
│   5,751 participants     │  Logistic reg.   0.822 ●─● 0.859                  │
│  "2.6x rows per person"  │  (error bars from auc_bootstrap_ci)               │
├──────────────────────────┼───────────────────────────────────────────────────┤
│ 75% of test rows had an  │ Corrected models: sensitivity / specificity table │
│ exact copy in training   │ + SMOTE-in-fold vs class-weights (matrix)         │
│ (98% of CHD rows)        │                                                   │
├──────────────────────────┴───────────────────────────────────────────────────┤
│ Threshold slicer [0.05 … 0.95]  → Sensitivity ■■■■ 0.85 Specificity ■■ 0.6   │
│ Line: sensitivity & specificity vs threshold (logistic regression)           │
├──────────────────────────────────────────────────────────────────────────────┤
│ Odds ratios with 95% CI (dot + error bars, log axis), top 12 features        │
└──────────────────────────────────────────────────────────────────────────────┘
```

Visual-by-visual:

1. **Funnel** visual from `funnel` (Category = `Step`, Values = `Count`, sorted by `Order`). Card beside it: `Inflation Label`.
2. **AUC original vs corrected**: clustered bar from `model_comparison` with Legend = `Setup`, Y = `Model`, X = `AUC`, X-axis range 0.7–1.0. Colors: original `#BDC1C6`, corrected `#1A73E8`. Add error bars: Analytics > Error bars, upper/lower bound from `auc_bootstrap_ci` (requires same `Model` key; this is the one place a relationship `model_comparison[Model]` → `auc_bootstrap_ci[Model]` is useful, many-to-one, single direction). If you prefer a dumbbell, the "Dumbbell Bar Chart" AppSource visual accepts the two setups as start/end.
3. **Leakage card**: a card with `Leaked Test Rows %` (0.754) and subtitle "of original test rows had an exact copy in the SMOTE training set (98% of CHD rows)".
4. **Corrected metrics table**: Matrix from `model_comparison` filtered to the corrected setup: rows = `Model`, values = AUC, Accuracy, Sensitivity, Specificity, Threshold. Conditional formatting (data bars) on Sensitivity so RF's 0.155 is visibly poor despite 0.948 accuracy. Second small matrix from `balancing_comparison` (rows = Model, columns = Balancing, value = AUC).
5. **Threshold explorer**: slicer on `threshold_curve[Threshold]` (single select, style Dropdown or Slider) and three cards: `Sensitivity at Threshold`, `Specificity at Threshold`, `Flagged Adults at Threshold`. Line chart: X = Threshold, Y = Sensitivity and Specificity, filtered to Model = "Logistic regression". Title: "Lowering the threshold trades specificity for sensitivity".
6. **Odds ratios**: clustered bar (horizontal) from `lr_odds_ratios`, top N filter 12 by `AbsLogOR`, X = `OddsRatio`, log-scale axis, constant line at 1, error bars from `CI_low` / `CI_high`, bar color from `OR Direction Color` (conditional formatting > field value). Caption: "Per SD (numeric) or per category (one-hot). Associations in cross-sectional data, not causal effects."


## 4b. Page 3 — "U.S. population estimates & calibration" (1280 × 720)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ About 8.3 million U.S. adults report CHD; the risk model is calibrated       │
├──────────────┬──────────────┬──────────────┬─────────────────────────────────┤
│ 3.6%         │ 2.8 – 4.7%   │ 8.3 M        │ [Weighted ◉ / Unweighted ○]     │
│ U.S. adults  │ 95% CI       │ adults w/ CHD│ toggle (field parameter)        │
├──────────────┴──────────────┴──────────────┴─────────────────────────────────┤
│ Prevalence by group: weighted dot + CI bar, unweighted tick (dot plot)       │
│  Age 60+            ───●───  10.7%   |10.1                                   │
│  Stroke history     ─────────●──────── 19.4%                                 │
│  …                                                                           │
├──────────────────────────────────────┬───────────────────────────────────────┤
│ Calibration: observed vs predicted   │ Decision curve: net benefit vs         │
│ (scatter + y=x line), 3 models       │ threshold, LR vs treat all / none      │
├──────────────────────────────────────┴───────────────────────────────────────┤
│ Missing-data sensitivity: 5 strategies, AUC 0.857–0.860 (table w/ data bars)│
└──────────────────────────────────────────────────────────────────────────────┘
```

1. **KPI cards**: `Weighted Prevalence (All Adults)`, a card showing `CI Label`, and `Adults With CHD (Millions)`. All three come from `weighted_prevalence` filtered to Factor = "All adults".
2. **Weighted / unweighted toggle**: Modeling > New parameter > Fields, with `Weighted Prevalence (live)` and `CHD Prevalence`. Put the parameter in a slicer; the page-1 visuals can reuse it, so the whole report flips between sample and population. This is the single most "biostat" interaction in the report.
3. **Prevalence by group (dot plot with CIs)**: from `weighted_prevalence`, Y = `Level` (with `Factor` as the hierarchy above it, or small multiples by `Factor`), X = `WeightedPrevalence`, error bars `CI_low`/`CI_high` (Analytics > Error bars). Add `UnweightedPrevalence` as a second series in grey with markers only. Exclude Factor = "All adults" and use it as a constant line instead.
4. **Calibration plot**: scatter from `calibration_curve`, X = `MeanPredicted`, Y = `Observed`, Legend = `Model`, both axes 0–0.25. Power BI has no built-in y = x line: create a two-row table `diag` (Home > Enter data: `x, y` = `0, 0` and `0.25, 0.25`), draw it as a dashed grey line chart with the same axis ranges, and place the scatter on top with a transparent background. Colors: unweighted LR blue, class-weighted LR grey, RF red. Cards beside it from `calibration_summary`: Brier and calibration slope per model.
5. **Decision curve**: line chart from `decision_curve`, X = `Threshold`, Y = `NetBenefit`, Legend = `Strategy`, Y-axis range −0.01 to 0.045. Title: "The calibrated model adds net benefit at every threshold from 1% to 30%".
6. **Missing-data table**: matrix from `missing_sensitivity` (Strategy, N, Cases, AUC, CI_low, CI_high) with data bars on AUC. Caption: "Triglycerides are missing for 56% (fasting subsample only); results do not depend on how they are handled."
7. **Survey-weighted odds ratios**: forest plot of `svy_odds_ratios` filtered to Model = "Multiple imputation (m=20)", same construction as page 2's odds-ratio visual (log axis, constant line at 1, error bars from `CI_low`/`CI_high`). Color the points blue when the CI excludes 1 (measure: `IF ( MAX(svy_odds_ratios[CI_low]) > 1 || MAX(svy_odds_ratios[CI_high]) < 1, "#1A73E8", "#9AA0A6" )`). This replaces page 2's unweighted odds ratios if you need the space.
8. **Footnote**: "Survey-weighted with WTMEC2YR, SDMVSTRA, SDMVPSU (15 df); Taylor-linearized SEs, logit CIs. Cross-checked against R survey::svyciprop."

## 5. Theme

Save this as `theme.json` and import via View > Themes > Browse for themes:

```json
{
  "name": "NHANES CHD",
  "dataColors": ["#1A73E8", "#BDC1C6", "#5F6368", "#D93025", "#188038"],
  "background": "#FFFFFF",
  "foreground": "#202124",
  "tableAccent": "#1A73E8",
  "textClasses": {
    "title": {"fontSize": 14, "fontFace": "Segoe UI Semibold", "color": "#202124"},
    "label": {"fontSize": 10, "fontFace": "Segoe UI", "color": "#5F6368"}
  }
}
```

Two colors carry meaning everywhere: blue = corrected / high-risk / the thing to look at, grey = original / reference. Keep it that way; a rainbow of model colors hides the point.

## 6. Checks before you screenshot

- Page 1 KPI cards show 5,751 / 232 / 4.0% / 48 with no slicer selected.
- Page 2 funnel ends at 5,751 and the RF bars read 0.999 → 0.858.
- Move the threshold slicer to 0.25 and confirm sensitivity rises and specificity falls.
- Page 3 shows 3.6% (2.8–4.7%) and 8.3 M; the weighted/unweighted toggle on page 1 moves overall prevalence between 3.6% and 4.0%.
- Publish to Power BI Service and use "Publish to web" only if you are comfortable with the data being public (it is de-identified CDC public-use data, so this is generally fine); otherwise export a PDF (File > Export > PDF) for the portfolio.
