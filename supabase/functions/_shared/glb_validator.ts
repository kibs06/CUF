// supabase/functions/_shared/glb_validator.ts
//
// The server-side half of the shoe-model authoring contract (roadmap V2.4).
//
// `lib/utils/glb_validator.dart` is the **executable reference** for the
// contract: partners run `tool/validate_glb.dart` on the export, and the
// seller form (V2.3) runs the same library before it uploads. This file is
// the third caller, and it cannot import that one — an Edge Function runs on
// Deno/TypeScript, the app on Dart — so the checks are *mirrored* here
// instead of shared. That mirroring is the whole risk of this file: two
// implementations of one rule set drift unless something proves they agree.
// `tool/check_glb_validator_parity.mjs` is that something — it runs both
// over the same fixtures and diffs the reports (check names, order, statuses
// and detail text), so a divergence is a failing command rather than a
// seller told one thing by the app and another by the server.
//
// Why a second copy is worth it: architecture §2.5.4 says client-side
// validation is **not** a security boundary — it exists to give sellers fast
// feedback, and every rule in it can be skipped by anyone willing to call the
// REST API instead of the app. This copy runs on bytes the caller never
// touched (downloaded with the service role after the row's RLS-scoped read),
// which is what makes it a check rather than a courtesy.
//
// **What it can decide and what it cannot** is exactly the Dart version's
// list, and it is repeated here because this copy is the one whose verdict
// hides a row from customers: GLB structure and single-file embedding, file
// size, triangle count, material part names, texture dimensions, the
// compression gate, units, up-axis, origin/grounding, and the mesh's external
// length against the declared one ±5 mm. It cannot decide whether the toe
// points at +Z rather than the heel (a bbox is symmetric about that question),
// whether the albedo was de-lit, whether it *looks* like the shoe, or what
// frame rate it holds on device — those stay reviewer rows in
// `SHOE_MODEL_AUTHORING_GUIDE.md` §5.2, and `validate-shoe-model` refuses to
// pretend otherwise in its response.
//
// Deliberately dependency-free and Deno-global-free: `crypto.subtle`,
// `TextDecoder` and `DataView` are the only non-language things it touches, so
// the parity checker can import it under plain Node.

// ─── Contract constants (each mirrors its twin in lib/utils/glb_validator.dart)

/** GLB magic `glTF` as a little-endian uint32. */
export const GLB_MAGIC = 0x46546c67;

/** GLB chunk type `JSON`. */
export const JSON_CHUNK_TYPE = 0x4e4f534a;

/** GLB chunk type `BIN\0`. */
export const BIN_CHUNK_TYPE = 0x004e4942;

/** Triangle budget — guide §C4/§C7 / architecture §2.5.1. */
export const MAX_TRIANGLES = 60000;

/** The guide's file budget ("≤ 5 MB"). The bucket's hard cap is 8 MiB. */
export const FILE_SIZE_BUDGET_BYTES = 5 * 1024 * 1024;

/** The `shoe-models` bucket's `file_size_limit`. */
export const FILE_SIZE_HARD_CAP_BYTES = 8 * 1024 * 1024;

/** Declared external length tolerance — guide §C2 / acceptance checklist 3. */
export const LENGTH_TOLERANCE_MM = 5.0;

/** Origin/grounding tolerance; the contract has no number of its own. */
export const ORIGIN_TOLERANCE_MM = 5.0;

/** Plausible external length band, mirroring the `authored_length_mm` CHECK. */
export const PLAUSIBLE_LENGTH_MIN_MM = 100;
export const PLAUSIBLE_LENGTH_MAX_MM = 400;

/** Guide §C5/§C7: textures at ≤ 1024². */
export const MAX_TEXTURE_DIMENSION = 1024;

/**
 * Architecture §2.5.1: "≤ 2 texture sets at ≤ 1024²". A *set* is not
 * derivable from image count alone, so past this count the check warns and
 * asks a reviewer rather than guessing.
 */
export const TEXTURE_SET_WARNING_IMAGE_COUNT = 8;

/** Guide §C6 — the exact material names a colour swap can target. */
export const APPROVED_PART_NAMES = [
  "upper",
  "sole",
  "midsole",
  "laces",
  "lining",
  "heel",
];

/** The two parts every shoe has. */
export const REQUIRED_PART_NAMES = ["upper", "sole"];

/** Rejected until roadmap V0.7 proves the shipped renderer decodes them. */
export const UNAPPROVED_COMPRESSION_EXTENSIONS = new Set([
  "KHR_draco_mesh_compression",
  "EXT_meshopt_compression",
  "KHR_texture_basisu",
]);

// ─── Report types ──────────────────────────────────────────────────────────

export type GlbCheckStatus = "pass" | "fail" | "warning";

/** One row of the pass/fail table. Same shape as the Dart `GlbCheck`. */
export interface GlbCheck {
  name: string;
  status: GlbCheckStatus;
  detail: string;
}

/**
 * What the caller knows that the file cannot say: the declared external
 * length (the row's `authored_length_mm`, or a handover declaration), plus
 * identity fields echoed into the report.
 */
export interface GlbValidationOptions {
  label?: string;
  externalLengthMm?: number | null;
  authoredSizeEu?: number | null;
  shoeSide?: string | null;
}

/** The report, shape-compatible with the Dart `GlbValidationReport.toJson`. */
export class GlbValidationReport {
  readonly options: Required<GlbValidationOptions>;
  readonly fileSizeBytes: number;
  readonly checks: GlbCheck[] = [];
  readonly notes: string[] = [];

  /**
   * Triangles counted across every triangulated primitive, or null when the
   * file never got far enough to count them. `product_models.triangle_count`
   * stores this, and comparing it against the number the client sent is how
   * the two sides stay honest (the Dart library's comment says the same).
   */
  triangleCount: number | null = null;

  /**
   * The mesh's heel-to-toe extent along Z in millimetres, or null when no
   * POSITION accessor carried min/max. The **external** length — never
   * `products.last_length_mm`, which is the internal last the fit engine
   * grades against (architecture §2.7.3).
   */
  meshExternalLengthMm: number | null = null;

  constructor(options: GlbValidationOptions, fileSizeBytes: number) {
    this.options = {
      label: options.label ?? "<memory>",
      externalLengthMm: options.externalLengthMm ?? null,
      authoredSizeEu: options.authoredSizeEu ?? null,
      shoeSide: options.shoeSide ?? null,
    };
    this.fileSizeBytes = fileSizeBytes;
  }

  get passed(): boolean {
    return !this.checks.some((c) => c.status === "fail");
  }

  get failCount(): number {
    return this.checks.filter((c) => c.status === "fail").length;
  }

  get warningCount(): number {
    return this.checks.filter((c) => c.status === "warning").length;
  }

  add(name: string, status: GlbCheckStatus, detail: string): void {
    this.checks.push({ name, status, detail });
  }

  note(message: string): void {
    this.notes.push(message);
  }

  toJson(): Record<string, unknown> {
    return {
      label: this.options.label,
      fileSizeBytes: this.fileSizeBytes,
      passed: this.passed,
      triangleCount: this.triangleCount,
      meshExternalLengthMm: this.meshExternalLengthMm,
      checks: this.checks.map((c) => ({
        name: c.name,
        status: c.status,
        detail: c.detail,
      })),
      notes: this.notes,
    };
  }
}

// ─── Entry point ───────────────────────────────────────────────────────────

/**
 * Validates one `.glb` against the authoring contract.
 *
 * Never throws for a malformed file: a file that cannot be parsed produces a
 * report whose `format` row fails, because "explain what is wrong" is the
 * function's whole job.
 */
export function validateGlb(
  bytes: Uint8Array,
  options: GlbValidationOptions = {},
): GlbValidationReport {
  const report = new GlbValidationReport(options, bytes.length);

  const parsed = parseGlb(bytes, report);
  if (parsed === null) return report;

  checkSingleFile(parsed, report);
  checkFileSize(report);
  checkTriangles(parsed, report);
  checkMaterials(parsed, report);
  checkTextures(parsed, report);
  checkCompression(parsed, report);

  const bbox = boundingBox(parsed, report);
  if (bbox === null) {
    report.add(
      "geometry",
      "fail",
      "no POSITION accessor with min/max was found, so scale and origin " +
        "cannot be checked — the glTF spec requires min/max on POSITION, " +
        "and Blender writes it; a missing value usually means the file was " +
        "post-processed by hand",
    );
  } else {
    report.meshExternalLengthMm = bbox.lengthMm;
    checkUnits(bbox, report);
    checkOrientation(bbox, report);
    checkOrigin(bbox, report);
    checkScale(bbox, report);
  }

  return report;
}

// ─── Parsing ───────────────────────────────────────────────────────────────

interface ParsedGlb {
  json: Record<string, unknown>;
  bin: Uint8Array | null;
}

/** The bytes of one `bufferViews` entry, or null when it is not embedded. */
function bufferViewBytes(parsed: ParsedGlb, index: number): Uint8Array | null {
  const views = asList(parsed.json["bufferViews"]);
  if (index < 0 || index >= views.length) return null;
  const view = views[index];
  if (!isMap(view)) return null;
  const buffer = view["buffer"];
  // A GLB embeds exactly one buffer (index 0); anything else is external
  // and already failed the single-file check.
  if (typeof buffer === "number" && Math.trunc(buffer) !== 0) return null;
  const offset = asInt(view["byteOffset"]) ?? 0;
  const length = asInt(view["byteLength"]) ?? 0;
  const bin = parsed.bin;
  if (
    bin === null ||
    offset < 0 ||
    length <= 0 ||
    offset + length > bin.length
  ) {
    return null;
  }
  return bin.subarray(offset, offset + length);
}

function accessor(parsed: ParsedGlb, index: number): unknown {
  const accessors = asList(parsed.json["accessors"]);
  if (index < 0 || index >= accessors.length) return null;
  return accessors[index];
}

function parseGlb(
  bytes: Uint8Array,
  report: GlbValidationReport,
): ParsedGlb | null {
  if (bytes.length < 12) {
    report.add(
      "format",
      "fail",
      `file is ${bytes.length} bytes — too short for the 12-byte GLB header`,
    );
    return null;
  }

  const data = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (data.getUint32(0, true) !== GLB_MAGIC) {
    report.add(
      "format",
      "fail",
      'not a GLB: the first four bytes are not "glTF" — a .gltf + .bin pair or ' +
        "a zip of textures is the usual cause (export \"glTF Binary (.glb)\")",
    );
    return null;
  }

  const version = data.getUint32(4, true);
  if (version !== 2) {
    report.add(
      "format",
      "fail",
      `glTF version ${version} — the contract is glTF 2.0`,
    );
    return null;
  }

  const declaredLength = data.getUint32(8, true);
  if (declaredLength !== bytes.length) {
    report.add(
      "format",
      "fail",
      `the header declares ${declaredLength} bytes but the file is ` +
        `${bytes.length} — a truncated copy, or the file was edited after ` +
        "export",
    );
    return null;
  }

  let jsonBytes: Uint8Array | null = null;
  let bin: Uint8Array | null = null;
  let offset = 12;
  while (offset + 8 <= bytes.length) {
    const chunkLength = data.getUint32(offset, true);
    const chunkType = data.getUint32(offset + 4, true);
    const start = offset + 8;
    const end = start + chunkLength;
    if (end > bytes.length) {
      report.add(
        "format",
        "fail",
        `a chunk at byte ${offset} claims ${chunkLength} bytes but the file ends first`,
      );
      return null;
    }
    if (chunkType === JSON_CHUNK_TYPE) {
      jsonBytes = jsonBytes ?? bytes.subarray(start, end);
    } else if (chunkType === BIN_CHUNK_TYPE) {
      bin = bin ?? bytes.subarray(start, end);
    }
    offset = end;
  }

  if (jsonBytes === null) {
    report.add("format", "fail", "no JSON chunk found");
    return null;
  }

  let parsedJson: Record<string, unknown>;
  try {
    const text = new TextDecoder("utf-8", { fatal: false }).decode(jsonBytes);
    const decoded: unknown = JSON.parse(text);
    if (!isMap(decoded)) {
      report.add("format", "fail", "the JSON chunk is not an object");
      return null;
    }
    parsedJson = decoded;
  } catch (e) {
    report.add(
      "format",
      "fail",
      `the JSON chunk does not parse: ${e instanceof Error ? e.message : e}`,
    );
    return null;
  }

  const asset = parsedJson["asset"];
  const rawVersion = isMap(asset) ? asset["version"] : undefined;
  const assetVersion =
    rawVersion === undefined || rawVersion === null
      ? null
      : String(rawVersion);
  if (assetVersion !== "2.0") {
    report.add(
      "format",
      "fail",
      `asset.version is ${assetVersion ?? "missing"} — the contract is "2.0"`,
    );
    return null;
  }

  report.add(
    "format",
    "pass",
    `GLB v2 · JSON ${size(jsonBytes.length)} · ` +
      `BIN ${bin === null ? "none" : size(bin.length)}`,
  );
  return { json: parsedJson, bin };
}

// ─── Checks ────────────────────────────────────────────────────────────────

function checkSingleFile(parsed: ParsedGlb, report: GlbValidationReport): void {
  const external: string[] = [];

  const buffers = asList(parsed.json["buffers"]);
  for (let i = 0; i < buffers.length; i++) {
    const buffer = buffers[i];
    if (!isMap(buffer)) continue;
    const uri = textOrNull(buffer["uri"]);
    if (uri !== null && uri.trim() !== "") {
      external.push(`buffers[${i}].uri = ${uri}`);
    } else if (i > 0) {
      // glTF: only buffer 0 may omit a uri in a GLB (it is the BIN chunk).
      external.push(`buffers[${i}] has no uri but is not the embedded buffer`);
    }
  }

  const images = asList(parsed.json["images"]);
  for (let i = 0; i < images.length; i++) {
    const image = images[i];
    if (!isMap(image)) continue;
    const uri = textOrNull(image["uri"]);
    if (uri !== null && uri.trim() !== "") {
      external.push(`images[${i}].uri = ${uri}`);
    }
  }

  if (external.length === 0) {
    report.add(
      "single file",
      "pass",
      "everything is inside the .glb — no external .bin or image files",
    );
  } else {
    report.add(
      "single file",
      "fail",
      `external reference(s): ${external.join(", ")} — export as ` +
        `"glTF Binary (.glb)" with textures embedded (guide §C8)`,
    );
  }
}

function checkFileSize(report: GlbValidationReport): void {
  const bytes = report.fileSizeBytes;
  if (bytes > FILE_SIZE_HARD_CAP_BYTES) {
    report.add(
      "file size",
      "fail",
      `${size(bytes)} exceeds even the bucket hard cap of ${size(FILE_SIZE_HARD_CAP_BYTES)} ` +
        "— the upload would be rejected",
    );
  } else if (bytes > FILE_SIZE_BUDGET_BYTES) {
    report.add(
      "file size",
      "fail",
      `${size(bytes)} is over the ${size(FILE_SIZE_BUDGET_BYTES)} authoring budget ` +
        "(the bucket would still accept it — the contract is the smaller number; " +
        "re-bake textures and retopo, guide §C5/C7)",
    );
  } else {
    report.add(
      "file size",
      "pass",
      `${size(bytes)} (budget ${size(FILE_SIZE_BUDGET_BYTES)})`,
    );
  }
}

function checkTriangles(parsed: ParsedGlb, report: GlbValidationReport): void {
  let triangles = 0;
  const notes: string[] = [];

  const meshes = asList(parsed.json["meshes"]);
  for (let m = 0; m < meshes.length; m++) {
    const mesh = meshes[m];
    if (!isMap(mesh)) continue;
    for (const primitive of asList(mesh["primitives"])) {
      if (!isMap(primitive)) continue;
      const mode = asInt(primitive["mode"]) ?? 4; // 4 = TRIANGLES
      if (mode !== 4) {
        notes.push(
          `a primitive uses mode ${mode} — only triangles are supported`,
        );
        continue;
      }
      const indices = primitive["indices"];
      let count: number | null = null;
      if (typeof indices === "number") {
        const found = accessor(parsed, Math.trunc(indices));
        if (isMap(found)) count = asInt(found["count"]);
      } else {
        const attributes = primitive["attributes"];
        const position = isMap(attributes) ? attributes["POSITION"] : null;
        if (typeof position === "number") {
          const found = accessor(parsed, Math.trunc(position));
          if (isMap(found)) count = asInt(found["count"]);
        }
      }
      if (count === null) {
        notes.push(
          `mesh ${m} has a primitive whose vertex or index count is unreadable`,
        );
        continue;
      }
      triangles += Math.floor(count / 3);
    }
  }

  for (const note of notes) report.note(note);

  report.triangleCount = triangles;

  if (triangles > MAX_TRIANGLES) {
    report.add(
      "triangles",
      "fail",
      `${num(triangles)} triangles exceeds the ${num(MAX_TRIANGLES)} cap ` +
        "(target 25,000–45,000 — retopo, guide §C4)",
    );
  } else {
    report.add(
      "triangles",
      "pass",
      `${num(triangles)} triangles (cap ${num(MAX_TRIANGLES)}, target 25,000–45,000)`,
    );
  }
}

function checkMaterials(parsed: ParsedGlb, report: GlbValidationReport): void {
  const materials = asList(parsed.json["materials"]);
  if (materials.length === 0) {
    report.add(
      "materials",
      "fail",
      `no materials — the colour swap targets parts by name ` +
        `(${APPROVED_PART_NAMES.join(", ")}); the app cannot repaint a single-material mesh`,
    );
    return;
  }

  const names: string[] = [];
  for (const material of materials) {
    if (!isMap(material)) continue;
    names.push(
      material["name"] === undefined ? "" : String(material["name"]).trim(),
    );
  }

  const problems: string[] = [];
  const unnamed = names.filter((n) => n === "").length;
  if (unnamed > 0) {
    problems.push(
      `${unnamed} material(s) have no name ` +
        '("Material.001" in Blender means the rename in §C6 was skipped)',
    );
  }

  const known = names.filter((n) => n !== "");
  const duplicates = new Set(known).size !== known.length;
  if (duplicates) {
    problems.push(
      `duplicate material names (${known.join(", ")}) — each part ` +
        "must exist exactly once or the colour swap is ambiguous",
    );
  }

  const unapproved = [
    ...new Set(known.filter((n) => !APPROVED_PART_NAMES.includes(n))),
  ];
  if (unapproved.length > 0) {
    problems.push(
      `names outside the approved set: ${unapproved.join(", ")} ` +
        `(approved: ${APPROVED_PART_NAMES.join(", ")})`,
    );
  }

  const missing = REQUIRED_PART_NAMES.filter((n) => !known.includes(n));
  if (missing.length > 0) {
    problems.push(`missing required part(s): ${missing.join(", ")}`);
  }

  if (problems.length === 0) {
    report.add(
      "materials",
      "pass",
      `${known.join(", ")} — all names approved`,
    );
  } else {
    report.add("materials", "fail", problems.join("; "));
  }
}

function checkTextures(parsed: ParsedGlb, report: GlbValidationReport): void {
  const images = asList(parsed.json["images"]);
  if (images.length === 0) {
    report.add(
      "textures",
      "pass",
      "no image textures (base-colour factors only)",
    );
    return;
  }

  let maxWidth = 0;
  let maxHeight = 0;
  const oversized: string[] = [];
  const unreadable: string[] = [];

  for (let i = 0; i < images.length; i++) {
    const image = images[i];
    if (!isMap(image)) continue;
    if (image["uri"] !== undefined && image["uri"] !== null) {
      continue; // already failed the single-file check
    }
    const viewIndex = image["bufferView"];
    if (typeof viewIndex !== "number") {
      unreadable.push(`images[${i}] (no bufferView)`);
      continue;
    }
    const bytes = bufferViewBytes(parsed, Math.trunc(viewIndex));
    if (bytes === null) {
      unreadable.push(`images[${i}] (bufferView not embedded)`);
      continue;
    }
    const dimensions = imageDimensions(bytes);
    if (dimensions === null) {
      const mime =
        image["mimeType"] === undefined
          ? "unknown format"
          : String(image["mimeType"]);
      unreadable.push(
        `images[${i}] (${mime} — dimensions unreadable by this validator)`,
      );
      continue;
    }
    if (dimensions.width > maxWidth) maxWidth = dimensions.width;
    if (dimensions.height > maxHeight) maxHeight = dimensions.height;
    if (
      dimensions.width > MAX_TEXTURE_DIMENSION ||
      dimensions.height > MAX_TEXTURE_DIMENSION
    ) {
      oversized.push(
        `images[${i}] ${dimensions.width}×${dimensions.height} (${dimensions.format})`,
      );
    }
  }

  for (const item of unreadable) report.note(`texture not measurable: ${item}`);

  if (oversized.length > 0) {
    report.add(
      "textures",
      "fail",
      `${oversized.join("; ")} exceeds ${MAX_TEXTURE_DIMENSION}² — re-bake ` +
        "(guide §C5: base colour, roughness, metallic, normal at 1024² max)",
    );
  } else if (images.length > TEXTURE_SET_WARNING_IMAGE_COUNT) {
    report.add(
      "textures",
      "warning",
      `${images.length} images, largest ${maxWidth}×${maxHeight} — the budget is ` +
        `≤ 2 texture sets at ${MAX_TEXTURE_DIMENSION}²; image count alone cannot ` +
        "tell sets from maps, so a reviewer should confirm (guide §C7)",
    );
  } else {
    report.add(
      "textures",
      "pass",
      `${images.length} image(s), largest ${maxWidth}×${maxHeight} (limit ${MAX_TEXTURE_DIMENSION}²)`,
    );
  }
}

function checkCompression(
  parsed: ParsedGlb,
  report: GlbValidationReport,
): void {
  const declared = new Set([
    ...asStringList(parsed.json["extensionsUsed"]),
    ...asStringList(parsed.json["extensionsRequired"]),
  ]);

  const banned = [...declared]
    .filter((e) => UNAPPROVED_COMPRESSION_EXTENSIONS.has(e))
    .sort();
  const other = [...declared]
    .filter((e) => !UNAPPROVED_COMPRESSION_EXTENSIONS.has(e))
    .sort();

  if (other.length > 0) {
    const required = asStringList(parsed.json["extensionsRequired"]);
    report.note(
      `extension(s) in use: ${other.join(", ")}` +
        `${required.some((e) => other.includes(e)) ? " (required)" : ""} — the renderer must ` +
        "support these; they are not rejected by the validator",
    );
  }

  if (banned.length > 0) {
    report.add(
      "compression",
      "fail",
      `${banned.join(", ")} is declared, but geometry compression and KTX2 are ` +
        "not approved until roadmap V0.7 proves the shipped renderer decodes " +
        "them (architecture §2.5.1 / decision D6) — export uncompressed",
    );
  } else {
    report.add(
      "compression",
      "pass",
      "none declared — the asset is uncompressed",
    );
  }
}

interface Bbox {
  minX: number;
  minY: number;
  minZ: number;
  maxX: number;
  maxY: number;
  maxZ: number;
  lengthMm: number;
  widthMm: number;
  heightMm: number;
  centreXMm: number;
}

function boundingBox(
  parsed: ParsedGlb,
  report: GlbValidationReport,
): Bbox | null {
  // Prefer the meshes the scene actually instantiates; an unreferenced mesh
  // (a leftover copy in the Blender outliner) must not decide the geometry.
  const nodes = asList(parsed.json["nodes"]);
  const referenced = new Set<number>();
  for (const node of nodes) {
    if (!isMap(node)) continue;
    const mesh = node["mesh"];
    if (typeof mesh === "number") referenced.add(Math.trunc(mesh));
  }

  const meshes = asList(parsed.json["meshes"]);
  const meshIndices =
    referenced.size === 0
      ? meshes.map((_, i) => i)
      : [...referenced].sort((a, b) => a - b);

  if (referenced.size > 0 && referenced.size < meshes.length) {
    report.note(
      `${meshes.length - referenced.size} mesh(es) are not referenced by any ` +
        "node — delete leftovers before export (guide §C3)",
    );
  }

  let minX: number | null = null;
  let minY: number | null = null;
  let minZ: number | null = null;
  let maxX: number | null = null;
  let maxY: number | null = null;
  let maxZ: number | null = null;

  for (const meshIndex of meshIndices) {
    if (meshIndex < 0 || meshIndex >= meshes.length) continue;
    const mesh = meshes[meshIndex];
    if (!isMap(mesh)) continue;
    for (const primitive of asList(mesh["primitives"])) {
      if (!isMap(primitive)) continue;
      const attributes = primitive["attributes"];
      if (!isMap(attributes)) continue;
      const position = attributes["POSITION"];
      if (typeof position !== "number") continue;
      const found = accessor(parsed, Math.trunc(position));
      if (!isMap(found)) continue;
      const min = asNumList(found["min"]);
      const max = asNumList(found["max"]);
      if (min.length < 3 || max.length < 3) continue;

      minX = minX === null ? min[0] : Math.min(min[0], minX);
      minY = minY === null ? min[1] : Math.min(min[1], minY);
      minZ = minZ === null ? min[2] : Math.min(min[2], minZ);
      maxX = maxX === null ? max[0] : Math.max(max[0], maxX);
      maxY = maxY === null ? max[1] : Math.max(max[1], maxY);
      maxZ = maxZ === null ? max[2] : Math.max(max[2], maxZ);
    }
  }

  if (
    minX === null ||
    minY === null ||
    minZ === null ||
    maxX === null ||
    maxY === null ||
    maxZ === null
  ) {
    return null;
  }

  return {
    minX,
    minY,
    minZ,
    maxX,
    maxY,
    maxZ,
    lengthMm: (maxZ - minZ) * 1000,
    widthMm: (maxX - minX) * 1000,
    heightMm: (maxY - minY) * 1000,
    centreXMm: ((minX + maxX) / 2) * 1000,
  };
}

function checkUnits(bbox: Bbox, report: GlbValidationReport): void {
  const length = bbox.lengthMm;
  if (length < PLAUSIBLE_LENGTH_MIN_MM || length > PLAUSIBLE_LENGTH_MAX_MM) {
    report.add(
      "units",
      "fail",
      `the mesh is ${mm(length)} long along Z — outside the plausible ` +
        `${num(PLAUSIBLE_LENGTH_MIN_MM)}–${num(PLAUSIBLE_LENGTH_MAX_MM)} mm ` +
        "band. If that is 270-odd thousand, the file is in millimetres: " +
        "Scene units must be Metric / Unit Scale 1.0 / Length: Metres before " +
        "export (architecture §2.5.5)",
    );
  } else {
    report.add(
      "units",
      "pass",
      `length ${mm(length)} — metres, plausible for a shoe`,
    );
  }
}

function checkOrientation(bbox: Bbox, report: GlbValidationReport): void {
  const length = bbox.lengthMm;
  const width = bbox.widthMm;
  const height = bbox.heightMm;

  // The taller-than-long case is checked first because that is what a Z-up
  // export looks like (the length lands on Y), and naming the actual mistake
  // beats a generic "rotated".
  if (length <= height) {
    report.add(
      "orientation",
      "fail",
      `the mesh is taller (${mm(height)}) than it is long (${mm(length)}) — the ` +
        "long axis is not +Z. That is what a Z-up export looks like; export " +
        "with Transform → +Y Up ON (guide §C8)",
    );
  } else if (length <= width) {
    report.add(
      "orientation",
      "fail",
      `the mesh is wider (${mm(width)}) than it is long (${mm(length)}) — it is ` +
        "rotated. The toe must run along +Z: fix the rotation in the Blender " +
        "scene, apply transforms, and export with Transform → +Y Up ON " +
        "(guide §C8)",
    );
  } else {
    report.add(
      "orientation",
      "pass",
      `the long axis is +Z · L ${mm(length)} · W ${mm(width)} · H ${mm(height)}`,
    );
  }
}

function checkOrigin(bbox: Bbox, report: GlbValidationReport): void {
  const problems: string[] = [];
  const minY = bbox.minY * 1000;
  const minZ = bbox.minZ * 1000;
  const centreX = bbox.centreXMm;

  if (Math.abs(minY) > ORIGIN_TOLERANCE_MM) {
    problems.push(
      `the sole is ${mmSigned(minY)} from the ground plane (y min) — ` +
        "heel-bottom-centre at the origin, sole resting on it",
    );
  }
  if (Math.abs(minZ) > ORIGIN_TOLERANCE_MM) {
    problems.push(
      `the heel sits ${mmSigned(minZ)} along Z from the origin — the origin ` +
        "is the heel, not the middle of the shoe",
    );
  }
  if (Math.abs(centreX) > ORIGIN_TOLERANCE_MM) {
    problems.push(`the mesh is ${mmSigned(centreX)} off-centre in X`);
  }

  if (problems.length === 0) {
    report.add(
      "origin",
      "pass",
      `grounded (y ${mm(bbox.minY * 1000)}), heel at ${mm(bbox.minZ * 1000)} on Z, ` +
        `centred (x ${mm(bbox.centreXMm)}) — tolerance ±${num(Math.trunc(ORIGIN_TOLERANCE_MM))} mm`,
    );
  } else {
    report.add("origin", "fail", problems.join("; "));
  }
}

function checkScale(bbox: Bbox, report: GlbValidationReport): void {
  const declared = report.options.externalLengthMm;
  if (declared === null || declared === undefined) {
    report.add(
      "scale",
      "fail",
      "no declared external length. Put external_length_mm in declaration.txt " +
        "(guide §5.1) or pass --external-length-mm — the contract is that the " +
        `mesh equals the calipers ±${num(Math.trunc(LENGTH_TOLERANCE_MM))} mm, and ` +
        "that comparison cannot run without the number",
    );
    return;
  }

  const delta = Math.abs(bbox.lengthMm - declared);
  if (delta > LENGTH_TOLERANCE_MM) {
    report.add(
      "scale",
      "fail",
      `mesh ${mm(bbox.lengthMm)} along Z vs declared ${mm(declared)} — off by ` +
        `${mm(delta)} (tolerance ±${num(Math.trunc(LENGTH_TOLERANCE_MM))} mm). ` +
        "Re-measure at §C2 and scale numerically before re-export",
    );
  } else {
    report.add(
      "scale",
      "pass",
      `mesh ${mm(bbox.lengthMm)} vs declared ${mm(declared)} ` +
        `(Δ ${mm(delta)}, tolerance ±${num(Math.trunc(LENGTH_TOLERANCE_MM))} mm)`,
    );
  }
}

// ─── Handover declaration (guide §5.1) ─────────────────────────────────────

/**
 * Parses a handover `declaration.txt` into a lowercase-key map.
 *
 * Tolerant on purpose: the template ships with placeholders, a maker may
 * write `285 mm` or `UNKNOWN`, and the validator's job is to say what is
 * missing rather than fail to read the file. Blank lines and `#` comments are
 * skipped. Mirrors `parseGlbDeclaration` in `lib/utils/glb_validator.dart`.
 */
export function parseGlbDeclaration(text: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const rawLine of text.split(/\r\n|\r|\n/)) {
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#")) continue;
    const colon = line.indexOf(":");
    if (colon <= 0) continue;
    values[line.slice(0, colon).trim().toLowerCase()] = line
      .slice(colon + 1)
      .trim();
  }
  return values;
}

/**
 * The first number in a declaration value, or null when there is none.
 * Deliberately unit-blind: `285`, `285 mm` and `285mm` all mean the
 * millimetre field they appear in, and `UNKNOWN` must mean "absent" rather
 * than 0.
 */
export function declarationNumber(value: string | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  const match = value.match(/-?\d+(?:\.\d+)?/);
  if (match === null) return null;
  const parsed = Number.parseFloat(match[0]);
  return Number.isFinite(parsed) ? parsed : null;
}

// ─── Small helpers ─────────────────────────────────────────────────────────

interface ImageDimensions {
  width: number;
  height: number;
  format: string;
}

function imageDimensions(bytes: Uint8Array): ImageDimensions | null {
  // PNG: 8-byte signature, then IHDR (width/height as big-endian uint32 at
  // 16 and 20).
  if (
    bytes.length >= 24 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47
  ) {
    const data = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return {
      width: data.getUint32(16, false),
      height: data.getUint32(20, false),
      format: "png",
    };
  }

  // JPEG: walk the markers until a Start-Of-Frame carries the dimensions.
  if (bytes.length > 4 && bytes[0] === 0xff && bytes[1] === 0xd8) {
    let i = 2;
    while (i + 9 <= bytes.length) {
      if (bytes[i] !== 0xff) {
        i++;
        continue;
      }
      const marker = bytes[i + 1];
      if (
        marker === 0xd8 ||
        marker === 0x01 ||
        (marker >= 0xd0 && marker <= 0xd7)
      ) {
        i += 2;
        continue;
      }
      const segmentLength = (bytes[i + 2] << 8) | bytes[i + 3];
      const isStartOfFrame =
        marker >= 0xc0 &&
        marker <= 0xcf &&
        marker !== 0xc4 &&
        marker !== 0xc8 &&
        marker !== 0xcc;
      if (isStartOfFrame) {
        return {
          width: (bytes[i + 7] << 8) | bytes[i + 8],
          height: (bytes[i + 5] << 8) | bytes[i + 6],
          format: "jpeg",
        };
      }
      if (segmentLength <= 0) break;
      i += 2 + segmentLength;
    }
  }

  return null;
}

/// `value?.toString()` — Dart's null-aware stringify: absent and explicit
/// null are the same thing, and neither is the string "null".
function textOrNull(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  return String(value);
}

function isMap(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asList(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asNumList(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((v): v is number => typeof v === "number")
    .map((v) => v);
}

function asStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((v) => String(v));
}

function asInt(value: unknown): number | null {
  return typeof value === "number" ? Math.trunc(value) : null;
}

function size(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MiB`;
}

function num(value: number): string {
  return value
    .toString()
    .replace(/(\d)(?=(\d{3})+$)/g, (_, digit: string) => `${digit},`);
}

function mm(value: number): string {
  return `${value.toFixed(1)} mm`;
}

function mmSigned(value: number): string {
  return `${value >= 0 ? "+" : ""}${value.toFixed(1)} mm`;
}
