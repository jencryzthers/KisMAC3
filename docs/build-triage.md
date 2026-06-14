# KisMac3 — Build Triage (S0.1, post-S0.6 re-run)

This is the deliverable for task slice **S0.1 — Compile baseline: inventory & triage
build failures** (`docs/task-slices.md`), **re-run after S0.6** landed. It catalogues
the now-observable result of a clean Debug build of the legacy KisMAC2 project on the
current Xcode. **No source fixes were made** beyond the S0.6 Python de-indent — fixes
to C/Objective-C happen in slices S0.2–S0.5.

> **Status: this is the post-S0.6 re-run.** The original S0.1 build aborted in the
> very first build phase (`Update vendors.db`) on a Python `IndentationError`, masking
> all compiler output. **S0.6** (commit on this branch) fixed that script. With the
> script phase now passing, the KisMac2 application sources compile and link **and the
> build SUCCEEDS**. This re-run **overturns the original S0.1 prediction** that the
> removed-API items were hard compile/link-breakers: on this toolchain they are all
> still-declared **deprecated** APIs (warnings) or symbols still vended by a
> still-present system framework (link OK). See "Headline finding" below.

## Headline finding (changed conclusion)

**`** BUILD SUCCEEDED **` — 0 hard errors.** The KisMac2 Debug build is **green** on
Xcode 26.5 / macOS 27.0 once S0.6 unblocks the run-script phase. All 87 KisMac2
application source files compile; the app links against the system frameworks and a
runnable `KisMac2.app` is produced (unsigned).

The items the first S0.1 pass listed as *source-confirmed compile-breakers* did **not**
break the build:

- **`-[NSDate descriptionWithCalendarFormat:timeZone:locale:]`** is **not** removed on
  macOS 27.0 — it is still declared in `Foundation/NSCalendarDate.h` as
  `API_DEPRECATED("", macos(10.4,10.10))`. Result: a **deprecation warning**, not an
  error. (The `NSCalendarDate` *class* is unused in current source; only the still-live
  `NSDate` category method is called.)
- **`NSBeginAlertSheet` / `NSBeginCriticalAlertSheet` / `NSRunCriticalAlertPanel` /
  `NSRunAlertPanel` / `NSRunInformationalAlertPanel`** are all still declared in
  `AppKit` (`API_DEPRECATED(..., macos(10.0,10.10))`). Result: **warnings**, not errors.
- **`WirelessCryptMD5` / `WirelessEncrypt`** are **not** missing symbols. The
  `Sources/3rd Party/Apple80211.h` header declares them, and the system framework
  **`/System/Library/PrivateFrameworks/Apple80211.framework` is still present on
  macOS 27.0 and still exports `_WirelessCryptMD5`** (`nm` on the linked binary shows
  `T _WirelessCryptMD5`). So `WaveNetWEPWordlist.m:341` compiles **and** links. The
  two `WirelessEncrypt` call sites (`:87,:214`) are commented out and inert.

So the Wave-0 source work (S0.2–S0.5) is **not** "fix compile errors" — it is
**deprecation/warning cleanup + dead-code removal + the upstream parity decisions**.
The slices keep their scope (the deprecated calls still must be migrated and the dead
code still must be removed), but their *acceptance bar moves from "make it compile" to
"replace the deprecated API / remove the dead code without regressing the now-green
build"*. This should be reflected when those slices are picked up.

## Runtime smoke test (S0.1 runtime addendum)

After the green build, the produced app was launched directly from the build product to
confirm it reaches its runtime event loop — not just that it compiles. **Result: it
launches and runs clean.**

```
$ …/Build/Products/Debug/KisMac2.app/Contents/MacOS/KisMac2
2026-06-14 00:12:06 KisMac2[37734] KisMAC startup done. Version Alpha 4.
                    Build from Jun 14 2026 00:03:04. NSAppKitVersionNumber: 2757.5
2026-06-14 00:12:06 KisMac2[37734] Registering with Growl
2026-06-14 00:12:06 KisMac2[37734] Using native macOS notifications
Error Domain=kCLErrorDomain Code=1 "(null)"
```

| Check | Result |
|---|---|
| Process | **alive** (PID 37734), no early exit, left running |
| Crash reports | none in `~/Library/Logs/DiagnosticReports/` |
| AppKit init | reaches `applicationDidFinishLaunching` (startup-done log) on AppKit 2757.5 / macOS 27 |
| Notifications | **`Using native macOS notifications`** — the Growl→`NSUserNotification` migration works at runtime. (The preceding `Registering with Growl` is a stale log string, not a real Growl call — harmless; clean it up under S0.2.) |
| CoreLocation | **`kCLErrorDomain Code=1` (denied)** — runtime confirmation of the parity-audit gap: no authorization is requested and no `NSLocationWhenInUseUsageDescription` exists, so location fails closed. Owner: **S1.2**. |
| Code signature | ad-hoc / linker-signed (`codesign -dv` → `flags=0x20002(adhoc)`); bundle id `com.igrsoft.kismac`, min OS 13.0. |

**Limitation — no pixel capture.** This CLI context lacks **Screen Recording**
permission (`screencapture` → `could not create image from display`) and **Accessibility**
permission (System Events → `not allowed assistive access`), and no `Quartz` Python
module is available, so the window could not be screenshotted or introspected
automatically. Visual confirmation of the main window's appearance is therefore **deferred to
the human operator** (the window was left open for that). To enable automated GUI
capture later, grant Screen Recording (+ Accessibility) to the terminal app.

**Milestone-4 Definition-of-Done impact:** "Launches outside Xcode" is **partially
met** — the app launches from the unsigned build product and runs. The *signed*-launch
half (Developer ID + hardened runtime, so it runs after Gatekeeper/quarantine) remains
owned by **S8.x** (see ENV-1).

## Environment

| Item | Value |
|---|---|
| Xcode | 26.5 (build 17F42) |
| macOS | 27.0 (build 26A5353q) |
| Arch (host) | arm64 (Apple Silicon) |
| SDK | MacOSX26.5.sdk |
| Deployment target | macOS 13.0 |
| Scheme built | `KisMac2` (configuration Debug) |
| Build ARCHS | arm64 |
| Build log (this re-run) | `/tmp/kismac_build_rerun.log` |
| Build log (original S0.1, masked) | `/tmp/kismac_build_debug.log` |

Workspace schemes (`xcodebuild -workspace KisMac2.xcworkspace -list`):
`BIGeneric`, `BIGL`, `Kismac.dmg`, `KisMac2`. Main app scheme = `KisMac2`.

## How the build was run (re-run)

```
xcodebuild -workspace "…/KisMac3/KisMac2.xcworkspace" \
  -scheme KisMac2 -configuration Debug clean build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tee /tmp/kismac_build_rerun.log
```

> **Why signing was disabled:** the first attempt without those flags failed
> immediately at provisioning with `No signing certificate "Mac Development" found …
> matching team ID "DMP42GVPJ3"`. That is an environment/signing blocker (this repo
> lives in iCloud; codesign/xattr quirks are known) and masks all compile output. It is
> catalogued below as **ENV-1**. Re-running with signing disabled lets the full build
> run. Owner: S8.x.

`xcpretty` is not installed; output is raw `xcodebuild`.

### `Update vendors.db` run-script phase — now passes, no network needed

With the S0.6 fix in place the phase ran and **succeeded**. On this machine it printed:

```
Vendor Database exists, skip downloading
```

i.e. an existing `Resources/Generic/vendor.db` is present and fresh (younger than the
7-day `needForce` window) in a Debug build, so the script **skipped the IEEE OUI
download entirely** — no network access was attempted and the phase exited 0. The
expected network fetch was therefore **not** exercised in this run.

> **Environment caveat (not a blocker):** in a `Release` build, or if `vendor.db` is
> older than 7 days / missing, the script *will* hit
> `https://standards-oui.ieee.org/oui.txt`. The S0.6 commit hardened this path:
> `urlopen(..., timeout=30)`, a `try/except` around the download, and a
> `writeEmptyVendorDB` fallback that emits a valid empty plist so the build still
> succeeds offline. So even an offline/failed download no longer aborts the build. This
> was confirmed by code review, not exercised at build time here (the skip path ran).

---

## Update — post-S0.3 + S0.5 (warning burn-down)

> **S0.3 + S0.5 landed (done together, same files).** The numbers below are the
> original post-S0.6 S0.1 re-run baseline. After the S0.3/S0.5 migrations, on a
> **fresh clean Debug build** (Xcode 26.5 / macOS 27 / arm64, signing disabled),
> **deduplicated unique** warnings dropped:
>
> | Scope | Baseline (post-S0.6) | After S0.3+S0.5 | Δ |
> |---|---|---|---|
> | Whole-build unique warnings | 449 | **248** | −201 |
> | KisMac2 `Sources/` unique | 315 | **115** | −200 |
> | `Sources/` `-Wdeprecated-declarations` | 248 | **54** | −194 |
> | `Sources/` `-Wmisleading-indentation` | 6 | **0** | −6 |
>
> **Fully cleared symbols** (now 0 in `Sources/`): `NSOnState`/`NSOffState`,
> `NSFileHandlingPanelOKButton`, the whole `NSBeginAlertSheet`/`NSBeginCriticalAlertSheet`/
> `NSRunAlertPanel`/`NSRunCriticalAlertPanel`/`NSRunInformationalAlertPanel` alert
> family (→ `NSAlert`), `descriptionWithCalendarFormat:` (→ `strftime`/`WaveHelper`
> helper), `NSAlertDefault/Alternate/OtherReturn` (→ `NSAlertFirst/Second/Third`),
> `IOMasterPort` (→ `IOMainPort`), `NSCompositeSourceOver`/`Copy`, `NSPNG/JPEGFileType`,
> `NSCenterTextAlignment`, `NSWarningAlertStyle`, `NSLeftMouseUp(Mask)`/`Dragged(Mask)`,
> `NSTexturedBackgroundWindowMask`, `stringByAddingPercentEscapesUsingEncoding:`.
>
> **Remaining `Sources/` deprecated floor (54), by owner:** `NSDrawer` 17 + sheet/
> `NSUserNotification`/Carbon-Speech/`setMin/MaxSize:` (S5.x); `setAllowedFileTypes:`
> 15 + `imageFileTypes` 1 (UTType — kept, framework not linked, S5.x/S8.x);
> plist `propertyListFromData:`/`dataFromPropertyList:` 8 + `unarchiveObjectWith*` 2 +
> `dateWith*`/`CFPropertyListCreateFromXMLData` (S6.x/parse); CoreWLAN
> `interfaceNames`/`interfaceWithName:` 8 (S1.x). **Release build:** also green; product
> is **universal x86_64+arm64**. Fixed `OUItoVendorDB.py` so an HTTP-418/offline OUI
> download keeps the existing `vendor.db` and the Release build still passes. Fixed the
> S1.2 Location-denial modal so it never nags at launch on `notDetermined`. Full detail:
> `docs/task-slices.md` S0.3 + S0.5.

## Result summary

**`** CLEAN SUCCEEDED **` then `** BUILD SUCCEEDED **`.**

- **0 hard errors** anywhere in the build (KisMac2, BIGL, BIGeneric, GBStorage).
- All **87** KisMac2 application source files `CompileC`-compiled on arm64.
- The KisMac2 app **linked** and produced
  `…/Build/Products/Debug/KisMac2.app/Contents/MacOS/KisMac2` (1.5 MB, unsigned).
- **453** total warnings (up from 123 in the masked run, because KisMac2's own sources
  now compile and emit their warnings).

> Note: every literal `error:` token that appears in the log is inside *warning* text
> (e.g. `errorDescription:`, `errorString`) — there are **no** `… error:` diagnostics
> and no `Command … failed` lines.

### Counts

| Category | Hard errors | Warnings |
|---|---|---|
| KisMac2 app sources — deprecated declarations (`-Wdeprecated-declarations`) | 0 | 295 |
| KisMac2 app sources — other (logic/quality, see table) | 0 | 23 |
| BIGL / BIGeneric subprojects (OpenGL/AppKit/Carbon/misc) | 0 | 121 |
| GBStorage subproject | 0 | 3 |
| Run-script phase (Python) — **resolved by S0.6** | 0 | 0 |
| Linker (`-seg1addr` chained-fixups, BIGL/BIGeneric) | 0 | 2 (in the 121) |
| Environment / code signing (only when signing enabled) | 1 (ENV-1) | 0 |
| **Total observed this build** | **0** | **453** |

Warnings by clang flag (whole build):

| Count | Flag |
|---|---|
| 413 | `-Wdeprecated-declarations` |
| 9 | `-Wshorten-64-to-32` |
| 6 | `-Wmisleading-indentation` |
| 4 | `-Wdangling-assignment` |
| 2 | `-Wunused-but-set-variable` |
| 2 | `-Wunreachable-code` |
| 1 each | `-Wvoid-pointer-to-int-cast`, `-Wunused-property-ivar`, `-Wtautological-overlap-compare`, `-Wpointer-bool-conversion`, `-Wobjc-missing-super-calls`, `-Wformat`, `-Wbool-conversion` |

---

## Hard errors (build-stopping) — listed individually

**None.** The build succeeded. The previously-listed E1/E2 are resolved:

| # | Was | Now |
|---|---|---|
| E1 | `OUItoVendorDB.py:49` `IndentationError` aborting `Update vendors.db` | **FIXED by S0.6** — phase runs and skips/downloads cleanly. |
| E2 | umbrella workspace failure cascading from E1 | **GONE** — `BUILD SUCCEEDED`. |

### Environment blocker (only when code signing is enabled)

| # | File:line | Message | Category | Owner slice |
|---|---|---|---|---|
| ENV-1 | `KisMac2.xcodeproj` (target `KisMac2`) | `error: No signing certificate "Mac Development" found … matching team ID "DMP42GVPJ3" with a private key was found.` | Signing / provisioning (env). iCloud-hosted repo; no dev cert/team on this machine. Blocks **default** `xcodebuild`; the Wave-0 signing-disabled invocation works. | **S8.x** |

---

## Build-confirmed status of the items the first pass predicted (was: "NOT yet reproduced")

The original triage listed these under *"Source-confirmed compile-breakers NOT yet
reproduced (masked behind E1)"*. They are still present in source on this branch (none
were silently fixed), the files **did** compile, and **none broke the build**. The
table below converts each to its build-confirmed outcome. **All move from "predicted
hard error/link error" to "build-confirmed warning" or "build-confirmed clean (no
diagnostic)".** This is the flag the task asked for: every predicted item that did NOT
appear as an error is called out.

| File:line (current source) | Symbol / issue | Predicted (S0.1) | **Build-confirmed (this re-run)** | Owner slice |
|---|---|---|---|---|
| `Sources/Core/WaveStorageController.m:327,477,514,715` | `descriptionWithCalendarFormat:` | Removed-API **error** | **Warning** `-Wdeprecated-declarations` (4 sites; still declared in `NSCalendarDate.h`) | S0.3 (now: migrate off deprecated API) |
| `Sources/WavePlugins/WavePcapDump.m:60,66` | `descriptionWithCalendarFormat:` | Removed-API **error** | **Warning** `-Wdeprecated-declarations` (2 sites) | S0.3 |
| `Sources/Crypto/WaveNetWEPWordlist.m:341` | `WirelessCryptMD5(...)` | Missing/removed symbol → **link error** | **Compiles AND links** — `Apple80211.framework` still present, binary has `T _WirelessCryptMD5`. **Did NOT appear as an error.** | S0.3 (now: 🗑 quarantine per parity decision, not error-fix) |
| `Sources/Crypto/WaveNetWEPWordlist.m:87,214` | `WirelessEncrypt(...)` | Missing/removed symbol | **Inert** — both call sites are commented out; no diagnostic. **Did NOT appear.** | S0.3 |
| `Sources/Support/MapDownload.m:81,93,99` | `NSBeginAlertSheet(...)` | Deprecated-alert (treated as breaker) | **Warning** `-Wdeprecated-declarations` | S0.3 |
| `Sources/WavePlugins/WavePcapDump.m:77` | `NSBeginAlertSheet(...)` | Deprecated alert | **Warning** | S0.3 |
| `Sources/WindowControllers/DownloadMapController.m:94` | `NSRunCriticalAlertPanel(...)` | Deprecated alert | **Warning** (1 site here; 23 `NSRunCriticalAlertPanel` warnings total across the build) | S0.3 |
| `Sources/Preferences/PreferencePanes/PrefsDriver.m:291` | `NSRunAlertPanel(...)` | Deprecated alert | **Warning** | S0.3 |
| `Sources/WaveDrivers/WaveDriverKismet.m:100,144` | `NSRunCriticalAlertPanel(...)` | Deprecated alert | **Warning** | S0.3 |
| `Sources/WaveDrivers/WaveDriverKismetDrone.m` (≈16 sites) | `NSRunCriticalAlertPanel(...)` | Deprecated alert | **Warning** | S0.3 |
| `Sources/WaveDrivers/WaveDriverUSB.mm:177` | `NSRunCriticalAlertPanel(...)` | Deprecated alert | **Warning** | S0.3 |
| `Sources/WavePlugins/WavePluginMidi.m:34,50,96` | `#ifdef __i386__` Carbon QuickTime MIDI plugin | Dead i386/Carbon code (potential breaker) | **Compiles clean** — the `__i386__` blocks are excluded by the preprocessor on arm64, so the file is effectively empty of MIDI code. No diagnostic. **Did NOT appear.** | S0.4 (remove dead block) |
| `Sources/Support/HTTPStream.{m,h}` | Dead `HTTPStream` transport | Dead-endpoint (potential breaker) | **Compiles clean.** No diagnostic. **Did NOT appear.** | S0.4 (remove) |
| `Sources/WindowControllers/CrashReportController.m:30,54,88` | `ABAddressBook` + POST to `http://kismac-ng.org/crash.php` | Dead endpoint + privacy | **Compiles** with 4 deprecation warnings (`stringByAddingPercentEscapesUsingEncoding:`, `NSUserNotification*`, etc.); not an error. | S0.4 (remove; privacy) |
| `KisMac2.xcodeproj` (9 refs) + `Resources/Growl.framework` | Bundled Growl.framework still linked/CopyFiles'd | Dead bundled framework | **Build still succeeds** with Growl linked; no code refs. Cleanup, not a breaker. | S0.2 |

**Conclusion:** every "source-confirmed compile-breaker" the first pass predicted is, on
this toolchain, **non-fatal**. Zero of them appeared as build errors. They remain valid
*cleanup/migration* work for S0.2–S0.5, but the compile-baseline gate (build green) is
**already met** for Debug/arm64.

---

## KisMac2 application warnings — deduplicated with counts

These are **new** in this re-run (the masked run never compiled KisMac2). 318 of the
453 warnings are in `Sources/`.

### Deprecated declarations in KisMac2 sources (`-Wdeprecated-declarations`, 295) — top symbols

| Count | Symbol | Representative files | Owner slice |
|---|---|---|---|
| 60 | `NSOffState` (→ `NSControlStateValueOff`) | `ScanControllerMenus.m`, `ScanControllerPrivate.m`, `PrefsDriver.m` | S0.5 / S5.x |
| 54 | `NSOnState` (→ `NSControlStateValueOn`) | same | S0.5 / S5.x |
| 23 | `NSRunCriticalAlertPanel` (→ `NSAlert`) | `WaveDriverKismetDrone.m`, `WaveDriverKismet.m`, `WaveDriverUSB.mm`, `DownloadMapController.m` | S0.3 |
| 20 | `NSFileHandlingPanelOKButton` (→ `NSModalResponseOK`) | `ScanController*.m`, `MapView.m` | S0.5 / S5.x |
| 20 | `NSBeginAlertSheet` (→ `NSAlert beginSheetModalForWindow:`) | `MapDownload.m`, `WavePcapDump.m`, `ScanController*.m` | S0.3 |
| 17 | `NSDrawer` (→ split view / sidebar) | `ScanController*.m` | S5.x |
| 14 | `setAllowedFileTypes:` (→ `allowedContentTypes`) | `ScanController*.m`, `MapView.m` | S0.5 / S5.x |
| 6 | `NSBeginCriticalAlertSheet` | `ScanController*.m` | S0.3 |
| 6 | `descriptionWithCalendarFormat:timeZone:locale:` | `WaveStorageController.m`, `WavePcapDump.m` | S0.3 |
| 5 | `propertyListFromData:mutabilityOption:format:errorDescription:` | `WaveStorageController.m`, `MapView.m` | S0.5 |
| 5 | `interfaceNames` / 3 `interfaceWithName:` (CoreWLAN) | `WaveDriverAirport*.m`, `WaveHelper.m` | S1.x (CoreWLAN modernization) |
| 5 | `beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo:` | `ScanController*.m` | S5.x |
| 5 ea | `NSAlertDefaultReturn` / 4 `NSAlertAlternateReturn` / 4 `NSAlertOtherReturn` | alert call sites | S0.3 |
| 4 | `NSRunAlertPanel` | `WaveScanner.mm`, `PrefsDriver.m` | S0.3 |
| 3 | `dataFromPropertyList:format:errorDescription:` | `WaveStorageController.m`, `MapView.m` | S0.5 |
| 3 | `IOMasterPort` (→ `IOMainPort`) | USB driver code | S0.4 / S5.x |
| 3 | `NSCompositeSourceOver` (→ `NSCompositingOperationSourceOver`) | `MapView.m` | S5.x |
| 2 ea | `NSUserNotification`, `NSCompositeCopy`, `dateWithNaturalLanguageString:` | `CrashReportController.m`, drawing/parse code | S0.4 / S5.x |
| 1 ea | `unarchiveObjectWithFile:`, `unarchiveObjectWithData:`, `stringByAddingPercentEscapesUsingEncoding:`, `NSPNGFileType`, `NSJPEGFileType`, `NSTexturedBackgroundWindowMask`, `NSLeftMouseUp(Mask)`, `NSLeftMouseDragged(Mask)`, `NSCenterTextAlignment`, `NSWarningAlertStyle`, `NSRunInformationalAlertPanel`, `NSBeginInformationalAlertSheet`, `setMinSize:`/`setMaxSize:`, `NSUserNotificationCenter` | various | S0.5 / S5.x |

(Full per-line listing is in `/tmp/kismac_build_rerun.log`.)

### KisMac2 source logic / quality warnings (non-deprecation) — listed individually

These are the **interesting** ones — real code smells/correctness flags, several of
which already have owner slices in `docs/task-slices.md`.

| File:line | Message | Flag | Owner slice / note |
|---|---|---|---|
| `Sources/Controller/ScanControllerScriptable.m:718:22` | `overlapping comparisons always evaluate to true` | `-Wtautological-overlap-compare` | **S2.3** (this is the "weak-scheduling tautology guard" called out in S2.3 scope) |
| `Sources/Controller/ScanControllerScriptable.m:719:9` | `code will never be executed` | `-Wunreachable-code` | **S2.3** (consequence of the line-718 tautology — confirms the weak-scheduling path is dead) |
| `Sources/Crypto/WaveNetLEAPCrack.m:158:12` | `address of array 'pwhash' will always evaluate to 'true'` | `-Wpointer-bool-conversion` | S2.3 (crypto correctness) |
| `Sources/Crypto/AirCrackWrapper.m:574:165` | `format specifies type 'int' but argument has type 'unsigned long'` | `-Wformat` | S2.3 (crypto) |
| `Sources/Controller/TrafficController.mm:416,419,422,425` | `object backing the pointer 'ptr' will be destroyed at the end of the full-expression` | `-Wdangling-assignment` | S5.x (traffic graph; dangling temporaries) |
| `Sources/WaveDrivers/WaveDriverKismet.m:177:10` | `initialization of pointer of type 'NSArray *' to null from a constant boolean expression` | `-Wbool-conversion` | S2.4 (Kismet backend) |
| `Sources/Driver/USBJack/RT73Jack.mm:269:33` | `code will never be executed` | `-Wunreachable-code` | S0.4 / driver cleanup |
| `Sources/WaveDrivers/WaveDriverAirportExtreme.m:402:19` | `variable 'count' set but not used` | `-Wunused-but-set-variable` | S1.x |
| `Sources/Support/GPSController.m:1012:23` | `variable 'satnum' set but not used` | `-Wunused-but-set-variable` | S1.2 (GPS) |
| `Sources/WaveDrivers/WaveDriverUSBRealtekRTL8187.mm:66:2` | `misleading indentation; statement is not part of the previous 'if'` | `-Wmisleading-indentation` | S0.5 / driver cleanup |
| `Sources/WaveDrivers/WaveDriverUSBRalinkRT73.mm:66:2` | misleading indentation | `-Wmisleading-indentation` | S0.5 |
| `Sources/WaveDrivers/WaveDriverUSBRalinkRT2570.mm:67:2` | misleading indentation | `-Wmisleading-indentation` | S0.5 |
| `Sources/WaveDrivers/WaveDriverUSBIntersil.mm:105:2` | misleading indentation | `-Wmisleading-indentation` | S0.5 |
| `Sources/WavePlugins/WavePluginInjectionProbe.m:311:2` | misleading indentation | `-Wmisleading-indentation` | S0.5 |
| `Sources/WavePlugins/WavePluginInjecting.m:253:2` | misleading indentation | `-Wmisleading-indentation` | S0.5 |
| (9×) various | `-Wshorten-64-to-32` integer-precision (NSInteger→32-bit) | `-Wshorten-64-to-32` | S0.5 / S5.x |

> Note: the **WPA 64-bit pointer-aliasing** at `WaveNetWPACrack.m:115` named in S2.3 did
> **not** emit a distinct diagnostic in this Debug build (clang aliasing diagnostics are
> optimization-sensitive; it may surface in Release/`-O2`). Kept in S2.3 scope; flagged
> as not-yet-build-observed in Debug.

---

## Warnings in compiled subprojects (BIGL / BIGeneric / GBStorage) — 124

Unchanged from the original triage in character (pre-existing tech debt, non-fatal),
re-confirmed by this build. BIGL/BIGeneric = **121** warnings, GBStorage = **3**.

### OpenGL API deprecated (macOS 10.14) — `-Wdeprecated-declarations`

Per-symbol counts from the original pass still hold (`glVertex2f` ×17, `glTexCoord2f`
×8, `glEnable` ×7, `glEnd`/`glBlendFunc`/`glBegin` ×6, `glBindTexture` ×4, etc.) across
`BIGLView.m`, `BIGLLineView.m`, `BIGLPolyView.m`, `BIGLImageView.m`, `BIGLTextView.m`,
`BIGLGraphView.m`. **Owner: S5.x** (port graph off OpenGL/BIGL to Metal).

### Deprecated NSOpenGL types (→ Metal/MetalKit)

`NSOpenGLPixelFormat` ×4, `NSOpenGLView` ×2, `NSOpenGLPixelFormatAttribute` ×2,
`NSOpenGLPFASamples`/`…SampleBuffers`/`…NoRecovery`/`…DoubleBuffer` ×1 each — all in
`BIGLView.m`/`.h`. **Owner: S5.x.**

### Deprecated AppKit (non-OpenGL) in BIGL

`colorUsingColorSpaceName:` ×4, `initWithFocusedViewRect:` ×2, `NSCriticalAlertStyle`,
`NSCompositeSourceOver`. **Owner: S5.x.**

### Deprecated Carbon Speech (macOS 13.0 → AVSpeechSynthesizer)

`SpeechBusySystemWide` ×2; `SpeakCFString`, `SetSpeechProperty`, `NewSpeechChannel`,
`GetIndVoice`, `DisposeSpeechChannel` ×1 — `BISpeechController.m`. **Owner: S5.x.**

### BIGL / GBStorage misc & type-conversion

| File:line | Message | Flag | Owner |
|---|---|---|---|
| `…/BIGL/Classes/BIGLView.m:59:1` | possibly missing `[super prepareOpenGL]` | `-Wobjc-missing-super-calls` | S5.x |
| `…/BIGL/Classes/BIGLView.m:70:3` | cast to smaller int `NSOpenGLPixelFormatAttribute` from `void *` | `-Wvoid-pointer-to-int-cast` | S5.x |
| `Subprojects/GBStorage/GBStorage.m:28,32` | `archivedDataWithRootObject:` / `unarchiveObjectWithData:` deprecated | `-Wdeprecated-declarations` | S6.x (secure coding) |
| `Subprojects/GBStorage/GBStorage.m:169:1` | ivar `_cachedKeys` backs property but not referenced in accessor | `-Wunused-property-ivar` | S6.x |
| BIGL/BIGeneric `BIGLView.m`/`BIGLGraphView.m` | `NSInteger`→`GLsizei`/`GLint` precision loss | `-Wshorten-64-to-32` | S5.x |

### Linker / toolchain warnings

| Count | Message | Scope | Owner slice |
|---|---|---|---|
| 2 | `prefered load addresses (-seg1addr) are disabled with chained fixups` | Linker (BIGL, BIGeneric `Ld`) | S0.5 / S8.x (drop obsolete `-seg1addr`) |
| 1 | `Traditional headermap style is no longer supported; … set 'ALWAYS_SEARCH_USER_PATHS' to NO` | BIGeneric target settings | S0.5 / S8.x |

---

## What this means for the dependent slices

- **S0.6** — ✅ done (this branch). `Update vendors.db` passes; build reaches and clears
  the compile + link phases.
- **S0.1** — ✅ re-run complete; compile baseline is **green**, not red. Acceptance met:
  reproducible result documented (the command above can be re-run to verify).
- **S0.2 / S0.3 / S0.4** — scope is intact but **re-characterized from "fix compile
  errors" to "remove dead code / migrate deprecated APIs without regressing the green
  build."** None of their items are build-blockers today.
- **S0.5** — the "clean Debug **and** Release build green" gate: Debug is already green.
  Remaining work is the **453-warning** burn-down + a **Release** build check (Release
  forces a real `vendors.db` download per `needForce`, so verify the S0.6 network/offline
  path there) + Intel-arch confirmation. ENV-1 (signing) still owned by S8.x.
- **S2.3** — the **weak-scheduling tautology** (`ScanControllerScriptable.m:718`) and its
  **dead branch** (`:719`) are now **build-confirmed** exactly where S2.3 predicts;
  `WaveNetLEAPCrack.m:158` and `AirCrackWrapper.m:574` are confirmed crypto warnings.

---

## Submodule status

`git submodule status --recursive` (unchanged from S0.1; all four present & checked
out, BIGL/BIGeneric build successfully):

| Submodule | Commit | Branch/tag |
|---|---|---|
| `Subprojects/BIGeneric` | `66dc826ba177f7c5426f961c5eb6d8127cf29263` | heads/master |
| `Subprojects/BIGeneric/Submodules/BIGL` | `60344b03b21e5380f0879686d476316cde3392cc` | heads/master |
| `Subprojects/GBStorage` | `9778d8ee1adff4d929dc488ba5b3592966ab4d64` | 2.6.0 |
| `Subprojects/polarssl` | `a36ae0837d59159f0c49f51ec1a25ed0adc3861f` | polarssl-1.2.19 |

This re-run links `BIGL.framework`, `BIGeneric.framework`, and (via GBStorage source in
the target) `GBStorage`. `polarssl` is still not in the Debug scheme's link graph.

> Note: the working tree still shows `Subprojects/BIGeneric` as a dirty submodule (`m`).
> Per scope this is left unstaged and untouched; only `docs/build-triage.md` is committed
> in this slice (plus the separate S0.6 Python commit).
