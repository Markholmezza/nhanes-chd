"""Writes data/oof_predictions.csv for the Shiny app.

Same pipeline as notebooks/nhanes_chd_audit_and_revalidation.ipynb (corrected setup):
one row per participant, participant-level stratified 5-fold CV, mean imputation and
scaling fit inside each fold. Run from the nhanes-chd repo root:
    python nhanes_chd_shiny/precompute_oof.py
Expected: out-of-fold AUC 0.859 (class-weighted) and 0.860 (unweighted).
"""
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

warnings.filterwarnings("ignore")
SEED = 42
ROOT = Path.cwd()
OUT = Path(__file__).resolve().parent / "data"

raw = pd.read_csv(ROOT / "data" / "selected_features_v1.csv").rename(columns={"Blood-Rel Stroke": "StrokeHistory"})
d = raw[raw["disease_status"].notna()].drop_duplicates("SEQN").reset_index(drop=True)
assert d["SEQN"].is_unique and len(d) == 5751

categorical = ["Gender", "Vigorous Work", "Moderate Work", "Diabetes", "Blood-Rel Diabetes", "StrokeHistory"]
numeric = ["Age", "Systolic", "Diastolic", "Platelet Count", "Red-Cell Distribution Width", "Cholesterol",
           "Creatinine", "Glucose", "LDH", "Uric Acid", "Triglycerides", "HDL", "Glycohemoglobin"]
X = d[categorical + numeric].copy()
X[categorical] = X[categorical].astype(str)
y = (d["disease_status"] == "diseased").astype(int).to_numpy()

preprocess = ColumnTransformer([
    ("num", Pipeline([("impute", SimpleImputer(strategy="mean")), ("scale", StandardScaler())]), numeric),
    ("cat", Pipeline([("impute", SimpleImputer(strategy="most_frequent")),
                      ("onehot", OneHotEncoder(handle_unknown="ignore"))]), categorical),
])
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)

out = {"SEQN": d["SEQN"].to_numpy(), "CHD_Flag": y}
for col, weight in [("p_lr_weighted", "balanced"), ("p_lr_unweighted", None)]:
    prob = np.zeros(len(y))
    for tr, te in cv.split(X, y):
        pipe = Pipeline([("prep", preprocess),
                         ("model", LogisticRegression(max_iter=2000, class_weight=weight))])
        pipe.fit(X.iloc[tr], y[tr])
        prob[te] = pipe.predict_proba(X.iloc[te])[:, 1]
    out[col] = prob
    print(f"{col}: out-of-fold AUC {roc_auc_score(y, prob):.3f}")

OUT.mkdir(exist_ok=True)
pd.DataFrame(out).round(6).to_csv(OUT / "oof_predictions.csv", index=False)
