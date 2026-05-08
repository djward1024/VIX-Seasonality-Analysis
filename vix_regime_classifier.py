# ================================================================
# VIX VOLATILITY REGIME CLASSIFIER
# Features: R-engineered (VIX_Daily_Analysis_Full.csv)
# Target:   VIX rises >20% within next 10 trading days (binary)
# Model:    XGBoost with walk-forward cross-validation
#
# Required packages:
#   pip install pandas numpy xgboost scikit-learn matplotlib
# ================================================================

import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import roc_auc_score, classification_report
import matplotlib.pyplot as plt
import warnings
warnings.filterwarnings("ignore")

# ── CONFIG ───────────────────────────────────────────────────────
DATA_PATH   = r"C:\Users\dayla\OneDrive - Radford University\Documents\R Outputs\VIX_Daily_Analysis_Full.csv"
SIGNAL_OUT  = r"C:\Users\dayla\OneDrive - Radford University\Documents\Python Outputs\VIX_Spike_Signals.csv"
CHART_OUT   = r"C:\Users\dayla\OneDrive - Radford University\Documents\Python Outputs\VIX_ML_Dashboard.png"
HORIZON     = 10      # trading days forward
THRESHOLD   = 0.20    # spike = VIX rises >20%
N_SPLITS    = 5       # walk-forward CV folds

# ── 1. LOAD ───────────────────────────────────────────────────────
df = pd.read_csv(DATA_PATH, parse_dates=["date"])
df = df.sort_values("date").reset_index(drop=True)

# ── 2. TARGET VARIABLE ────────────────────────────────────────────
# Max VIX over the next HORIZON days for each row (no lookahead bias:
# feature date t, target uses t+1 through t+HORIZON only)
future_windows = pd.concat(
    [df["vix"].shift(-i) for i in range(1, HORIZON + 1)], axis=1
)
df["vix_forward_max"] = future_windows.max(axis=1)
df["spike"] = ((df["vix_forward_max"] / df["vix"]) - 1 >= THRESHOLD).astype(int)

# ── 3. ADDITIONAL FEATURE ENGINEERING ────────────────────────────
# Lagged signals: give the model memory of where indicators were 1-2 weeks ago
for col in ["term_spread", "vix_rolling_z", "vvix_vix_ratio"]:
    df[f"{col}_lag5"]  = df[col].shift(5)
    df[f"{col}_lag10"] = df[col].shift(10)

FEATURES = [
    "term_spread",
    "vix_mom_20d",
    "vvix_vix_ratio",
    "vix_rolling_z",
    "vix_z_score",
    "term_spread_lag5",    "term_spread_lag10",
    "vix_rolling_z_lag5",  "vix_rolling_z_lag10",
    "vvix_vix_ratio_lag5", "vvix_vix_ratio_lag10",
]

# Show dataset shape and NaN counts before dropping — helps diagnose issues
print(f"Loaded {len(df):,} rows from CSV")
nan_counts = df[FEATURES].isna().sum()
if nan_counts.any():
    print("NaN counts per feature (expected for first ~252 rows of rolling cols):")
    print(nan_counts[nan_counts > 0].to_string())
    print()

# Drop rows with any NaN in features or target
# (first ~252 days from rolling window + last 10 days with no forward data)
model_df = df.dropna(subset=FEATURES + ["spike", "vix_forward_max"]).copy()
model_df = model_df[model_df["vix_forward_max"].notna()].reset_index(drop=True)

if len(model_df) == 0:
    raise SystemExit(
        "ERROR: 0 rows remain after dropping NaNs. "
        "A feature column is likely all-NA — re-run the R script to regenerate the CSV."
    )

X     = model_df[FEATURES].values
y     = model_df["spike"].values
dates = model_df["date"]

spike_rate       = y.mean()
scale_pos_weight = (1 - spike_rate) / spike_rate  # correct for rare events

print(f"Dataset: {len(model_df):,} rows")
print(f"Spike rate: {spike_rate:.1%}  |  scale_pos_weight: {scale_pos_weight:.1f}")

# ── 4. WALK-FORWARD CROSS-VALIDATION ─────────────────────────────
tscv      = TimeSeriesSplit(n_splits=N_SPLITS)
oof_probs = np.full(len(y), np.nan)

xgb_params = dict(
    n_estimators      = 400,
    max_depth         = 4,
    learning_rate     = 0.04,
    subsample         = 0.8,
    colsample_bytree  = 0.8,
    scale_pos_weight  = scale_pos_weight,
    eval_metric       = "auc",
    random_state      = 42,
)

print("\nWalk-forward validation:")
for fold, (train_idx, val_idx) in enumerate(tscv.split(X)):
    model = xgb.XGBClassifier(**xgb_params)
    model.fit(
        X[train_idx], y[train_idx],
        eval_set=[(X[val_idx], y[val_idx])],
        verbose=False,
    )
    oof_probs[val_idx] = model.predict_proba(X[val_idx])[:, 1]
    fold_auc = roc_auc_score(y[val_idx], oof_probs[val_idx])
    n_spikes = y[val_idx].sum()
    print(f"  Fold {fold + 1}: AUC = {fold_auc:.4f}  ({n_spikes} spike events in val set)")

# Only evaluate rows that got an OOF prediction
oof_mask    = ~np.isnan(oof_probs)
overall_auc = roc_auc_score(y[oof_mask], oof_probs[oof_mask])
print(f"\nOverall OOF AUC: {overall_auc:.4f}")
print("\nClassification report (threshold = 0.50):")
print(classification_report(
    y[oof_mask],
    (oof_probs[oof_mask] >= 0.5).astype(int),
    target_names=["No Spike", "Spike"],
    zero_division=0,
))

# ── 5. FINAL MODEL (full dataset) ────────────────────────────────
final_model = xgb.XGBClassifier(**xgb_params)
final_model.fit(X, y, verbose=False)

# ── 6. SIGNAL OUTPUT ─────────────────────────────────────────────
signal_df = model_df[["date", "vix", "term_spread", "vix_rolling_z", "spike"]].copy()
signal_df["spike_probability"] = final_model.predict_proba(X)[:, 1]
signal_df["signal"] = signal_df["spike_probability"].apply(
    lambda p: "SPIKE_RISK" if p >= 0.5 else "CALM"
)

signal_df.to_csv(SIGNAL_OUT, index=False)

latest = signal_df.iloc[-1]
print(f"\nMost recent signal ({latest['date'].date()}):")
print(f"  Signal:            {latest['signal']}")
print(f"  Spike probability: {latest['spike_probability']:.2%}")
print(f"  VIX:               {latest['vix']:.2f}")
print(f"  Term spread:       {latest['term_spread']:.2f}")
print(f"  Rolling Z-score:   {latest['vix_rolling_z']:.2f}")
print(f"\nSignal CSV saved: {SIGNAL_OUT}")

# ── 7. FEATURE IMPORTANCE ────────────────────────────────────────
importance = pd.DataFrame({
    "feature":    FEATURES,
    "importance": final_model.feature_importances_,
}).sort_values("importance", ascending=True)

# ── 8. DIAGNOSTIC CHART ──────────────────────────────────────────
fig, axes = plt.subplots(3, 1, figsize=(14, 13))
fig.suptitle("VIX Volatility Regime Classifier — Diagnostic Dashboard", fontsize=13)

spike_prob = final_model.predict_proba(X)[:, 1]

# Panel 1: VIX with spike events marked
ax1 = axes[0]
ax1.plot(dates, model_df["vix"], color="steelblue", linewidth=0.6, label="VIX")
spike_mask = y == 1
ax1.scatter(
    dates[spike_mask], model_df["vix"].values[spike_mask],
    color="red", s=6, zorder=5, label="Spike event (actual, +10d)"
)
ax1.set_ylabel("VIX")
ax1.set_title("VIX Price with Labeled Spike Events")
ax1.legend(fontsize=8)
ax1.grid(alpha=0.25)

# Panel 2: Model spike probability
ax2 = axes[1]
ax2.fill_between(dates, spike_prob, alpha=0.35, color="firebrick")
ax2.plot(dates, spike_prob, color="firebrick", linewidth=0.5)
ax2.axhline(0.5, linestyle="--", color="black", linewidth=0.8, alpha=0.6,
            label="Decision threshold (0.50)")
ax2.set_ylabel("P(Spike)")
ax2.set_ylim(0, 1)
ax2.set_title("XGBoost Spike Probability Signal")
ax2.legend(fontsize=8)
ax2.grid(alpha=0.25)

# Panel 3: Feature importance
ax3 = axes[2]
ax3.barh(importance["feature"], importance["importance"], color="steelblue", height=0.6)
ax3.set_xlabel("Importance Score")
ax3.set_title("Feature Importance")
ax3.grid(alpha=0.25, axis="x")

plt.tight_layout()
plt.savefig(CHART_OUT, dpi=300, bbox_inches="tight")
plt.show()
print(f"Saved: {CHART_OUT}")
