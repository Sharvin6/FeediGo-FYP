// functions/src/index.ts

// Gen 2 HTTPS (callable) & global opts
import { onCall } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
// Legacy import ONLY to read functions:config()
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// ---- Load trained model JSON ----
// Requires tsconfig "resolveJsonModule": true
import modelJson from "./model/matching_tree.json";

import { ModelJson, TreeNode } from "./model/model";

admin.initializeApp();
setGlobalOptions({ region: "us-central1" });

/* ===========================
   Utilities
=========================== */

function toDate(v: unknown): Date | null {
  if (!v) return null;
  // Firestore Timestamp duck-typing
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const ts = v as any;
  if (ts?.toDate && typeof ts.toDate === "function") return ts.toDate();
  if (v instanceof Date) return v;
  if (typeof v === "string") {
    const d = new Date(v);
    return Number.isFinite(d.getTime()) ? d : null;
  }
  return null;
}

function safeNum(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function clamp(n: number, lo: number, hi: number) {
  return Math.max(lo, Math.min(hi, n));
}

function deg2rad(d: number) {
  return (d * Math.PI) / 180;
}

function haversineKm(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6371; // km
  const dLat = deg2rad(bLat - aLat);
  const dLng = deg2rad(bLng - aLng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(deg2rad(aLat)) * Math.cos(deg2rad(bLat)) *
    Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
}

type ParsedQty =
  | { ok: false }
  | { ok: true; value: number; unit: string; cat: "mass" | "count" };

function parseQuantity(text?: string | null): ParsedQty {
  if (!text) return { ok: false };
  const m = String(text).toLowerCase().trim().match(/([\d.,]+)\s*([a-zA-Z]+)/);
  if (!m) return { ok: false };
  const value = Number(m[1].replace(",", "."));
  if (!Number.isFinite(value)) return { ok: false };
  const unit = m[2];

  const mass = ["g", "gram", "grams", "kg", "kilogram", "kilograms"];
  const count = [
    "plate", "plates",
    "bottle", "bottles",
    "box", "boxes",
    "pack", "packs",
    "item", "items",
    "pc", "pcs", "piece", "pieces"
  ];

  if (mass.includes(unit)) return { ok: true, value, unit, cat: "mass" };
  if (count.includes(unit)) return { ok: true, value, unit, cat: "count" };
  return { ok: false };
}

function gramsFrom(value: number, unit: string): number | null {
  const u = unit.toLowerCase();
  if (u === "g" || u === "gram" || u === "grams") return value;
  if (u === "kg" || u === "kilogram" || u === "kilograms") return value * 1000;
  return null;
}

/* ===========================
   Quantity ranking helpers (for sorting)
========================== */

// Lower is better
function qtyBucket(r: number | null | undefined): number {
  // 0 = ideal, 1 = acceptable, 2 = poor, 3 = unknown (worst)
  if (typeof r !== "number" || !Number.isFinite(r) || r < 0) return 3; // unknown
  if (r >= 0.8 && r <= 3.0) return 0;                                   // ideal
  if ((r >= 0.5 && r < 0.8) || (r > 3.0 && r <= 5.0)) return 1;         // acceptable
  return 2;                                                             // poor
}

function qtyDistanceFromIdeal(r: number | null | undefined): number {
  if (typeof r !== "number" || !Number.isFinite(r) || r < 0) return 9999; // unknown = worst
  return Math.abs(r - 1); // closer to 1.0 is better
}

/* ===========================
   Types
========================== */

type MatchRequest = {
  requestedFoodType?: string | null;

  qtyValue?: number | null;
  qtyUnit?: string | null; // request unit (kg/g/plates/boxes/etc.)
  qtyNeed?: string | null; // optional legacy text

  // (No longer required) need-by date
  needByDate?: string | null;

  // optional coarse filter
  expiryPrefHours?: number | null;

  // requester's location
  address?: string | null;
  lat?: number | null;
  lng?: number | null;

  windowStartMins?: number | null;
  windowEndMins?: number | null;

  topK?: number | null;
};

type DonationDoc = {
  title?: string;
  foodName?: string;
  foodTypeLabel?: string;
  quantity?: string;
  servings?: number;
  status?: string;
  expiryAt?: admin.firestore.Timestamp | Date | null;
  pickupInfo?: {
    address?: string;
    lat?: number;
    lng?: number;
    time?: admin.firestore.Timestamp | Date | null;
    endTime?: admin.firestore.Timestamp | Date | null;
  } | null;
};

/* ===========================
   Load trained model
========================== */

const MODEL: ModelJson = modelJson as unknown as ModelJson;

// Match training defaults when a feature is missing
function defaultFor(feat: string) {
  if (feat === "qty_ratio") return -1;
  if (feat === "distance_km") return 999;
  if (feat === "expiry_gap_days") return -14;
  if (feat === "window_overlap_min") return 0;
  if (feat === "has_coords") return 0;
  if (feat === "unit_compatible") return 0;
  // default for dummy one-hot fields (qty_bucket_*, qty_bucket_unknown, etc.)
  if (feat.startsWith("qty_bucket_")) return 0;
  return 0;
}

function predictWithTree(node: TreeNode, features: Record<string, number | string>): number {
  while (!node.leaf) {
    const feat = node.feature;

    // categorical split: "food_type==Cooked Meals"
    if (feat.startsWith("food_type==")) {
      const want = feat.substring("food_type==".length);
      const val = String(features["food_type"] ?? "");
      const cond = val === want ? 1 : 0;
      node = cond <= node.threshold ? node.left : node.right;
      continue;
    }

    const vRaw = features[feat];
    const v = (typeof vRaw === "number" && Number.isFinite(vRaw)) ? vRaw : defaultFor(feat);
    node = v <= node.threshold ? node.left : node.right;
  }
  return node.p1;
}

/* ===========================
   Cloud Function (Gen 2)
========================== */

export const matchDonations = onCall(async (request) => {
  try {
    const data = request.data as MatchRequest;

    const now = new Date();
    const db = admin.firestore();

    const reqFood = (data.requestedFoodType ?? "").toString().trim();

    // ---- Request qty & unit (for coverage) ----
    const reqQtyVal = safeNum(data.qtyValue);
    const reqQtyUnit = (data.qtyUnit ?? "").toString().trim() || null;
    const reqQtyParsed = parseQuantity(
      reqQtyVal != null && reqQtyUnit ? `${reqQtyVal} ${reqQtyUnit}` : null
    );

    // ---- Need-by = TODAY EOD (your UX) ----
    const todayEOD = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);

    // ---- Requester location ----
    let reqLat = safeNum(data.lat);
    let reqLng = safeNum(data.lng);
    const requestAddress = (data.address ?? "").toString().trim();

    // If no coords but we have address, try to geocode using LocationIQ key if configured
    if ((reqLat == null || reqLng == null) && requestAddress) {
      try {
        const key =
          (functions.config()?.locationiq?.key as string | undefined) ??
          process.env.LOCATIONIQ_KEY;
        if (key) {
          const url =
            `https://us1.locationiq.com/v1/search?key=${encodeURIComponent(key)}` +
            `&q=${encodeURIComponent(requestAddress)}&format=json&limit=1`;
          const res = await fetch(url).catch(() => null);
          if (res && res.ok) {
            const arr = (await res.json()) as Array<{ lat: string; lon: string }>;
            const lat = Number(arr?.[0]?.lat);
            const lng = Number(arr?.[0]?.lon);
            if (Number.isFinite(lat) && Number.isFinite(lng)) {
              reqLat = lat;
              reqLng = lng;
            }
          }
        }
      } catch (e) {
        functions.logger.warn("Geocoding failed", e as any);
      }
    }

    const wStart = safeNum(data.windowStartMins);
    const wEnd = safeNum(data.windowEndMins);
    const topKRequested = Math.max(1, Math.min(10, Number(data.topK ?? 5)));

    // ---- Candidate donations (only not-expired) + exact food type ----
    const expiryCutoff = todayEOD;
    const a = await db
      .collection("donations")
      .where("status", "==", "pending")
      .where("foodTypeLabel", "==", reqFood)
      .where("expiryAt", ">=", expiryCutoff)
      .get() as FirebaseFirestore.QuerySnapshot<DonationDoc>;

    const b = await db
      .collection("donations")
      .where("status", "==", "approved")
      .where("foodTypeLabel", "==", reqFood)
      .where("expiryAt", ">=", expiryCutoff)
      .get() as FirebaseFirestore.QuerySnapshot<DonationDoc>;

    const seen = new Set<string>();
    const candidates = [...a.docs, ...b.docs].filter(d => !seen.has(d.id) && (seen.add(d.id), true));

    // Prepare list of qty_bucket feature names the model expects (e.g. "qty_bucket_balanced")
    const qtyBucketFeatureNames: string[] = (MODEL.features ?? []).filter(f => f.startsWith("qty_bucket_"));

    // ---- Score with the trained tree ----
    const rows = candidates.map(doc => {
      const d = doc.data();
      const title = (d.title || d.foodName || "Donation").toString();
      const foodType = (d.foodTypeLabel || "").toString();
      const qtyOffer = (d.quantity || "").toString();
      const address = (d.pickupInfo?.address || "").toString();

      // Dates: compute true expiry_gap_days = expiryEOD - needByEOD (rounded days)
      const expiryDate = toDate(d.expiryAt);
      const expiryEOD = expiryDate
        ? new Date(expiryDate.getFullYear(), expiryDate.getMonth(), expiryDate.getDate(), 23, 59, 59)
        : null;

      let expiry_gap_days = -14; // training default when unknown
      if (expiryEOD) {
        const ms = expiryEOD.getTime() - todayEOD.getTime();
        expiry_gap_days = clamp(Math.round(ms / 86_400_000), -14, 14);
      }

      // Also keep "days left" for UI/sorting (non-model)
      const freshDaysLeft = expiryEOD
        ? clamp(Math.round((expiryEOD.getTime() - todayEOD.getTime()) / 86_400_000), -14, 30)
        : 999;

      // Distance
      const dLat = safeNum(d.pickupInfo?.lat);
      const dLng = safeNum(d.pickupInfo?.lng);
      const rawDist =
        reqLat != null && reqLng != null && dLat != null && dLng != null
          ? haversineKm(reqLat, reqLng, dLat, dLng)
          : null;
      const distanceKm = Number.isFinite(rawDist as number) ? clamp(rawDist as number, 0, 200) : 999;

      // Pickup window overlap (minutes)
      const start = toDate(d.pickupInfo?.time);
      const end = toDate(d.pickupInfo?.endTime);
      const startMin = start ? start.getHours() * 60 + start.getMinutes() : null;
      const endMin = end ? end.getHours() * 60 + end.getMinutes() : null;

      let overlap = 0;
      if (wStart != null && wEnd != null) {
        const b1 = startMin ?? wStart;
        const b2 = endMin ?? (startMin ?? wStart);
        overlap = Math.max(0, Math.min(wEnd, b2) - Math.max(wStart, b1));
      }

      // Quantity coverage (offer / need)
      // Only compare when we can do it truthfully:
      // - mass↔mass (kg/g)
      // - count↔count with the SAME unit (boxes↔boxes, plates↔plates, ...)
      // Otherwise: coverage = -1 (unknown)
      const offer = parseQuantity(qtyOffer);
      let coverage = -1; // unknown by default (training default for qty_ratio)
      let unitCompatible = 0;
      if (offer.ok && reqQtyParsed.ok) {
        if (offer.cat === "mass" && reqQtyParsed.cat === "mass") {
          const offG = gramsFrom(offer.value, offer.unit);
          const reqG = gramsFrom(reqQtyParsed.value, (reqQtyParsed as any).unit);
          if (offG != null && reqG != null && reqG > 0) {
            coverage = clamp(offG / reqG, 0, 10);
            unitCompatible = 1;
          }
        } else if (offer.cat === "count" && reqQtyParsed.cat === "count") {
          const offUnit = offer.unit.toLowerCase();
          const needUnit = ((reqQtyParsed as any).unit as string | undefined)?.toLowerCase() ?? "";
          if (offUnit === needUnit && (reqQtyParsed as any).value > 0) {
            coverage = clamp(offer.value / (reqQtyParsed as any).value, 0, 10);
            unitCompatible = 1;
          } else {
            // both count-like but different units => not compatible
            unitCompatible = 0;
          }
        }
      }

      // Derive coarse qty_bucket label used by trainer
      // matches trainer buckets: unknown, too_small, small, balanced, too_large
      function qtyBucketLabel(r: number | null | undefined): string {
        if (typeof r !== "number" || !Number.isFinite(r) || r < 0) return "unknown";
        if (r < 0.5) return "too_small";
        if (r < 0.8) return "small";
        if (r <= 3.0) return "balanced";
        return "too_large";
      }
      const qbLabel = qtyBucketLabel(coverage);

      // ---- Features for the tree (ALIGN with trainer) ----
      const features: Record<string, number | string> = {
        qty_ratio: coverage,                                  // -1 when unknown
        distance_km: distanceKm,                              // 0..200; 999 if unknown
        expiry_gap_days,                                      // gap vs todayEOD
        window_overlap_min: overlap ?? 0,                     // 0 in training
        has_coords: (reqLat != null && reqLng != null && dLat != null && dLng != null) ? 1 : 0,
        unit_compatible: unitCompatible,                      // numeric flag
        food_type: reqFood || "",                             // request's desired type (for food_type== splits)
      };

      // Add qty_bucket_* one-hot fields expected by the model
      for (const fname of qtyBucketFeatureNames) {
        // fname looks like "qty_bucket_balanced" -> label is part after prefix
        const suffix = fname.substring("qty_bucket_".length);
        features[fname] = (suffix === qbLabel) ? 1 : 0;
      }

      const score = predictWithTree(MODEL.tree, features);

      return {
        donationId: doc.id,
        title,
        foodType,
        qtyOffer,
        address,
        distanceKm: Number.isFinite(rawDist as number) ? (rawDist as number) : null,
        expiryDate: expiryEOD ? expiryEOD.toISOString() : null,
        freshDaysLeft, // negative => expires before today ends (shouldn’t happen due to filter)
        score: Math.round(score * 1000) / 1000,

        // for sorting priorities
        qtyRatio: coverage,
        foodTypeMatch: foodType === reqFood,
      };
    });

    // PRIORITY: food type match → quantity → expiry → distance → score
    rows.sort((a, b) => {
      // 1) food type exact match first
      const aMatch = a.foodTypeMatch ? 0 : 1;
      const bMatch = b.foodTypeMatch ? 0 : 1;
      if (aMatch !== bMatch) return aMatch - bMatch;

      // 2) quantity: bucket first (ideal 0, acceptable 1, poor 2, unknown 3), then closeness to 1.0
      const aQB = qtyBucket(a.qtyRatio);
      const bQB = qtyBucket(b.qtyRatio);
      if (aQB !== bQB) return aQB - bQB;

      const aQD = qtyDistanceFromIdeal(a.qtyRatio);
      const bQD = qtyDistanceFromIdeal(b.qtyRatio);
      if (aQD !== bQD) return aQD - bQD;

      // 3) expiry: sooner first (unknown pushed to bottom)
      const aExp = a.freshDaysLeft ?? 9999;
      const bExp = b.freshDaysLeft ?? 9999;
      if (aExp !== bExp) return aExp - bExp;

      // 4) distance: nearer first (unknown pushed to bottom)
      const aDist = a.distanceKm ?? 9999;
      const bDist = b.distanceKm ?? 9999;
      if (aDist !== bDist) return aDist - bDist;

      // 5) tie-breaker: model score (higher wins)
      return b.score - a.score;
    });

    const out = rows.slice(0, topKRequested);

    return {
      matches: out,
      meta: {
        modelType: "decision_tree",
        categories_food_type: MODEL.categories_food_type ?? [],
        candidates: rows.length,
        requesterHasCoords: reqLat != null && reqLng != null,
        generatedAt: new Date().toISOString(),
        sort: "foodType_match > quantity > expirySoonest > distanceNearest > score"
      },
    };
  } catch (err: any) {
    // Surface useful info while you're debugging
    functions.logger.error("matchDonations failed", err);
    throw new functions.https.HttpsError(
      "internal",
      err?.message || "Unhandled exception",
      { stack: err?.stack }
    );
  }
});
