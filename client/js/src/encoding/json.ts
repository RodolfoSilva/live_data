import JSONpatch from "jsonpatch";

export const unSerialize = <T = Record<string, unknown>>(
  doc: T,
  patch: Diff
): T => {
  return JSONpatch.apply_patch(doc, decompress(patch));
};
type Diff = [number, ...any];
type BaseOperation = "remove";
type FromOperation = "move" | "copy";
type ValueOperation = "add" | "replace" | "test";
type Operation = BaseOperation | FromOperation | ValueOperation;

type BasePatch = { op: BaseOperation; path: string };
type FromPatch = { op: FromOperation; path: string; from: string };
type ValuePatch = { op: ValueOperation; path: string; value: string };

type Patch = BasePatch | FromPatch | ValuePatch;

const OPERATIONS: Record<number, Operation> = {
  0: "remove",
  1: "add",
  2: "replace",
  3: "test",
  4: "move",
  5: "copy",
};

function decompress(diff: Diff): Patch[] {
  const decoded: Patch[] = [];

  for (let i = 0; i < diff.length; i++) {
    const op = diff[i];
    const patch = {
      op: OPERATIONS[op]!,
      path: diff[++i] as string,
    } as Patch;

    if (["add", "replace", "test"].includes(patch.op)) {
      (patch as ValuePatch).value = diff[++i];
    } else if (patch.op !== "remove") {
      (patch as FromPatch).from = diff[++i];
    }

    decoded.push(patch);
  }

  return decoded;
}

export default class JSONEncoding {
  __lastRender__ = { r: {} };

  get out(): Record<string, unknown> {
    return this.__lastRender__.r;
  }

  constructor() {}

  handleMessage(diff: any): boolean {
    let rendered = false;

    this.__lastRender__ = unSerialize(this.__lastRender__, diff);

    return true;
  }
}
