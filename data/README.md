# data/

- `raw/` (git-ignored): the six NHANES 2013-2014 CSVs — `demographic.csv`, `diet.csv`, `examination.csv`, `labs.csv`, `medications.csv`, `questionnaire.csv`. Kaggle mirror: "National Health and Nutrition Examination Survey"; official source: [CDC NHANES 2013-2014](https://wwwn.cdc.gov/nchs/nhanes/continuousnhanes/default.aspx?BeginYear=2013).
- `processed/` (git-ignored): written by `notebooks/data_preprocessing.ipynb` (v2, one row per participant).
- `selected_features_v1.csv`: the merged file produced by the **original** (v1) preprocessing (`notebooks/preprocessing_v1_original.ipynb`), with duplicated participants. Keep it here so the audit notebook can reproduce the 15,103 → 5,751 finding. (Rename your old `data/processed/selected_features.csv` to this.)
- `train_split_smote.csv`, `test_split.csv`: the original v1 modeling splits, used by the audit notebook's leakage check and "original setup" results.
