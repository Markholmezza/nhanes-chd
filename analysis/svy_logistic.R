#!/usr/bin/env Rscript
# =============================================================================
# OPTIONAL cross-check in R of notebook sections 12-13 (the main analysis is in Python).
# Survey-weighted analysis of self-reported CHD, NHANES 2013-2014 (U.S. adults 20+)
#
#   1. Cross-check: survey-weighted prevalence with the R `survey` package must
#      reproduce outputs/weighted_prevalence.csv (computed in Python by hand).
#   2. Survey-weighted logistic regression (quasibinomial svyglm) of CHD on the
#      19 predictors, with multiple imputation (mice, m = 20) pooled by Rubin's
#      rules (mitools::MIcombine). Sensitivity: complete cases, no triglycerides.
#
# Run from the repo root:  Rscript analysis/svy_logistic.R
# Packages: install.packages(c("survey", "mice", "mitools"))
#
# Design notes
# - Weight WTMEC2YR (exam weight), strata SDMVSTRA (15), PSU SDMVPSU (2/stratum):
#   15 design degrees of freedom.
# - Domain estimation: the design is built on ALL examined participants and the
#   analysis cohort is selected with subset(), so variances use every PSU.
# - With ~21 coefficients and 15 design df, svyglm's residual df is <= 0, so its
#   default summary() p-values are NaN. Wald CIs here use t with 15 df (complete
#   case) or Rubin's df with df.complete = 15 (multiple imputation).
# =============================================================================

suppressPackageStartupMessages({
  library(survey)
  library(mice)
  library(mitools)
})
options(survey.lonely.psu = "adjust")
set.seed(42)

root <- if (dir.exists("data")) "." else ".."
out_dir <- file.path(root, "outputs")

# ---------------------------------------------------------------- data -------
demo <- read.csv(file.path(root, "data", "raw", "demographic.csv"))[, c("SEQN", "WTMEC2YR", "SDMVSTRA", "SDMVPSU")]
cohort <- read.csv(file.path(out_dir, "nhanes_chd_cohort.csv"), stringsAsFactors = FALSE)
cohort <- cohort[, setdiff(names(cohort), c("WTMEC2YR", "SDMVSTRA", "SDMVPSU"))]

full <- merge(demo, cohort, by = "SEQN", all.x = TRUE)
stopifnot(!anyDuplicated(full$SEQN), nrow(full) == 10175)

# Interview-only participants have WTMEC2YR = 0 and contribute nothing to any
# MEC-weighted estimate; dropping them keeps svydesign() free of infinite 1/w.
full <- full[full$WTMEC2YR > 0, ]
full$dom <- !is.na(full$CHD_Flag)
full$CHD_Flag[is.na(full$CHD_Flag)] <- 0

na_unknown <- function(x) { x[x %in% c("Unknown", "Missing")] <- NA; x }
full$Sex <- factor(full$Sex, levels = c("Female", "Male"))
full$DiabetesSelfReport <- factor(na_unknown(full$DiabetesSelfReport), levels = c("No", "Borderline", "Yes"))
for (v in c("StrokeHistory", "FamilyHistoryDiabetes", "VigorousWork", "ModerateWork")) {
  full[[v]] <- factor(na_unknown(full[[v]]), levels = c("No", "Yes"))
}

des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC2YR, nest = TRUE, data = full)
DF <- degf(des)
cat("Design degrees of freedom:", DF, "\n")
stopifnot(DF == 15)

# ------------------------------------------- 1. prevalence cross-check -------
prev_one <- function(mask) {
  d <- des[mask, ]                                  # domain subset, keeps all PSUs
  r <- svyciprop(~CHD_Flag, d, method = "logit", df = DF)
  ci <- confint(r)
  c(WeightedPrevalence = unname(coef(r)), SE = unname(sqrt(vcov(r))),
    CI_low = unname(ci[1]), CI_high = unname(ci[2]))
}

factor_cols <- c("All adults" = NA, "Age group" = "AgeGroup", "Sex" = "Sex",
                 "Blood pressure" = "BPCategory", "HbA1c" = "HbA1cCategory",
                 "Self-reported diabetes" = "DiabetesSelfReport", "Stroke history" = "StrokeHistory")

py <- read.csv(file.path(out_dir, "weighted_prevalence.csv"), stringsAsFactors = FALSE)
r_rows <- lapply(seq_len(nrow(py)), function(i) {
  col <- factor_cols[[py$Factor[i]]]
  mask <- if (is.na(col)) full$dom else full$dom & (as.character(full[[col]]) %in% py$Level[i])
  data.frame(Factor = py$Factor[i], Level = py$Level[i], t(prev_one(mask)))
})
r_prev <- do.call(rbind, r_rows)
cmp <- merge(py[, c("Factor", "Level", "WeightedPrevalence", "SE", "CI_low", "CI_high")],
             r_prev, by = c("Factor", "Level"), suffixes = c("_python", "_R"))
diffs <- with(cmp, c(
  prevalence = max(abs(WeightedPrevalence_python - WeightedPrevalence_R)),
  se         = max(abs(SE_python - SE_R)),
  ci         = max(abs(c(CI_low_python - CI_low_R, CI_high_python - CI_high_R)))))
print(round(diffs, 5))
write.csv(cmp, file.path(out_dir, "svy_prevalence_crosscheck.csv"), row.names = FALSE)
if (diffs["prevalence"] > 1e-4 || diffs["se"] > 5e-4 || diffs["ci"] > 2e-3) {
  stop("R survey estimates do not match outputs/weighted_prevalence.csv - investigate before continuing.")
}
cat("Cross-check passed: R `survey` reproduces the Python weighted prevalences.\n\n")

# --------------------------------------- 2. survey-weighted logistic ---------
num_vars <- c("Age", "SystolicBP", "DiastolicBP", "TotalCholesterol", "HDL", "Triglycerides", "Glucose",
              "HbA1c", "Creatinine", "UricAcid", "LDH", "PlateletCount", "RDW")
cat_vars <- c("Sex", "VigorousWork", "ModerateWork", "DiabetesSelfReport", "FamilyHistoryDiabetes", "StrokeHistory")

# Standardize numeric predictors on the analysis cohort, so ORs are per 1 SD
for (v in num_vars) {
  m <- mean(full[[v]][full$dom], na.rm = TRUE); s <- sd(full[[v]][full$dom], na.rm = TRUE)
  full[[paste0(v, "_z")]] <- (full[[v]] - m) / s
}
# Rebuild the design so it contains the standardized predictors (svydesign stores a copy of the data)
des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC2YR, nest = TRUE, data = full)
z_vars <- paste0(num_vars, "_z")
rhs <- c(z_vars, cat_vars)
fml <- as.formula(paste("CHD_Flag ~", paste(rhs, collapse = " + ")))

wald_table <- function(est, se, df, model) {
  t <- qt(0.975, df)
  data.frame(Model = model, Term = names(est), OddsRatio = exp(est),
             CI_low = exp(est - t * se), CI_high = exp(est + t * se),
             p = 2 * pt(-abs(est / se), df), row.names = NULL)
}

# 2a. Multiple imputation (primary). Impute within the analysis cohort, using the
#     outcome and the weight as predictors (outcome must be in the imputation model).
imp_cols <- c(z_vars, cat_vars, "CHD_Flag", "WTMEC2YR")
dom_dat <- full[full$dom, imp_cols]
cat("Missing values in the cohort before imputation:\n"); print(colSums(is.na(dom_dat))[colSums(is.na(dom_dat)) > 0])
imp <- mice(dom_dat, m = 20, maxit = 10, printFlag = FALSE, seed = 42)

imp_frames <- lapply(seq_len(imp$m), function(k) {
  f <- full
  f[f$dom, imp_cols] <- complete(imp, k)
  f
})
fits <- lapply(imp_frames, function(f) {
  d <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC2YR, nest = TRUE, data = f)
  svyglm(fml, design = subset(d, dom), family = quasibinomial())
})
pooled <- MIcombine(fits, df.complete = DF)
mi_tab <- wald_table(coef(pooled), sqrt(diag(vcov(pooled))), pooled$df, "Survey-weighted, multiple imputation (m=20)")

# 2b. Complete-case sensitivity analysis without triglycerides (fasting subsample)
fml_cc <- update(fml, . ~ . - Triglycerides_z)
fit_cc <- svyglm(fml_cc, design = subset(des, dom), family = quasibinomial())
cc_tab <- wald_table(coef(fit_cc), sqrt(diag(vcov(fit_cc))), DF, "Survey-weighted, complete cases, no triglycerides")
cc_rows <- full$dom & complete.cases(full[, c(setdiff(z_vars, "Triglycerides_z"), cat_vars)])
cat("Complete-case n:", sum(cc_rows), " cases:", sum(full$CHD_Flag[cc_rows]), "\n")

or_tab <- rbind(mi_tab, cc_tab)
or_tab <- or_tab[or_tab$Term != "(Intercept)", ]
or_tab$Term <- sub("_z$", " (per SD)", or_tab$Term)
num_cols <- sapply(or_tab, is.numeric)
or_tab[num_cols] <- lapply(or_tab[num_cols], function(x) signif(x, 4))
write.csv(or_tab, file.path(out_dir, "svy_odds_ratios_R.csv"), row.names = FALSE)
# Complete-case estimates should match outputs/svy_odds_ratios.csv (Python) to ~3 decimals; MI estimates
# differ slightly because the imputation models differ (mice pmm/logreg vs IterativeImputer).

cat("\nSurvey-weighted odds ratios (multiple imputation), sorted by p:\n")
print(head(mi_tab[mi_tab$Term != "(Intercept)", ][order(mi_tab$p[mi_tab$Term != "(Intercept)"]), ], 10), digits = 3)
cat("\nWrote outputs/svy_prevalence_crosscheck.csv and outputs/svy_odds_ratios_R.csv\n")
