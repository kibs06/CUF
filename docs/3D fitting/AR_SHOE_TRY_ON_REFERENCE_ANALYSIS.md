# 3D Fitting: Reference Analysis

**Reference project:** AR Shoe Try-On System (Datathon Vietnam 2023, team QTHomeTown)
**Repository:** https://github.com/QuanHoangNgoc/AR-Shoe-Try-On-System-Datathon-QTHomeTown-
**Method paper:** *ARShoe: Real-Time Augmented Reality Shoe Try-on System on Smartphones*, ACM MM '21, DOI 10.1145/3474085.3481537, arXiv 2108.10515

This report covers what the reference project actually contains, the method its paper describes, and what our app should expect from a 3D fitting feature.

---

## 1. What the reference project is

- **Type:** a web demo, not a native app. It is a webpack + Bootstrap page (`package.json`) built on the **DeepAR** SDK (`deepar ^5.0.0`).
- **Flow (`src/index.js`):**
  1. A product card click stores an effect name in `sessionStorage` and reloads the page.
  2. The page calls `deepar.initialize` with `effects/<name>`, a rear camera (`facingMode: "environment"`), and `hint: "footInit"`.
  3. `onFeetTracked` hides the "feet not found" prompt once a foot is detected.
- **Size:** the whole client is one ~3 KB script. There are no install steps in the README ("will be provided"), no effect files (`.deepar`) in the repo, and no CNN training code.
- **Other files:** `Datathon_Summary.pdf` (58 KB) and `Vietnam_Datathon_2023.pdf` (33 MB, the competition deck). My tools could not extract text from the PDF, so its contents are unverified.
- **The demo's core is DeepAR's foot tracker.** The team's own contribution is the product-to-effect mapping and the page flow. The CNN model described in the README is not in the repo.

## 2. The method in the paper (ARShoe)

| Requirement | ARShoe paper | Reference demo |
| --- | --- | --- |
| Foot pose | Multi-branch encoder-decoder predicts 8 keypoints per foot and PAFs for grouping. PnP gives 6-DoF pose from 2D keypoints and camera intrinsics. | DeepAR `footInit` tracker (closed source) |
| Occlusion | Leg segmentation mask, combined with the shoe's silhouette and a transparent opening, cuts the leg over the shoe. | Not visible in the demo |
| Stabilization | FAST corners tracked with bidirectional optical flow inside the foot mask. Pose blended with weights from reprojection error. Kalman and One Euro filters were tested and rejected. | DeepAR internal |
| Speed | Over 30 FPS on common phones, 256×256 inputs. | Not measured |
| Data | 86,040 annotated foot images, about 3M after augmentation. | Not published |

Notable paper details:
- Stabilization blends quaternions and translations with weight `w_R = 0.432·ln(D) + 2.388`, where `D` is the L1 reprojection difference of the shoe model between frames. The weights are empirical.
- The paper says there was no open-source virtual shoe try-on project at the time. The reference repo does not publish the paper's code either.

## 3. What our app should expect

The reference demo sets the expectation: a customer picks a shoe and sees it on their foot through the camera, the shoe stays put, and the leg covers the shoe opening. Our app already has most of the pieces. Status is taken from the code and commits I reviewed.

| Expected behaviour | Our app | Status |
| --- | --- | --- |
| Shoe follows the foot in real time | Detector plus between-frame tracking (`FootFlow`, commit 98e7f6b), eased anchor in `ArTryOnView` | Built. Between-frame tracking was added recently. |
| Real camera background | `ArCameraFeed`: ARCore OES texture drawn by Filament | **Not working on device.** This is the open regression. |
| Leg occludes the shoe opening | `FootMaskOverlay` (V4.4), drawn with the camera feed's material | Built, but depends on the camera feed, so it is currently blocked. |
| Stable overlay | `FootSnapshotStabilizer`, `footTracker`, eased anchor | Built. Needs tuning on device. |
| Per-product 3D model | Per-product model (commit 4575768) | Built |
| 3D preview before AR | `PREVIEW` mode on the same renderer | Built |
| Diagnostics | `DiagRelay` and `nav_diag` log | Built. Useful for the device issues above. |

**Our advantage over the reference:** we use ARCore (world tracking, camera intrinsics, and depth) and Filament rendering, with no third-party tracking licence. The paper's PnP and optical-flow ideas map directly onto ARCore's pose and depth data.

## 4. Gaps and risks

1. **Hardcoded DeepAR licence key in client code.** The reference `src/index.js` ships a licence key in plain text. Do not copy it. Treat it as exposed. DeepAR is also a commercial SDK. Our native route avoids that dependency.
2. **Camera feed and frame stall (our current blocker).** The device log shows about 2,040 `beginFrame refused` lines, and the camera-feed reveal lines are missing. This is the open problem from the earlier investigation (commit 98e7f6b changed the feed's reveal logic).
3. **Occlusion depends on the camera feed.** Until the feed draws, the leg-over-shoe effect cannot be checked.
4. **Paper results are not measured on our devices.** The 30 FPS figure comes from the paper's test phones, not from our target devices.
5. **Reference demo has no fallback.** When no foot is detected it only shows a text prompt. Our app should keep the manual tap-to-place fallback (commit 5269001).

## 5. Recommended next steps

1. **Fix the camera feed and the frame stall first.** Occlusion and the realistic look both depend on them.
2. **Use the paper's stabilization idea as a tuning reference.** Compare our `FootFlow` carry-over with the paper's reprojection-weighted blend.
3. **Do not adopt DeepAR or copy its key.** Keep the ARCore and Filament route.
4. **Set on-device acceptance criteria.** These are proposals, not yet measured:
   - Foot tracked on the target phone (P30 Pro) for at least 80% of a 10-second walk-and-stop test.
   - Shoe stays within a few pixels of the foot during a 2-second still hold.
   - Camera background and leg occlusion visible in the same frame.
   - Presented frame rate of at least 25 FPS during tracking.
5. **Keep this report current.** Update section 3 after each device test.

## 6. Sources

- Reference repo, README, `package.json`, `src/index.js`: https://github.com/QuanHoangNgoc/AR-Shoe-Try-On-System-Datathon-QTHomeTown-
- ARShoe paper (arXiv HTML): https://arxiv.org/html/2108.10515
- ARShoe paper (abstract and metadata): https://arxiv.org/abs/2108.10515
- ACM DOI: https://doi.org/10.1145/3474085.3481537
