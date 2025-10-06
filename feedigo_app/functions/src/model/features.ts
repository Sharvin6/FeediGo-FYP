// functions/src/model/features.ts
export function defaultFor(feat: string): number {
  if (feat === "qty_ratio") return -1;
  if (feat === "distance_km") return 999;
  if (feat === "expiry_gap_days") return -14;
  if (feat === "window_overlap_min") return 0;
  if (feat === "has_coords") return 0;
  return 0;
}
