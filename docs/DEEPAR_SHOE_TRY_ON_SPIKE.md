# DeepAR shoe try-on spike — solo test (free ≤10 MAU)

Custom tracker is parked. This spike uses DeepAR instead — no native SDK in
the build yet, only the config seam (`lib/services/deepar_try_on.dart`).

## 0. What "free to 10 MAU" means for you

- 1 MAU = 1 distinct person using a DeepAR feature that month (you = 1 MAU).
- Solo testing on 1 phone never caps. Free build shows a watermark.
- Paid starts at $25/mo (1,000 MAU). Only needed for beta/customers.

## 1. Get keys (5 min, on your machine — not CI)

1. Sign up at https://developer.deepar.ai → Create project → copy the
   **Android** key (and iOS key if you test iPhone).
2. Copy `dart_defines.json.example` → `dart_defines.json` (git-ignored), fill:
   `DEEPAR_ANDROID_KEY`, `DEEPAR_IOS_KEY`. Never commit this file.

## 2. Make the shoe effect in DeepAR Studio (free desktop app)

1. Download Studio: https://www.deepar.ai/creator (Win/macOS, free).
2. New project → **Shoe try-on template** (foot-tracking demo).
3. Replace sample shoe with one CUFMAI `.glb` (brown sandal first):
   import → toe to +Z, reset transforms, align to foot occluder.
4. Preview on device via QR (Android works; iOS foot preview had issues
   in 2023 — test Android first).
5. Export: `File` → `Export effect` → `brown_sandal.deepar`.
   Place at `assets/effects/deepar_<productId>.deepar` for the spike.

## 3. Run the spike

```bash
flutter run --dart-define-from-file=dart_defines.json
```

- `deepArConfigured` is false until keys exist → UI keeps 3D box, no crash.
- Once effect file exists, next step wires `deepar_flutter_plus`:
  `android/app/libs/deepar.aar` + `pubspec` dep + `DeepArPreview` screen.
  That step is intentionally NOT in this commit (needs the .aar download).

## 4. Decide

Same phone, same foot distance (~1m, ankle + toes framed):
- locks fast + occlusion reads as "inside shoe" → promote to beta (paid plan).
- jitters / wrong scale → try Snap Lens Studio footwear template instead
  (`customer-portal/docs/BUILD_LENS.md` — already half-integrated).
