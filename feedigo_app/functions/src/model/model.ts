// functions/src/model/model.ts

export type TreeNode =
  | { leaf: true; p1: number }
  | {
      leaf: false;
      feature: string;     // "qty_ratio" | "distance_km" | "expiry_gap_days" | "window_overlap_min" | "has_coords" | "food_type==Cooked Meals" ...
      threshold: number;
      left: TreeNode;
      right: TreeNode;
    };

export type ModelJson = {
  model_type: "decision_tree";
  features: string[];               // raw feature names used during training
  categories_food_type?: string[];  // e.g., ["Cooked Meals", ...]
  tree: TreeNode;                   // the trained tree
  metrics?: { auc?: number };       // optional
};
