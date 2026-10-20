# Model orientation audit (Phase 1.4)

> Tool: `customer-portal/scripts/inspect-glb.mjs` (+ `inspect-math.mjs`).
> Method: apply viewer's `rotation.z = PI`, measure world-space bounds,
> longest horizontal axis, toe direction from 3 signals (height profile:
> heel counter taller; width profile: toe end wider; vertex density).
> Slide sandals: strap/upper at the TOE end.
> Confidence `agree` = all 3 signals same end; `disagree` = split.

| Product / file | Bounds size (x,y,z) | Long axis | Suggested forward_axis | Confidence |
|---|---|---|---|---|
| `assets/models/placeholder_shoe.glb` | 0.0943, 0.0942, 0.27 | z | +z | disagree (height→low, width→high, density→high) |
| `assets/models/qa_partner_shoe_v1.glb` | 0.1117, 0.1007, 0.27 | z | **-z** | agree (all 3 → low end) |
| `assets/models/bee24e2d9dbc7e61f3254e30eff44df4.contract.glb` | 0.1003, 0.068, 0.27 | z | +z | agree (all 3 → high end) |

## Findings

- **H1 confirmed in the wild:** `qa_partner_shoe_v1.glb` points its toe at
  **-Z** with all 3 signals agreeing, while the viewer assumes +Z. Rendered
  today it would wear **heel/toe swapped** — the exact strap-near-ankle
  symptom in the brown-sandal screenshots.
- `placeholder_shoe.glb` splits 1-vs-2 (height says low, width+density say
  high) → needs owner eyeball in "View in 3D" before assigning.
- Brown slide sandal (production `shoe-models` bucket) **not yet audited** —
  needs its public URL or `storage_path`. Owner: which product is it?

## Open questions for owner (STOP AND ASK)

1. Brown sandal product name / URL so it can be inspected the same way.
2. `placeholder_shoe.glb`: confirm toe direction visually (+z as suggested?).
3. Fixture recordings (debug `?footdebug=1` → "Save frames"): (a) foot
   top-down ~50 cm, (b) foot ~1.5 m with knee visible, (c) 45° side view.
