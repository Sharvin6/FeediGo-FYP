#!/usr/bin/env python3
"""
make_synth_and_train.py

Usage:
  python make_synth_and_train.py --n 8000 \
    --out_csv training_data.csv \
    --out_model functions/src/model/matching_tree.json

Generates synthetic pairs, trains a DecisionTree, and exports a JSON model
compatible with the Cloud Function runtime.
"""
import argparse
import json
from pathlib import Path
from datetime import datetime, timedelta, timezone
import math
import random
import uuid

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.tree import DecisionTreeClassifier, _tree
from sklearn.metrics import roc_auc_score

# -----------------------------
# Config / taxonomy
# -----------------------------
FOOD_TYPES = [
    "Cooked Meals",
    "Fresh Produce",
    "Bakery",
    "Packaged / Canned",
    "Beverage",
    "Frozen / Chilled",
    "Dry Goods",
]

CENTER_LAT = 3.1390
CENTER_LNG = 101.6869

# -----------------------------
# Utility functions
# -----------------------------
def rnd_coord(center_lat, center_lng, radius_km=25.0):
    """Return a random lat/lng within approx radius_km of center."""
    r = radius_km / 111.0
    u, v = random.random(), random.random()
    w = r * math.sqrt(u)
    t = 2 * math.pi * v
    lat = center_lat + w * math.cos(t)
    lng = center_lng + (w * math.sin(t)) / math.cos(math.radians(center_lat))
    return lat, lng

def haversine_km(a_lat, a_lng, b_lat, b_lng):
    R = 6371.0
    dlat = math.radians(b_lat - a_lat)
    dlng = math.radians(b_lng - a_lng)
    s = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(a_lat))
        * math.cos(math.radians(b_lat))
        * math.sin(dlng / 2) ** 2
    )
    return 2 * R * math.atan2(math.sqrt(s), math.sqrt(1 - s))

def qty_to_grams(val: float, unit: str):
    """Convert kg/g to grams (returns None for unknown/other units)."""
    if unit is None:
        return None
    u = str(unit).lower()
    if u in ["g", "gram", "grams"]:
        return float(val)
    if u in ["kg", "kilogram", "kilograms"]:
        return float(val) * 1000.0
    return None

def unit_category(unit: str):
    """Return 'mass' for kg/g, 'count' for other textual units, or None."""
    if not unit:
        return None
    u = str(unit).lower()
    if u in ["g", "gram", "grams", "kg", "kilogram", "kilograms"]:
        return "mass"
    # treat the rest as count-like (plates, boxes, bottles, etc.)
    return "count"

def clip(n, lo, hi):
    return max(lo, min(hi, n))

# -----------------------------
# Synthetic data generation
# -----------------------------
def sample_request():
    req_id = str(uuid.uuid4())[:8]
    food = random.choice(FOOD_TYPES[:-1])
    if random.random() < 0.75:
        unit, val = "kg", round(random.uniform(0.5, 20.0), 1)
    else:
        unit, val = "grams", int(random.uniform(200, 4000))
    need_days = int(random.uniform(0, 10))
    need_dt = (
        datetime.now(timezone.utc) + timedelta(days=need_days)
    ).replace(hour=23, minute=59, second=59, microsecond=0)
    lat, lng = rnd_coord(CENTER_LAT, CENTER_LNG, radius_km=25.0)
    created = datetime.now(timezone.utc) - timedelta(days=random.uniform(0, 7))
    return {
        "request_id": req_id,
        "requestedFoodType": food,
        "qtyValue": val,
        "qtyUnit": unit,
        "needByDate": need_dt,
        "lat": lat,
        "lng": lng,
        "createdAt": created,
    }

def sample_donation():
    don_id = str(uuid.uuid4())[:8]
    food = random.choice(FOOD_TYPES[:-1])
    if random.random() < 0.75:
        unit, val = "kg", round(random.uniform(0.5, 25.0), 1)
    else:
        unit, val = "grams", int(random.uniform(200, 6000))
    off_text = f"{val} {unit}"
    exp_days = int(random.uniform(-2, 7))
    exp_dt = (
        datetime.now(timezone.utc) + timedelta(days=exp_days)
    ).replace(hour=23, minute=59, second=59, microsecond=0)
    lat, lng = rnd_coord(CENTER_LAT, CENTER_LNG, radius_km=25.0)
    created = datetime.now(timezone.utc) - timedelta(days=random.uniform(0, 10))
    return {
        "donation_id": don_id,
        "foodTypeLabel": food,
        "quantity_text": off_text,
        "expiryAt": exp_dt,
        "lat": lat,
        "lng": lng,
        "createdAt": created,
    }

# -----------------------------
# Pair + label logic
# -----------------------------
def qty_bucket_from_ratio(r):
    """Coarse bucket used to help tree splits.
    r == -1 => 'unknown'
    r < 0.5 => 'too_small'
    0.5 <= r < 0.8 => 'small'
    0.8 <= r <= 3.0 => 'balanced'
    r > 3.0 => 'too_large'
    """
    try:
        if r is None:
            return "unknown"
        if not (isinstance(r, (int, float)) and math.isfinite(r)):
            return "unknown"
    except Exception:
        return "unknown"

    if r < 0:
        return "unknown"
    if r < 0.5:
        return "too_small"
    if r < 0.8:
        return "small"
    if r <= 3.0:
        return "balanced"
    return "too_large"

def make_pair_and_label(req, don):
    food_type = req["requestedFoodType"]
    req_g = qty_to_grams(req["qtyValue"], req["qtyUnit"])

    # parse donation textual quantity (e.g., "2.5 kg")
    try:
        m = str(don["quantity_text"]).strip().split()
        off_val, off_unit = float(m[0]), m[1]
    except Exception:
        off_val, off_unit = (None, None)

    off_g = qty_to_grams(off_val, off_unit) if off_val is not None else None

    # numeric ratio when both mass-known; otherwise -1
    qty_ratio = -1.0
    if req_g is not None and off_g is not None and req_g > 0:
        qty_ratio = clip(off_g / req_g, 0.0, 10.0)

    # distance
    dist_km = clip(haversine_km(req["lat"], req["lng"], don["lat"], don["lng"]), 0.0, 200.0)

    # dates
    today_eod = datetime.now(timezone.utc).replace(hour=23, minute=59, second=59, microsecond=0)
    need_eod, exp_eod = req["needByDate"], don["expiryAt"]

    expiry_gap_days = None
    if need_eod and exp_eod:
        expiry_gap_days = clip(round((exp_eod - need_eod).total_seconds() / 86400.0), -14, 14)

    donation_fresh_days_left = clip(round((exp_eod - today_eod).total_seconds() / 86400.0), -14, 30)
    req_need_days_from_now = clip(round((need_eod - today_eod).total_seconds() / 86400.0), -7, 30)

    # Unit compatibility
    req_cat = unit_category(req.get("qtyUnit"))
    off_cat = unit_category(off_unit)
    unit_compatible = 0
    if req_cat == "mass" and off_cat == "mass":
        unit_compatible = 1
    elif req_cat == "count" and off_cat == "count":
        if (str(req.get("qtyUnit") or "").strip().lower() ==
            str(off_unit or "").strip().lower()):
            unit_compatible = 1

    # qty bucket (categorical coarse)
    qb = qty_bucket_from_ratio(qty_ratio)

    # scoring to generate probabilistic label (same logic as before)
    score = 0.0
    score += 2.5 if (food_type == don["foodTypeLabel"]) else -1.5
    if qty_ratio == -1:
        score += -0.6
    else:
        if 0.9 <= qty_ratio <= 1.5:
            score += 1.8
        elif 0.8 <= qty_ratio <= 3.0:
            score += 1.0
        elif (0.5 <= qty_ratio < 0.8) or (3.0 < qty_ratio <= 5.0):
            score += 0.5
        else:
            score += -1.0

    if expiry_gap_days is not None:
        if expiry_gap_days >= 0:
            score += 1.0
        elif -2 <= expiry_gap_days < 0:
            score += 0.2
        else:
            score += -1.2

    if donation_fresh_days_left >= 3:
        score += 0.3
    elif donation_fresh_days_left >= 1:
        score += 0.1
    else:
        score += -0.2

    if dist_km <= 3:
        score += 0.6
    elif dist_km <= 7:
        score += 0.3
    elif dist_km <= 15:
        score += 0.1
    else:
        score += -0.4

    # small boost if units are compatible (makes same-unit matches more likely)
    if unit_compatible:
        score += 0.5

    score += random.normalvariate(0, 0.25)
    p = 1.0 / (1.0 + math.exp(-score))
    y = 1 if random.random() < p else 0

    return {
        "pair_id": f"{req['request_id']}_{don['donation_id']}",
        "donation_id": don["donation_id"],
        "request_id": req["request_id"],
        "y": y,
        "food_type": food_type,
        "req_qty_value": req["qtyValue"],
        "req_qty_unit": req["qtyUnit"],
        "off_qty_text": don["quantity_text"],
        "req_qty_g": req_g if req_g else "",
        "off_qty_g": off_g if off_g else "",
        "qty_ratio": qty_ratio,
        "qty_bucket": qb,
        "unit_compatible": unit_compatible,
        "distance_km": round(dist_km, 3),
        "expiry_gap_days": expiry_gap_days if expiry_gap_days is not None else "",
        "donation_fresh_days_left": donation_fresh_days_left,
        "req_need_days_from_now": req_need_days_from_now,
        "window_overlap_min": random.randint(0, 120),
        "has_coords": 1,
        "created_at": req["createdAt"].isoformat(),
    }

# -----------------------------
# Training
# -----------------------------
def train_and_export(csv_path: Path, out_json: Path):
    df = pd.read_csv(csv_path)

    # ensure columns exist (robust to older CSV)
    for col, default in {
        "qty_ratio": -1,
        "distance_km": 999,
        "expiry_gap_days": -14,
        "window_overlap_min": 0,
        "has_coords": 0,
        "unit_compatible": 0,
        "qty_bucket": "unknown",
    }.items():
        if col not in df.columns:
            print(f"[train] WARNING: column '{col}' missing — creating with default={default}")
            df[col] = default

    # numeric conversions
    df["qty_ratio"] = pd.to_numeric(df["qty_ratio"], errors="coerce").fillna(-1)
    df["distance_km"] = pd.to_numeric(df["distance_km"], errors="coerce").fillna(999)
    df["expiry_gap_days"] = pd.to_numeric(df["expiry_gap_days"], errors="coerce").fillna(-14)
    df["window_overlap_min"] = pd.to_numeric(df["window_overlap_min"], errors="coerce").fillna(0)
    df["has_coords"] = pd.to_numeric(df["has_coords"], errors="coerce").fillna(0)
    df["unit_compatible"] = pd.to_numeric(df["unit_compatible"], errors="coerce").fillna(0)

    # sanitize categorical fields
    df["food_type"] = df["food_type"].astype(str)
    df["food_type"] = np.where(df["food_type"].isin(FOOD_TYPES), df["food_type"], "Other")
    df["qty_bucket"] = df["qty_bucket"].astype(str)

    # Balance classes by undersampling majority
    pos, neg = df[df["y"] == 1], df[df["y"] == 0]
    n_pos, n_neg = len(pos), len(neg)
    print(f"[train] positives={n_pos} negatives={n_neg}")

    if n_pos == 0 or n_neg == 0:
        df_bal = df.copy()
        print("[train] one class missing — skipping resampling")
    else:
        n = min(n_pos, n_neg)
        pos_down = pos.sample(n=n, random_state=42)
        neg_down = neg.sample(n=n, random_state=42)
        df_bal = pd.concat([pos_down, neg_down]).sample(frac=1.0, random_state=42).reset_index(drop=True)
        print(f"[train] balanced dataset -> {len(df_bal)} rows (pos={n}, neg={n})")

    # numeric features
    X_num = df_bal[["qty_ratio", "distance_km", "expiry_gap_days", "window_overlap_min", "has_coords", "unit_compatible"]]

    # categorical dummies: food_type + qty_bucket
    X_cat_food = pd.get_dummies(df_bal["food_type"], prefix="food_type")
    X_cat_qb = pd.get_dummies(df_bal["qty_bucket"], prefix="qty_bucket")

    # combine
    X = pd.concat([X_num, X_cat_food, X_cat_qb], axis=1)
    y = df_bal["y"].astype(int)

    # train/test split
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, stratify=y, random_state=42)

    clf = DecisionTreeClassifier(
        max_depth=6,
        min_samples_leaf=50,
        class_weight="balanced",
        random_state=42,
    )
    clf.fit(Xtr, ytr)
    auc = roc_auc_score(yte, clf.predict_proba(Xte)[:, 1])
    print(f"[train] AUC: {auc:.3f}")

    feature_names = list(X.columns)

    # Build JSON tree in runtime-friendly format
    def build_node(tree, node_id=0):
        if tree.feature[node_id] == _tree.TREE_UNDEFINED:
            counts = tree.value[node_id][0]
            p1 = float(counts[1] / counts.sum()) if counts.sum() > 0 else 0.0
            return {"leaf": True, "p1": p1}
        feat_idx = tree.feature[node_id]
        thr = float(tree.threshold[node_id])
        feat_name = feature_names[feat_idx]
        # map categorical dummies that start with prefix into runtime "food_type==Label" etc.
        if feat_name.startswith("food_type_"):
            label = feat_name[len("food_type_") :]
            feature = f"food_type=={label.replace('_', ' ')}"
        elif feat_name.startswith("qty_bucket_"):
            label = feat_name[len("qty_bucket_") :]
            # treat as a dummy, runtime won't produce this exact dummy; keep as-is.
            feature = feat_name
        else:
            feature = feat_name
        left_id = tree.children_left[node_id]
        right_id = tree.children_right[node_id]
        return {
            "leaf": False,
            "feature": feature,
            "threshold": thr,
            "left": build_node(tree, left_id),
            "right": build_node(tree, right_id),
        }

    tree_json = build_node(clf.tree_)
    out = {
        "model_type": "decision_tree",
        "features": feature_names,
        "categories_food_type": [ft for ft in FOOD_TYPES if ft != "Other"],
        "tree": tree_json,
        "metrics": {"auc": float(auc)},
    }

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(out, indent=2))
    print(f"[train] wrote model → {out_json}")

# -----------------------------
# Main
# -----------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=6000)
    ap.add_argument("--out_csv", type=str, default="training_data.csv")
    ap.add_argument("--out_model", type=str, default="functions/src/model/matching_tree.json")
    args = ap.parse_args()

    random.seed(42)
    np.random.seed(42)

    rows = []
    for _ in range(args.n):
        req, don = sample_request(), sample_donation()
        # keep some bias to make dataset learn food-type matching
        if random.random() < 0.6:
            don["foodTypeLabel"] = req["requestedFoodType"]
        rows.append(make_pair_and_label(req, don))

    df = pd.DataFrame(rows)
    df.to_csv(args.out_csv, index=False)
    print(f"[gen] wrote {len(df)} rows → {args.out_csv}")

    train_and_export(Path(args.out_csv), Path(args.out_model))

if __name__ == "__main__":
    main()
