#!/usr/bin/env node
// tool/check_glb_validator_parity.mjs
//
// Proves the two copies of the shoe-model rule set still agree.
//
// `lib/utils/glb_validator.dart` (reference, used by the CLI and the seller
// form) and `supabase/functions/_shared/glb_validator.ts` (the mirror used by
// the `validate-shoe-model` Edge Function, V2.4) are separate implementations
// of one contract, because an Edge Function cannot import Dart. Everything in
// V2.4 rests on them answering the same thing: a partner who runs the CLI,
// uploads, and gets a different verdict has been told two truths.
//
// This script runs both over the same bytes — the repo's bundled models, the
// androidTest compression fixtures, and synthetic GLBs built here to reach the
// failure branches (millimetre units, a Z-up export, external references, an
// oversized texture, a triangle overrun, no declared length) — and diffs the
// reports: check names, order, statuses, detail text, notes, and the two
// measured numbers. A divergence exits 1 with the differing field named.
//
//   node tool/check_glb_validator_parity.mjs
//
// Node 24 runs the `.ts` mirror directly (type stripping), so there is no
// build step and no Deno needed. Numbers are compared with a tolerance:
// JSON has one number type and Dart has two, so the Dart side prints
// meshExternalLengthMm as `269.0` where JavaScript prints `269`.

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const fixtureDir = join(repoRoot, "build", "glb_parity");

const { validateGlb } = await import(
  pathToFileURL(join(repoRoot, "supabase/functions/_shared/glb_validator.ts"))
    .href
);

// ─── GLB assembly (the smallest writer that produces valid containers) ─────

/** Wraps a glTF JSON document in a GLB container, optionally with a BIN. */
function buildGlb(json, bin = null) {
  const jsonBytes = Buffer.from(JSON.stringify(json), "utf8");
  const padTo4 = (length, filler) =>
    (4 - (length % 4)) % 4 === 0
      ? Buffer.alloc(0)
      : Buffer.alloc((4 - (length % 4)) % 4, filler);

  const jsonPadded = Buffer.concat([jsonBytes, padTo4(jsonBytes.length, 0x20)]);
  const chunks = [jsonChunk(jsonPadded)];
  if (bin !== null) {
    chunks.push(binChunk(Buffer.concat([bin, padTo4(bin.length, 0x00)])));
  }

  const body = Buffer.concat(chunks);
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(12 + body.length, 8);
  return Buffer.concat([header, body]);
}

function jsonChunk(padded) {
  const header = Buffer.alloc(8);
  header.writeUInt32LE(padded.length, 0);
  header.writeUInt32LE(0x4e4f534a, 4);
  return Buffer.concat([header, padded]);
}

function binChunk(padded) {
  const header = Buffer.alloc(8);
  header.writeUInt32LE(padded.length, 0);
  header.writeUInt32LE(0x004e4942, 4);
  return Buffer.concat([header, padded]);
}

/** A 24-byte PNG header carrying real dimensions — enough for both parsers. */
function pngHeader(width, height) {
  const bytes = Buffer.alloc(24);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(bytes, 0);
  bytes.writeUInt32BE(width, 16);
  bytes.writeUInt32BE(height, 20);
  return bytes;
}

// ─── Synthetic documents: one per branch the fixtures cannot reach ────────

/** A metres-scaled, Y-up shoe with the two required parts and 300 triangles. */
function shoeJson({
  metres = true,
  min = null,
  max = null,
  materials = [{ name: "upper" }, { name: "sole" }],
  triangles = 300,
  extensions = null,
} = {}) {
  const scale = metres ? 1 : 1000;
  const json = {
    asset: { version: "2.0", generator: "parity checker" },
    scene: 0,
    scenes: [{ nodes: [0] }],
    nodes: [{ mesh: 0, name: "shoe" }],
    meshes: [
      {
        name: "shoe",
        primitives: [
          {
            attributes: { POSITION: 0 },
            indices: 1,
            material: 0,
            mode: 4,
          },
        ],
      },
    ],
    accessors: [
      {
        bufferView: 0,
        componentType: 5126,
        count: 3,
        type: "VEC3",
        min: min ?? [-0.045 * scale, 0, 0],
        max: max ?? [0.045 * scale, 0.095 * scale, 0.269 * scale],
      },
      { bufferView: 1, componentType: 5125, count: triangles * 3, type: "SCALAR" },
    ],
    bufferViews: [
      { buffer: 0, byteOffset: 0, byteLength: 36 },
      { buffer: 0, byteOffset: 36, byteLength: 12 },
    ],
    buffers: [{ byteLength: 48 }],
  };
  if (materials !== null) json.materials = materials;
  if (extensions !== null) {
    json.extensionsUsed = extensions;
    json.extensionsRequired = extensions;
  }
  return json;
}

/** Adds one embedded image texture of the given size to a shoe document. */
function withTexture(json, width, height) {
  const image = pngHeader(width, height);
  const jsonWithoutBuffer = structuredClone(json);
  jsonWithoutBuffer.bufferViews.push({
    buffer: 0,
    byteOffset: 48,
    byteLength: image.length,
  });
  jsonWithoutBuffer.images = [{ bufferView: 2, mimeType: "image/png" }];
  jsonWithoutBuffer.buffers[0].byteLength = 48 + image.length;
  return { json: jsonWithoutBuffer, bin: Buffer.concat([Buffer.alloc(48), image]) };
}

const cases = [];

function addCase(name, { path = null, bytes = null, declaredMm = null }) {
  cases.push({ name, path: path ?? join(".parity", `${name}.glb`), bytes, declaredMm });
}

// 1. The two bundled models and the androidTest compression fixtures — real
//    bytes, exercising structure, materials, textures and the compression gate.
for (const [name, relative, declared] of [
  ["placeholder", "assets/models/placeholder_shoe.glb", 270],
  ["placeholder-no-declaration", "assets/models/placeholder_shoe.glb", null],
  ["androidTest-placeholder", "android/app/src/androidTest/assets/placeholder_shoe.glb", 270],
  ["androidTest-draco", "android/app/src/androidTest/assets/placeholder_shoe_draco.glb", 270],
  ["androidTest-meshopt", "android/app/src/androidTest/assets/placeholder_shoe_meshopt.glb", 270],
]) {
  addCase(name, { path: relative, declaredMm: declared });
}

// 2. Structure failures.
addCase("not-a-glb", { bytes: Buffer.from("PK\u0003\u0004 this is a zip, not a glb") });
addCase("truncated-header", { bytes: Buffer.from([0x67, 0x6c, 0x54, 0x46, 0x02]) });
addCase("wrong-version", {
  bytes: (() => {
    const bytes = buildGlb({ asset: { version: "2.0" } });
    bytes.writeUInt32LE(1, 4);
    return bytes;
  })(),
});
addCase("bad-asset-version", {
  bytes: buildGlb({ asset: { version: "1.0" } }),
});
addCase("external-buffer", {
  bytes: buildGlb({
    ...shoeJson({}),
    buffers: [{ uri: "shoe.bin", byteLength: 48 }],
  }),
  declaredMm: 269,
});

// 3. Geometry failures, all through the accessor min/max the bbox reads.
addCase("millimetres", {
  bytes: buildGlb(shoeJson({ metres: false })),
  declaredMm: 269,
});
addCase("z-up-export", {
  bytes: buildGlb(
    shoeJson({ min: [-0.045, 0, 0], max: [0.045, 0.269, 0.095] }),
  ),
  declaredMm: 269,
});
addCase("off-origin", {
  bytes: buildGlb(
    shoeJson({ min: [-0.045, 0.012, -0.138], max: [0.045, 0.107, 0.131] }),
  ),
  declaredMm: 269,
});
addCase("scale-drift", {
  bytes: buildGlb(shoeJson({})),
  declaredMm: 255,
});
addCase("unreferenced-mesh", {
  bytes: buildGlb({
    ...shoeJson({}),
    nodes: [{ mesh: 0 }],
    meshes: [shoeJson({}).meshes[0], shoeJson({}).meshes[0]],
  }),
  declaredMm: 269,
});
addCase("no-position-min-max", {
  bytes: buildGlb({
    ...shoeJson({}),
    accessors: [
      { bufferView: 0, componentType: 5126, count: 3, type: "VEC3" },
      { bufferView: 1, componentType: 5125, count: 900, type: "SCALAR" },
    ],
  }),
  declaredMm: 269,
});

// 4. Materials and the triangle cap.
addCase("no-materials", {
  bytes: buildGlb(shoeJson({ materials: null })),
  declaredMm: 269,
});
addCase("blender-default-names", {
  bytes: buildGlb(shoeJson({ materials: [{ name: "Material.001" }] })),
  declaredMm: 269,
});
addCase("too-many-triangles", {
  bytes: buildGlb(shoeJson({ triangles: 60001 })),
  declaredMm: 269,
});

// 5. Textures, and the extension gate.
addCase("oversized-texture", {
  bytes: (() => {
    const texture = withTexture(shoeJson({}), 2048, 2048);
    return buildGlb(texture.json, texture.bin);
  })(),
  declaredMm: 269,
});
addCase("ok-texture", {
  bytes: (() => {
    const texture = withTexture(shoeJson({}), 1024, 1024);
    return buildGlb(texture.json, texture.bin);
  })(),
  declaredMm: 269,
});
addCase("draco-declared", {
  bytes: buildGlb(shoeJson({ extensions: ["KHR_draco_mesh_compression"] })),
  declaredMm: 269,
});

// ─── Run both, diff ───────────────────────────────────────────────────────

mkdirSync(fixtureDir, { recursive: true });

/**
 * The Dart executable to use. On Windows the shim on PATH for a non-shell
 * spawn is `dart.bat`, not the extension-less bash script beside it, so the
 * invocation is shell-mediated unless DART names a real executable.
 */
function dartInvocation() {
  if (process.env.DART) return { file: process.env.DART, shell: false };
  if (process.platform === "win32") return { file: "dart.bat", shell: true };
  return { file: "dart", shell: false };
}

/** Runs the Dart reference (the CLI, so the comparison is against the shipped executable form). */
function dartReport(testCase, filePath) {
  const args = ["run", "tool/validate_glb.dart", "--json"];
  if (testCase.declaredMm !== null) {
    args.push("--external-length-mm", String(testCase.declaredMm));
  }
  args.push(filePath);
  const { file, shell } = dartInvocation();
  // Exit 1 is a failing report, not a failing command (exit 2 is the CLI
  // saying it could not run) — so the exit code is checked, not thrown on.
  const result = spawnSync(file, shell ? args.map(quoteForShell) : args, {
    cwd: repoRoot,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    shell,
  });
  if (result.error) {
    throw new Error(`could not run the Dart CLI: ${result.error.message}`);
  }
  if (result.status === 2) {
    throw new Error(`the Dart CLI could not run ${filePath}: ${result.stderr}`);
  }
  const stdout = result.stdout ?? "";
  const start = stdout.indexOf("{");
  if (start < 0) {
    throw new Error(`no JSON report from the Dart CLI on ${filePath}: ${stdout}`);
  }
  return JSON.parse(stdout.slice(start));
}

function quoteForShell(argument) {
  return /[\s&()^|<>]/.test(argument) ? `"${argument}"` : argument;
}

/** Runs the TypeScript mirror over the same bytes, labelled the same way. */
function tsReport(testCase, bytes) {
  return validateGlb(new Uint8Array(bytes), {
    label: testCase.path,
    externalLengthMm: testCase.declaredMm,
  }).toJson();
}

const NUMBER_TOLERANCE = 1e-6;

/** Compares two decoded reports, naming the first divergence by path. */
function diff(a, b, path = "") {
  if (typeof a !== typeof b) return `${path}: ${typeof a} vs ${typeof b}`;
  if (typeof a === "number") {
    return Math.abs(a - b) <= NUMBER_TOLERANCE
      ? null
      : `${path}: ${a} vs ${b}`;
  }
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b)) return `${path}: array vs object`;
    if (a.length !== b.length) return `${path}: ${a.length} items vs ${b.length}`;
    for (let i = 0; i < a.length; i++) {
      const found = diff(a[i], b[i], `${path}[${i}]`);
      if (found !== null) return found;
    }
    return null;
  }
  if (a !== null && b !== null && typeof a === "object") {
    const keys = [...new Set([...Object.keys(a), ...Object.keys(b)])];
    for (const key of keys) {
      const found = diff(a[key], b[key], path === "" ? key : `${path}.${key}`);
      if (found !== null) return found;
    }
    return null;
  }
  return a === b ? null : `${path}: ${JSON.stringify(a)} vs ${JSON.stringify(b)}`;
}

let failures = 0;
const rows = [];

for (const testCase of cases) {
  const filePath = join(repoRoot, testCase.path);
  if (testCase.bytes !== null) {
    mkdirSync(dirname(filePath), { recursive: true });
    writeFileSync(filePath, testCase.bytes);
  }
  const bytes = readFileSync(filePath);
  const reference = dartReport(testCase, testCase.path);
  const mirror = tsReport(testCase, bytes);
  const difference = diff(reference, mirror);
  if (difference !== null) failures++;
  rows.push({
    name: testCase.name,
    verdict: reference.passed
      ? "PASS"
      : `FAIL ${reference.checks.filter((c) => c.status === "fail").length}`,
    checks: reference.checks.length,
    notes: reference.notes.length,
    difference,
  });
}

const width = Math.max(...rows.map((r) => r.name.length));
console.log(`GLB validator parity — ${rows.length} cases`);
console.log("");
for (const row of rows) {
  console.log(
    `  ${row.difference === null ? "same" : "DIFF"}  ${row.name.padEnd(width)}  ` +
      `${row.verdict.padEnd(7)}  ${row.checks} checks, ${row.notes} notes` +
      `${row.difference === null ? "" : `\n        differs at ${row.difference}`}`,
  );
}
console.log("");
if (failures === 0) {
  console.log(
    `RESULT: the Dart reference and the TypeScript mirror agree on all ${rows.length} cases ` +
      "(check names, order, statuses, detail text, notes and measured numbers).",
  );
} else {
  console.log(
    `RESULT: ${failures} of ${rows.length} cases differ — the Edge Function (V2.4) and the ` +
      "CLI/form (V2.7/V2.3) would tell a partner different things.",
  );
}
process.exit(failures === 0 ? 0 : 1);
