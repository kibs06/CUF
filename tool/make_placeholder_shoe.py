#!/usr/bin/env python3
"""Generate assets/models/placeholder_shoe.glb — the V0 renderer-spike fixture.

THIS IS NOT A PRODUCT ASSET. It is a block-out used to prove that the native
glTF renderer works, and to measure model load time, frame rate and APK size
delta (docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md, V0.1/V0.5/V0.6). The real
assets come from photogrammetry of the physical pair — see
docs/RoadMap/SHOE_MODEL_AUTHORING_GUIDE.md.

It nevertheless obeys the contract it exists to validate, so the spike
exercises the same code path a real asset will:

  * metres, Y-up, heel-bottom-centre at the origin, toe along +Z
  * true dimensions: EU 42, external length 270 mm
  * part-named materials: "upper" and "sole"
  * one shoe, uncompressed single-file GLB, low triangle count

Run:  python tool/make_placeholder_shoe.py
      (writes assets/models/placeholder_shoe.glb and prints a summary)
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

OUT_PATH = Path(__file__).resolve().parent.parent / "assets" / "models" / "placeholder_shoe.glb"

# ── Contract constants ────────────────────────────────────────────────────────
LENGTH_M = 0.270          # EU 42 external heel-to-toe length
SOLE_HEIGHT_M = 0.018     # sole slab thickness
SECTIONS = 24             # rings along the length (heel → toe)
RING_POINTS = 16          # points around each cross-section
SUPERELLIPSE_P = 4.0      # 2 = ellipse, higher = flatter sides / boxier

# t (0 = heel, 1 = toe) → half-width of the sole outline, metres
HALF_WIDTH_PROFILE = [
    (0.00, 0.034),
    (0.10, 0.036),
    (0.25, 0.034),   # waist
    (0.45, 0.036),
    (0.62, 0.0475),  # ball of the foot — widest
    (0.75, 0.046),
    (0.88, 0.036),
    (1.00, 0.019),
]

# t → total shoe height (sole + upper), metres
HEIGHT_PROFILE = [
    (0.00, 0.092),
    (0.06, 0.095),   # heel collar
    (0.15, 0.090),
    (0.30, 0.078),
    (0.45, 0.068),
    (0.62, 0.056),
    (0.78, 0.042),
    (0.90, 0.032),
    (1.00, 0.030),
]


def lerp_profile(profile: list[tuple[float, float]], t: float) -> float:
    """Piecewise-linear sample of a (t, value) profile."""
    if t <= profile[0][0]:
        return profile[0][1]
    for (t0, v0), (t1, v1) in zip(profile, profile[1:]):
        if t <= t1:
            f = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return v0 + (v1 - v0) * f
    return profile[-1][1]


def ring_points(
    z: float, half_width: float, y_bottom: float, y_top: float, k: int = RING_POINTS
) -> list[tuple[float, float, float]]:
    """A closed superellipse cross-section in the XY plane at depth z.

    Bottom is flat-ish (y_bottom), top is flat-ish (y_top), sides are the
    superellipse — the shape of a shoe's cross-section, roughly.
    """
    cy = (y_bottom + y_top) / 2.0
    hy = (y_top - y_bottom) / 2.0
    pts = []
    for i in range(k):
        theta = 2.0 * math.pi * i / k
        c, s = math.cos(theta), math.sin(theta)
        x = half_width * math.copysign(abs(s) ** (2.0 / SUPERELLIPSE_P), s)
        y = cy + hy * math.copysign(abs(c) ** (2.0 / SUPERELLIPSE_P), c)
        pts.append((round(x, 6), round(y, 6), round(z, 6)))
    return pts


def loft(
    half_width_scale: float, y_from: float, y_to_profile: bool
) -> tuple[list[tuple[float, float, float]], list[tuple[int, int, int]]]:
    """Build a closed tube along +Z from a bottom ring to a top ring.

    `y_from` is the bottom of the tube; the top comes from HEIGHT_PROFILE when
    `y_to_profile` is True, otherwise the tube has constant height SOLE_HEIGHT_M.
    """
    rings: list[list[tuple[float, float, float]]] = []
    for i in range(SECTIONS):
        t = i / (SECTIONS - 1)
        z = t * LENGTH_M
        hw = lerp_profile(HALF_WIDTH_PROFILE, t) * half_width_scale
        y_top = lerp_profile(HEIGHT_PROFILE, t) if y_to_profile else y_from + SOLE_HEIGHT_M
        rings.append(ring_points(z, hw, y_from, y_top))

    # Vertices first, then quads → triangles.
    vertices: list[tuple[float, float, float]] = []
    for ring in rings:
        vertices.extend(ring)

    def idx(ring_i: int, point_i: int) -> int:
        return ring_i * RING_POINTS + point_i

    triangles: list[tuple[int, int, int]] = []
    for r in range(SECTIONS - 1):
        for p in range(RING_POINTS):
            pn = (p + 1) % RING_POINTS
            a, b = idx(r, p), idx(r, pn)
            c, d = idx(r + 1, pn), idx(r + 1, p)
            triangles.append((a, b, c))
            triangles.append((a, c, d))

    # End caps: fan from the ring centroid (the outline is star-convex).
    for ring_i, flip in ((0, False), (SECTIONS - 1, True)):
        ring = rings[ring_i]
        cx = sum(p[0] for p in ring) / RING_POINTS
        cy = sum(p[1] for p in ring) / RING_POINTS
        cz = sum(p[2] for p in ring) / RING_POINTS
        center_i = len(vertices)
        vertices.append((round(cx, 6), round(cy, 6), round(cz, 6)))
        for p in range(RING_POINTS):
            pn = (p + 1) % RING_POINTS
            a, b = idx(ring_i, p), idx(ring_i, pn)
            triangles.append((center_i, b, a) if flip else (center_i, a, b))

    return vertices, triangles


def compute_normals(
    vertices: list[tuple[float, float, float]], triangles: list[tuple[int, int, int]]
) -> list[tuple[float, float, float]]:
    """Area-weighted per-vertex normals (smooth shading)."""
    acc = [[0.0, 0.0, 0.0] for _ in vertices]
    for i0, i1, i2 in triangles:
        p0, p1, p2 = vertices[i0], vertices[i1], vertices[i2]
        ux, uy, uz = (p1[j] - p0[j] for j in range(3))
        vx, vy, vz = (p2[j] - p0[j] for j in range(3))
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        for i in (i0, i1, i2):
            acc[i][0] += nx
            acc[i][1] += ny
            acc[i][2] += nz

    normals = []
    for n in acc:
        length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
        if length < 1e-9:
            normals.append((0.0, 1.0, 0.0))
        else:
            normals.append(
                (round(n[0] / length, 6), round(n[1] / length, 6), round(n[2] / length, 6))
            )
    return normals


class BufferBuilder:
    """Accumulates 4-byte-aligned binary data and hands out accessor metadata."""

    def __init__(self) -> None:
        self.data = bytearray()
        self.accessors: list[dict] = []
        self.buffer_views: list[dict] = []

    def _align(self) -> None:
        while len(self.data) % 4:
            self.data.append(0)

    def add_vec3(self, values: list[tuple[float, float, float]], include_bounds: bool) -> int:
        self._align()
        offset = len(self.data)
        flat = [c for v in values for c in v]
        self.data.extend(struct.pack(f"<{len(flat)}f", *flat))
        count = len(values)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": count * 12, "target": 34962}
        self.buffer_views.append(view)
        accessor = {
            "bufferView": len(self.buffer_views) - 1,
            "componentType": 5126,  # FLOAT
            "count": count,
            "type": "VEC3",
        }
        if include_bounds:
            accessor["min"] = [round(min(v[i] for v in values), 6) for i in range(3)]
            accessor["max"] = [round(max(v[i] for v in values), 6) for i in range(3)]
        self.accessors.append(accessor)
        return len(self.accessors) - 1

    def add_indices(self, triangles: list[tuple[int, int, int]]) -> int:
        self._align()
        offset = len(self.data)
        flat = [i for tri in triangles for i in tri]
        self.data.extend(struct.pack(f"<{len(flat)}H", *flat))
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(flat) * 2, "target": 34963}
        self.buffer_views.append(view)
        self.accessors.append(
            {
                "bufferView": len(self.buffer_views) - 1,
                "componentType": 5123,  # UNSIGNED_SHORT
                "count": len(flat),
                "type": "SCALAR",
            }
        )
        return len(self.accessors) - 1


def build_glb() -> tuple[bytes, dict]:
    builder = BufferBuilder()
    primitives = []

    # Sole first (material 0), then upper (material 1) — the two part names the
    # authoring guide requires a real asset to carry.
    for name, hw_scale, y_from, to_profile in (("sole", 1.0, 0.0, False), ("upper", 0.97, SOLE_HEIGHT_M, True)):
        vertices, triangles = loft(hw_scale, y_from, to_profile)
        normals = compute_normals(vertices, triangles)
        primitives.append(
            {
                "attributes": {
                    "POSITION": builder.add_vec3(vertices, True),
                    "NORMAL": builder.add_vec3(normals, False),
                },
                "indices": builder.add_indices(triangles),
                "material": 0 if name == "sole" else 1,
            }
        )

    gltf = {
        "asset": {"version": "2.0", "generator": "SoleVision placeholder shoe generator (V0 spike)"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "placeholder_shoe", "mesh": 0}],
        "meshes": [
            {
                "name": "placeholder_shoe",
                "primitives": primitives,
            }
        ],
        "materials": [
            {
                "name": "sole",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.10, 0.10, 0.11, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.85,
                },
            },
            {
                "name": "upper",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.72, 0.42, 0.24, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.6,
                },
            },
        ],
        "accessors": builder.accessors,
        "bufferViews": builder.buffer_views,
        "buffers": [{"byteLength": len(builder.data)}],
    }

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_pad = (4 - len(json_bytes) % 4) % 4
    json_chunk = json_bytes + b" " * json_pad

    bin_chunk = bytes(builder.data)
    bin_pad = (4 - len(bin_chunk) % 4) % 4
    bin_chunk = bin_chunk + b"\x00" * bin_pad

    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    glb = bytearray()
    glb.extend(struct.pack("<4sII", b"glTF", 2, total))
    glb.extend(struct.pack("<I4s", len(json_chunk), b"JSON"))
    glb.extend(json_chunk)
    glb.extend(struct.pack("<I4s", len(bin_chunk), b"BIN\x00"))
    glb.extend(bin_chunk)

    summary = {
        "triangles": sum(a["count"] // 3 for a in builder.accessors if a["type"] == "SCALAR"),
        "vertices": sum(a["count"] for a in builder.accessors if a["type"] == "VEC3" and "min" in a),
        "materials": [m["name"] for m in gltf["materials"]],
        "bbox_mm": {
            "length_z": round(max(a["max"][2] for a in builder.accessors if "max" in a) * 1000, 1),
            "width_x": round(
                (max(a["max"][0] for a in builder.accessors if "max" in a)
                 - min(a["min"][0] for a in builder.accessors if "min" in a)) * 1000, 1
            ),
            "height_y": round(max(a["max"][1] for a in builder.accessors if "max" in a) * 1000, 1),
        },
    }
    return bytes(glb), summary


def main() -> None:
    glb, summary = build_glb()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_bytes(glb)
    print(f"wrote {OUT_PATH} ({len(glb) / 1024:.1f} KB)")
    print(f"  triangles : {summary['triangles']}")
    print(f"  vertices  : {summary['vertices']}")
    print(f"  materials : {', '.join(summary['materials'])}")
    print(
        "  bbox      : "
        f"length {summary['bbox_mm']['length_z']} mm (Z), "
        f"width {summary['bbox_mm']['width_x']} mm (X), "
        f"height {summary['bbox_mm']['height_y']} mm (Y)"
    )
    print("  contract  : heel-bottom-centre at origin, toe +Z, metres, uncompressed")


if __name__ == "__main__":
    main()
