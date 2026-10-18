# ✅ Release Checklist

> Run this before stamping any `vX.Y.Z`. Each item is a lesson that was learned the hard way — the reference says where. **#project/solevision**

---

1. **Signed with the project key, not the debug keystore.** A `--release` build without `android/key.properties` silently falls back to the debug key and is uninstallable-over — see [[docs/RELEASE_SIGNING|Release signing]]. Verify the installed certificate before publishing.
2. **In-app update still offered and still installable.** The update overlay + What's New banner must show for release builds and explain themselves on dev builds — `lib/utils/in_app_update_eligibility.dart` decides; never re-add a browser fallback for a blocked case (a test asserts the copy).
3. **`releases/version.json` + `releases/changelog.json` bumped** (version, apk_url, released_at, customer-readable notes). The vault's [[obsidian/MOCs/08 - Roadmap, Logs & History|🗺️ MOC 08]] release list follows these files.
4. **Vault updated per the session-end rule** ([[obsidian/README|vault README §5]]): Home context, Tasks Done, MOC 08 release line, area-MOC rows for behavior changes.
5. **Full suites green** — `flutter test` (~2,770) plus the JVM try-on suites. A passing filter pipe is not a passing test: preserve exit status (`pipefail`).
6. **TEMP-DIAG removed.** No probe lines, no QA dart-defines in the published APK — grep for `TEMP-DIAG` and `dots-probe` before stamping.

## 🔗 Related

- [[docs/RELEASE_SIGNING|Release signing]]
- [[obsidian/Decision Log|📜 Decision Log]] — why the update guard and single key exist
- [[obsidian/MOCs/08 - Roadmap, Logs & History|🗺️ Roadmap, Logs & History]]
