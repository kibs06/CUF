# Limitation: AR foot scan — camera brightness and floor detection vary by phone

**Status:** open. Observed on one test phone; not yet reproduced across devices.
**Area:** AR foot scan (`lib/screens/customer/foot_size_v2/`, `android/app/src/main/kotlin/com/solevision/app/arfoot/`).
**Recorded:** 2026-10-09.

## What was observed

Phones do not behave the same in the AR foot scan:

- **Camera brightness differs by phone.** Some phones show a normal image in the same room; others show a dark image. On the dark ones, the floor is hard to find.
- **Floor detection is unreliable on some phones.** The scan sits on "Looking for the floor…" and does not lock.
- **Surface matters.** On the test phone, the floor was wet and glossy. The floor was found about 12% of the time after the latest change, which is too low to rely on.

## What we know

- ARCore builds a floor plane from visual feature points. A dim, noisy, or glossy surface gives it few points, so the plane may never form.
- The scan only accepts a floor plane that faces upward (`HORIZONTAL_UPWARD_FACING`) and needs at least 3 of 5 floor probes to hit it.
- On the test phone, ARCore repeatedly reported `VIO Tracking state is not tracking` and missed camera frames during the search.
- A render-path problem was found and fixed in our code: the app converted a full camera frame every 150 ms while still searching, which stalled ARCore. Full conversion now happens only during capture. This reduced stalls and raised the floor hit rate, but did not make detection reliable.

## What was done in response

- A torch button and a "too dark to see the floor" hint were added for dim rooms (`ArFootSizingView.kt`, `foot_scan_session_screen_v2.dart`).
- The torch helps only where the room is dark. It does not fix a glossy floor or a camera that renders a dim image in a lit room.

## What is not known

- Whether the phones that look dark are dark because of their camera, their ARCore version, or their auto-exposure.
- Whether the same floor works on a dry, matte, textured surface. This has not been tested.
- Whether the remaining failures come from the phone's ARCore tracking, from the floor, or both.

## Workaround for customers and testers

- Scan on a dry, matte floor with visible texture and good light.
- If the floor is dark or glossy, turn on the torch.
- Use **Manual placement** only where it is offered; it does not replace a detected floor.

## Next steps to close this

1. Repeat the scan on a dry, textured floor and record whether the floor locks.
2. Log the same scan on each phone model that behaves differently and compare brightness and tracking.
3. Check the ARCore version on each phone and whether the phone supports the depth API.
4. Decide whether to keep the torch as a permanent control or only show it when the room is dark.

## Where the evidence is

- Phone log captures from the test session were saved under `.artifacts/` (`scan-capture.log`, `scan-capture2.log`). These are local and not committed.
