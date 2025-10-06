// functions/src/model/validate.ts
import { ModelJson, TreeNode } from "./model";

function isFiniteNumber(n: unknown): n is number {
  return typeof n === "number" && Number.isFinite(n);
}

function validateNode(node: TreeNode, depth = 0): void {
  if (node.leaf === true) {
    if (!isFiniteNumber(node.p1) || node.p1 < 0 || node.p1 > 1) {
      throw new Error(`Invalid leaf.p1 at depth ${depth}`);
    }
    return;
  }
  if (node.leaf !== false) throw new Error(`Invalid node.leaf at depth ${depth}`);
  if (typeof node.feature !== "string" || !("threshold" in node)) {
    throw new Error(`Invalid split node at depth ${depth}`);
  }
  if (!isFiniteNumber((node as any).threshold)) {
    throw new Error(`Non-numeric threshold at depth ${depth}`);
  }
  if (!node.left || !node.right) {
    throw new Error(`Missing children at depth ${depth}`);
  }
  validateNode(node.left, depth + 1);
  validateNode(node.right, depth + 1);
}

export function validateModelJson(m: any): asserts m is ModelJson {
  if (!m || m.model_type !== "decision_tree") {
    throw new Error("model_type must be 'decision_tree'");
  }
  if (!Array.isArray(m.features)) throw new Error("features missing/invalid");
  if (!m.tree) throw new Error("tree missing");
  validateNode(m.tree);
}
