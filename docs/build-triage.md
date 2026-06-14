# KisMac3 — Build Triage (S0.1 output)

This is the deliverable for task slice **S0.1 — Compile baseline: inventory & triage
build failures** (`docs/task-slices.md`). It catalogues every error and warning from a
clean Debug build of the legacy KisMAC2 project on the current Xcode. **No fixes were
made** — fixes happen in slices S0.2–S0.6.

Produced by `legacy-objc-porting-agent` on branch `setup/subagent-orchestration`.

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
| Build log | `/tmp/kismac_build_debug.log` |

Workspace schemes (`xcodebuild -workspace KisMac2.xcworkspace -list`):
`BIGeneric`, `BIGL`, `Kismac.dmg`, `KisMac2`. Main app scheme = `KisMac2`.

## How the build was run

```
xcodebuild -workspace "…/KisMac3/KisMac2.xcworkspace" \
  -scheme KisMac2 -configuration Debug clean build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee /tmp/kismac_build_debug.log
```

> **Why signing was disabled:** the first attempt without those flags failed
> immediately at provisioning with
> `error: No signing certificate "Mac Development" found … matching team ID
> "DMP42GVPJ3"`. That is an environment/signing blocker (this repo lives in iCloud;
> codesign/xattr quirks are known) and masks all compile output. It is catalogued
> below as **ENV-1**. Re-running with signing disabled lets the compiler run so the
> real build failures surface. Both behaviours are documented.

`xcpretty` is not installed; output is raw `xcodebuild`.

---

## Result summary

**`** BUILD FAILED **` — 2 failures.**

The build is currently blocked by a **single hard failure in the very first build
phase of the KisMac2 target** (the "Update vendors.db" Run Script phase), which aborts
before any KisMac2 source file is compiled. As a result:

- The **BIGL** and **BIGeneric** subproject frameworks **compile and link
  successfully** (Apple Silicon), producing only deprecation warnings.
- **No KisMac2 application source file is compiled at all** in this build. The
  compile-breaking removed-API errors catalogued by the parity audit
  (`docs/original-feature-parity.md` §5) are **present in source but not yet
  reproducible at build time** — they are masked behind the script-phase failure and
  will only surface once S0.6 (and S0.2) unblock the build. They are listed below as
  *source-confirmed / predicted* so the later slices keep their scope.

### Counts

| Category | Hard errors | Warnings |
|---|---|---|
| Run-script phase failure (Python) | 1 | 0 |
| Environment / code signing | 1 (when signing enabled) | 0 |
| Deprecated OpenGL/AppKit (BIGL/BIGeneric, compiled) | 0 | 113 |
| Deprecated Carbon Speech (BISpeechController) | 0 | 7 |
| Linker (chained fixups / -seg1addr) | 0 | 2 |
| Headermap (BIGeneric) | 0 | 1 |
| **Total observed this build** | **2** | **123** |

All 123 warnings come exclusively from the **BIGL/BIGeneric subprojects** (the only
code that actually compiled). KisMac2's own warnings are not yet observable.

---

## Hard errors (build-stopping) — listed individually

| # | File:line | Message | Category | Proposed owner slice |
|---|---|---|---|---|
| E1 | `Resources/Generic/OUItoVendorDB.py:49` | `IndentationError: unexpected indent` (`if filesize:` over-indented inside the `while` download loop) → `Command PhaseScriptExecution failed with a nonzero exit code` for the **"Update vendors.db"** build phase | Broken Run Script build phase (first phase of KisMac2 target; aborts the whole build before Sources compile) | **S0.6 (new)** |
| E2 | *(build orchestration)* | `Building workspace KisMac2 with scheme KisMac2 and configuration Debug` — the second "failure" is the umbrella failure caused by E1 | Cascade of E1 | S0.6 (resolved by fixing E1) |

### Environment blocker (only when code signing is enabled)

| # | File:line | Message | Category | Proposed owner slice |
|---|---|---|---|---|
| ENV-1 | `KisMac2.xcodeproj` (target `KisMac2`) | `error: No signing certificate "Mac Development" found: No "Mac Development" signing certificate matching team ID "DMP42GVPJ3" with a private key was found.` | Signing / provisioning (env). iCloud-hosted repo; no dev cert/team on this machine. Blocks default `xcodebuild` invocation. | **S8.x** (signing/notarization/CI) — for Wave 0 builds, build with signing disabled or set a local team. |

---

## Warnings (compiled code = BIGL/BIGeneric only) — deduplicated with counts

All of these are in the two subproject frameworks. They are pre-existing tech debt
already flagged in the parity audit (OpenGL/BIGL → Metal; Carbon Speech →
AVSpeechSynthesizer) and are owned by the **S5.x UI modernization** slice (port graph
off OpenGL/BIGL) and **S0.5 / S5.x** cleanup, not the Wave-0 compile-stabilization
slices. They are non-fatal.

### OpenGL API deprecated (macOS 10.14) — `-Wdeprecated-declarations`

| Count | Symbol | Primary files | Category | Owner slice |
|---|---|---|---|---|
| 17 | `glVertex2f` | `BIGLView.m`, `BIGLLineView.m`, `BIGLPolyView.m` | Deprecated OpenGL | S5.x |
| 8 | `glTexCoord2f` | `BIGLView.m`, `BIGLImageView.m` | Deprecated OpenGL | S5.x |
| 7 | `glEnable` | `BIGLView.m`, `BIGLTextView.m`, `BIGLImageView.m` | Deprecated OpenGL | S5.x |
| 6 | `glEnd` | `BIGLView.m` et al. | Deprecated OpenGL | S5.x |
| 6 | `glBlendFunc` | `BIGLView.m` et al. | Deprecated OpenGL | S5.x |
| 6 | `glBegin` | `BIGLView.m` et al. | Deprecated OpenGL | S5.x |
| 4 | `glBindTexture` | `BIGLImageView.m`, `BIGLTextView.m` | Deprecated OpenGL | S5.x |
| 3 | `glDisable` | `BIGLView.m` | Deprecated OpenGL | S5.x |
| 3 | `glColor4fv` | `BIGLView.m` | Deprecated OpenGL | S5.x |
| 2 each | `glTexImage2D`, `glPushMatrix`, `glPopMatrix`, `glMatrixMode`, `glLoadIdentity`, `glLineWidth`, `glGenTextures`, `glFinish`, `glColor4f` | `BIGLView.m`, `BIGLImageView.m`, `BIGLTextView.m`, `BIGLGraphView.m` | Deprecated OpenGL | S5.x |
| 1 each | `glViewport`, `glShadeModel`, `glReadPixels`, `glPixelStorei`, `glOrtho`, `glHint`, `glColorMaterial`, `glClearColor`, `glClear` | `BIGLView.m`, `BIGLGraphView.m` | Deprecated OpenGL | S5.x |

### Deprecated NSOpenGL types (macOS 10.14 → Metal/MetalKit) — `-Wdeprecated-declarations`

| Count | Symbol | Files | Owner slice |
|---|---|---|---|
| 4 | `NSOpenGLPixelFormat` | `BIGLView.m` | S5.x |
| 2 | `NSOpenGLView` | `BIGLView.m`/`.h` | S5.x |
| 2 | `NSOpenGLPixelFormatAttribute` | `BIGLView.m` | S5.x |
| 1 each | `NSOpenGLPFASamples`, `NSOpenGLPFASampleBuffers`, `NSOpenGLPFANoRecovery`, `NSOpenGLPFADoubleBuffer` | `BIGLView.m` | S5.x |

### Deprecated AppKit (non-OpenGL) — `-Wdeprecated-declarations`

| Count | Symbol | Files | Owner slice |
|---|---|---|---|
| 4 | `colorUsingColorSpaceName:` (→ `colorUsingColorSpace:`) | `BIGLTextView.m`, `BIGLView.m` | S5.x |
| 2 | `initWithFocusedViewRect:` (→ `cacheDisplayInRect:toBitmapImageRep:`) | `BIGLImageView.m`, `BIGLTextView.m` | S5.x |
| 1 | `NSCriticalAlertStyle` (10.12) | `BIGLView.m` | S5.x |
| 1 | `NSCompositeSourceOver` (10.12) | `BIGLView.m` | S5.x |

### Deprecated Carbon Speech (macOS 13.0 → AVSpeechSynthesizer) — `-Wdeprecated-declarations`

| Count | Symbol | File | Owner slice |
|---|---|---|---|
| 2 | `SpeechBusySystemWide` | `BISpeechController.m` | S5.x (audio feedback) |
| 1 each | `SpeakCFString`, `SetSpeechProperty`, `NewSpeechChannel`, `GetIndVoice`, `DisposeSpeechChannel` | `BISpeechController.m` | S5.x (audio feedback) |

### Type-conversion / misc compiler warnings

| Count | Message | File | Owner slice |
|---|---|---|---|
| 2 | implicit conversion loses integer precision `NSInteger`→`GLsizei` `-Wshorten-64-to-32` | `BIGLView.m`/`BIGLGraphView.m` | S5.x |
| 2 | implicit conversion loses integer precision `NSInteger`→`GLint` `-Wshorten-64-to-32` | `BIGLView.m` | S5.x |
| 1 | cast to smaller integer type `NSOpenGLPixelFormatAttribute` from `void *` `-Wvoid-pointer-to-int-cast` | `BIGLView.m` | S5.x |
| 1 | method possibly missing a `[super prepareOpenGL]` call `-Wobjc-missing-super-calls` | `BIGLView.m` | S5.x |

### Linker / toolchain warnings

| Count | Message | Scope | Owner slice |
|---|---|---|---|
| 2 | `prefered load addresses (-seg1addr) are disabled with chained fixups` | Linker (BIGL, BIGeneric `Ld`) | S0.5 / S8.x (drop obsolete `-seg1addr`) |
| 1 | `Traditional headermap style is no longer supported; please migrate … set 'ALWAYS_SEARCH_USER_PATHS' to NO` | BIGeneric target settings | S0.5 / S8.x |

---

## Source-confirmed compile-breakers NOT yet reproduced (masked behind E1)

These are **not** in this build log because the build aborted at E1 before KisMac2
sources compiled. They are confirmed by direct source inspection on this branch and
are pre-assigned to their owner slices per the parity audit. Listed so the later
slices keep their scope; expect them to appear in the log once S0.6 + S0.2 land.

| File:line | Symbol / issue | Category | Owner slice |
|---|---|---|---|
| `Sources/Core/WaveStorageController.m:327` | `[NSDate descriptionWithCalendarFormat:…]` | Removed API (NSCalendarDate) | S0.3 |
| `Sources/Core/WaveStorageController.m:477` | `descriptionWithCalendarFormat:` | Removed API | S0.3 |
| `Sources/Core/WaveStorageController.m:514` | `descriptionWithCalendarFormat:` | Removed API | S0.3 |
| `Sources/Core/WaveStorageController.m:715` | `descriptionWithCalendarFormat:` | Removed API | S0.3 |
| `Sources/WavePlugins/WavePcapDump.m:60` | `descriptionWithCalendarFormat:` | Removed API | S0.3 |
| `Sources/WavePlugins/WavePcapDump.m:66` | `descriptionWithCalendarFormat:` | Removed API | S0.3 |
| `Sources/Crypto/WaveNetWEPWordlist.m:341` | `WirelessCryptMD5(...)` (removed Apple80211 private symbol) | Missing/removed symbol (link) | S0.3 |
| `Sources/Crypto/WaveNetWEPWordlist.m:87,214` | `WirelessEncrypt(...)` (currently commented out) | Missing/removed symbol | S0.3 |
| `Sources/Support/MapDownload.m:81,93,99` | `NSBeginAlertSheet(...)` | Deprecated AppKit alert | S0.3 |
| `Sources/WavePlugins/WavePcapDump.m:77` | `NSBeginAlertSheet(...)` | Deprecated AppKit alert | S0.3 |
| `Sources/WindowControllers/DownloadMapController.m:94` | `NSRunCriticalAlertPanel(...)` | Deprecated AppKit alert | S0.3 |
| `Sources/Preferences/PreferencePanes/PrefsDriver.m:291` | `NSRunAlertPanel(...)` | Deprecated AppKit alert | S0.3 |
| `Sources/WaveDrivers/WaveDriverKismet.m:100,144` | `NSRunCriticalAlertPanel(...)` | Deprecated AppKit alert | S0.3 |
| `Sources/WaveDrivers/WaveDriverKismetDrone.m` (≈20 sites, lines 157–418) | `NSRunCriticalAlertPanel(...)` | Deprecated AppKit alert | S0.3 |
| `Sources/WaveDrivers/WaveDriverUSB.mm:177` | `NSRunCriticalAlertPanel(...)` | Deprecated AppKit alert | S0.3 |
| `Sources/WavePlugins/WavePluginMidi.m:34,50,96` | `#ifdef __i386__` Carbon QuickTime MIDI plugin (dead on arm64) | Dead i386/Carbon code | S0.4 |
| `Sources/Support/HTTPStream.{m,h}` | Dead `HTTPStream` transport (server export stub) | Dead i386/Carbon/dead-endpoint | S0.4 |
| `Sources/WindowControllers/CrashReportController.m:30,54,88` | `ABAddressBook` + POST to `http://kismac-ng.org/crash.php` | Dead endpoint + privacy (crash upload) | S0.4 |
| `KisMac2.xcodeproj/project.pbxproj` (9 refs) + `Resources/Growl.framework` on disk | Bundled Growl.framework still linked/CopyFiles'd, no code refs | Dead bundled framework | S0.2 |

---

## Proposed new slice

### S0.6 — Fix the `OUItoVendorDB.py` "Update vendors.db" build-script phase
Repair the Python `IndentationError` at `Resources/Generic/OUItoVendorDB.py:49`
(de-indent the `if filesize:` block to sit inside the `while` loop, not nested under
`downloaded += …`). This Run Script phase is the **first** build phase of the KisMac2
target (before Frameworks/Resources/Sources/CopyFiles), so it must succeed before any
KisMac2 source can compile. Owner: `legacy-objc-porting-agent`. This becomes the true
first build-unblocking step of Wave 0 (effectively a prerequisite to observing the
S0.3/S0.4 compile errors). **Dep:** S0.1.

---

## Submodule status

`git submodule update --init --recursive` completed with no output (all already
initialized). `git submodule status --recursive`:

| Submodule | Commit | Branch/tag |
|---|---|---|
| `Subprojects/BIGeneric` | `66dc826ba177f7c5426f961c5eb6d8127cf29263` | heads/master |
| `Subprojects/BIGeneric/Submodules/BIGL` | `60344b03b21e5380f0879686d476316cde3392cc` | heads/master |
| `Subprojects/GBStorage` | `9778d8ee1adff4d929dc488ba5b3592966ab4d64` | 2.6.0 |
| `Subprojects/polarssl` | `a36ae0837d59159f0c49f51ec1a25ed0adc3861f` | polarssl-1.2.19 |

All four required subprojects are present and checked out:
`BIGeneric`, its nested `BIGL`, and `polarssl` (plus `GBStorage`). The **BIGeneric**
and **BIGL** frameworks **build successfully** (warnings only) — confirming the
S0.1 acceptance criterion that the subprojects compile. `polarssl` and `GBStorage`
are not referenced by the `KisMac2` Debug scheme's dependency graph (which links only
`BIGL.framework` and `BIGeneric.framework`), so they were not exercised by this build.

> Note: the working tree shows `Subprojects/BIGeneric` as a dirty submodule (`m`).
> Per S0.1 scope this was left unstaged and untouched; only `docs/build-triage.md`
> is committed.
