# NHANES CHD Explorer (R Shiny)

An interactive companion to the [nhanes-chd](https://github.com/Markholmezza/nhanes-chd) audit:
5,751 adults from CDC NHANES 2013-2014, 232 with self-reported coronary heart disease.

| Tab | What it does |
|---|---|
| Outreach planner | Pick an outreach capacity or a risk cutoff; see adults flagged, cases reached (sensitivity), PPV, lift, specificity, a confusion matrix, the cumulative gains curve and decile calibration, all computed live from 5-fold out-of-fold predictions. |
| Population prevalence | Filter by age, sex, blood pressure, HbA1c, diabetes and stroke history; get survey-weighted CHD prevalence with Taylor-linearized logit 95% CIs (R `survey`), U.S. adults represented, and a breakdown chart that greys out unstable estimates (fewer than 30 adults or 10 cases). |
| Data quality checks | Eleven edit checks (ID uniqueness, label consistency, range and cross-field checks, survey weights) run on the analysis file, each with a severity and a drill-down to the flagged records, plus a missingness chart. |

## Run it

```r
install.packages(c("shiny", "bslib", "survey", "ggplot2", "DT"))
shiny::runApp("shiny_app")   # or open app.R in RStudio and click Run App
```

## Expected numbers (sanity checks)

- Outreach planner, class-weighted model, capacity 10%: 575 adults flagged, 116 of 232 cases reached (50.0%), lift 5.0; out-of-fold AUC 0.859.
- Risk threshold 0.40, class-weighted: sensitivity 86.2%, specificity 71.7%, 30.7% flagged.
- Population prevalence, no filters: 3.7% (95% CI 2.8% to 4.7%), 5,572 examined adults, about 228.7 million U.S. adults.
- Age 60+: 10.7% (8.4% to 13.6%).
- Data quality: DQ-06 flags 34 adults with diastolic BP below 30 mmHg (27 recorded as 0); DQ-11 flags 179 adults without an exam weight.

## Files

- `app.R`: the app.
- `data/nhanes_chd_cohort.csv`: analysis file from the audit notebook (one row per participant).
- `data/oof_predictions.csv`: out-of-fold logistic regression predictions, written by `precompute_oof.py`.

## Deploy (optional)

Create a free account at shinyapps.io, then:

```r
install.packages("rsconnect")
rsconnect::setAccountInfo(name = "<account>", token = "<token>", secret = "<secret>")
rsconnect::deployApp("shiny_app", appName = "nhanes-chd-explorer")
```

NHANES is cross-sectional and CHD is a self-reported past diagnosis; the outreach view illustrates a capacity-based decision framework, not a screening tool ready to deploy.
