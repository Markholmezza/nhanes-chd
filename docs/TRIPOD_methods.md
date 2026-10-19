# Methods (TRIPOD-style summary)

Prediction model development with internal validation, reported along the TRIPOD checklist (Collins et al., 2015). Item numbers in brackets.

## Source of data [4a, 4b]
CDC National Health and Nutrition Examination Survey (NHANES) 2013-2014, a cross-sectional, stratified multistage probability sample of the U.S. civilian non-institutionalized population. Six public-use files were joined on the participant identifier `SEQN`: demographics, dietary, examination, laboratory, medications, questionnaire. One row per participant; the medications file (one row per prescription) was collapsed to a per-participant count before joining, and uniqueness of `SEQN` was asserted after every merge.

## Participants [5a-c]
Adults aged 20-80 who answered the coronary heart disease question (n = 5,751 of 10,175 participants). No other exclusions. 179 of them were interviewed but not examined (exam weight 0); they are kept in the prediction models (labs imputed) and drop out of survey-weighted estimates.

## Outcome [6a, 6b]
`MCQ160C`, "Has a doctor or other health professional ever told you that you had coronary heart disease?" (1 = yes, 2 = no; refused/don't know treated as missing). 232 events (4.0%). Self-reported, lifetime, and ascertained at the same visit as the predictors, so the model is **diagnostic/cross-sectional, not prognostic**. Outcome assessment was not blinded to predictors (self-report precedes the exam).

## Predictors [7a, 7b]
The 19 variables of the replicated paper: sex, age; systolic and diastolic blood pressure (first reading); total cholesterol, HDL, triglycerides, glucose, HbA1c, creatinine, uric acid, LDH, platelet count, red-cell distribution width; vigorous work activity, moderate work activity, self-reported diabetes, family history of diabetes, and **own** stroke history (`MCQ160F`, mislabeled "blood-relative stroke" in the original analysis). Numeric predictors were z-scored; categorical predictors one-hot encoded.

## Sample size [8]
232 events and 31 candidate parameters after encoding (about 7.5 events per parameter); for the survey-weighted model with 21 parameters, about 11 events per parameter. The modest ratio is why penalized and unpenalized logistic regressions are both reported and why calibration slope is checked.

## Missing data [9]
Triglycerides were missing for 55.7% because NHANES measures them only in the morning fasting subsample (missing at random by design); blood pressure 11.4%, chemistry panel about 7.7%, blood count 6.5%. Primary prediction analysis: mean imputation for numeric and mode for categorical variables, fit inside each cross-validation fold. Sensitivity analyses (all inside folds): mean imputation with missing-indicator columns; multiple imputation by chained equations (`IterativeImputer`, single draw for prediction); dropping triglycerides; complete cases only (n = 2,335, 97 events). Survey-weighted regression: multiple imputation with `mice` (m = 20, outcome and weight in the imputation model), pooled by Rubin's rules.

## Statistical analysis [10a-d]
- **Models:** logistic regression (L2, C = 1), random forest (300 trees, min leaf 5), KNN (k = 15). Class imbalance handled by class weighting, compared with SMOTE applied inside each training fold; an unweighted logistic regression was fit for calibrated risks.
- **Internal validation:** stratified 5-fold cross-validation at the participant level, with all preprocessing (imputation, scaling, encoding, resampling) fit on the training folds only. Out-of-fold predictions were pooled for performance measures.
- **Performance:** discrimination by AUC with 1,000-sample bootstrap 95% CIs and a paired bootstrap for model differences; calibration by decile calibration curve, calibration-in-the-large (mean predicted vs observed), calibration slope and Brier score; clinical usefulness by decision curve analysis (net benefit, thresholds 1-30%); sensitivity, specificity and PPV across thresholds.
- **Population estimates:** survey-weighted prevalence with exam weights `WTMEC2YR`, strata `SDMVSTRA` and PSUs `SDMVPSU` (15 design df), domain estimation over the full design, Taylor-linearized variance (verified against a stratified jackknife and against R `survey`), logit-transformed 95% CIs with t(15).
- **Associations:** survey-weighted logistic regression: weighted maximum likelihood with design-based sandwich variance (score totals by stratum and PSU; the estimator used by R `survey::svyglm`), domain estimation, odds ratios per SD or per category, Wald CIs with t on 15 design df. Missing predictors handled by multiple imputation (m = 20, posterior draws, outcome in the imputation model), pooled by Rubin's rules with Barnard-Rubin df; complete-case model without triglycerides as sensitivity analysis. Sandwich SEs were verified against a stratified delete-one-PSU jackknife (median ratio 1.02). The odds ratios in notebook section 9 come from an L2-penalized, unweighted prediction model and are not the inferential ones.

## Results summary [13-16]
| | Value |
|---|---|
| Participants / events | 5,751 / 232 (4.0%) |
| AUC, logistic regression | 0.859 (0.837-0.881) |
| AUC, random forest | 0.858 (0.835-0.879); paired difference vs LR +0.001 (-0.011 to +0.012) |
| AUC, KNN | 0.745 (0.711-0.780) |
| Calibration, unweighted LR | mean predicted 4.05% vs observed 4.03%, slope 0.94, Brier 0.035 (no-skill 0.039) |
| Calibration, class-weighted LR | mean predicted 30.1%, slope 0.78, Brier 0.151 |
| Decision curve | unweighted LR beats treat-all and treat-none at every threshold 1-30%; class-weighted LR is below treat-none from 5% |
| Missing-data sensitivity | AUC 0.857-0.860 across all five strategies |
| U.S. adult CHD prevalence (weighted) | 3.6% (2.8-4.7%), about 8.3 million adults |
| Survey-weighted adjusted ORs (MI) | age 3.59/SD (2.72-4.74); family history of diabetes 1.80 (1.39-2.34); HbA1c 1.30/SD (1.02-1.67); RDW 1.28/SD (1.08-1.51); triglycerides 1.34/SD (1.08-1.66); prior stroke 2.14 (1.02-4.49); total cholesterol 0.59/SD (0.41-0.86); diastolic BP 0.84/SD (0.74-0.95) |

## Limitations [18]
Cross-sectional design with a self-reported lifetime outcome: predictors were measured after diagnosis, so treatment can reverse associations (lower cholesterol in people with CHD, consistent with statins). Internal validation only; NHANES 2015-2016 or 2017-2020 would provide temporal external validation. No PSO-ANN re-implementation.

## Interpretation [19, 20]
After removing duplicated participants, flexible models add nothing over logistic regression. The model ranks risk reasonably (AUC 0.86), but it identifies people who already have a CHD diagnosis rather than predicting future events, so it is a demonstration of method, not a screening tool.
