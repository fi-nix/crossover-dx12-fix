# Satisfactory DX12 on CrossOver — GPTK 4 workflow

Running **Satisfactory (UE 5.6)** under **CrossOver on Apple silicon** with the
**DirectX 12** renderer, by replacing CrossOver's bundled D3DMetal 3.0 with
**D3DMetal 4.0b2** from Apple's Game Porting Toolkit 4 beta 2.

**Status: working.** Verified 2026-08-23 on an M5 Max with CrossOver 26.3 — multiple
clean sessions, D3D12 feature level 12_2, shader model 6.6, resource binding
tier 3. Newer CrossOver or GPTK releases may change the picture; check the
[changelog](https://www.codeweavers.com/crossover/changelog).

> The swap is undone by every CrossOver update. When DX12 starts crashing again,
> run `./reapply-gptk4.sh`. That is the whole maintenance story.

---

## The problem

With stock CrossOver, Satisfactory dies during renderer init — before a window
ever appears. From `FactoryGame.log`:

```
LogRHI: Using Default RHI: D3D12
LogRHI: RHI D3D12 with Feature Level SM6 is supported and will be used.
LogD3D12RHI: Bindless resources are supported
Assertion failed: GGlobalSamplerDescriptorHeapSize <= MaximumSamplerHeapSize
  [File: Engine\Source\Runtime\D3D12RHI\Private\D3D12Device.cpp] [Line: 372]

FactoryGameSteam-D3D12RHI-Win64-Shipping.dll!FD3D12Device::SetupAfterDeviceCreation()
FactoryGameSteam-D3D12RHI-Win64-Shipping.dll!FD3D12Adapter::InitializeDevices()
FactoryGameSteam-D3D12RHI-Win64-Shipping.dll!FD3D12DynamicRHI::Init()
```

**Cause.** UE 5.6 sizes its global bindless *sampler* descriptor heap from what
the D3D12 device reports, then asserts the result fits the device maximum.
D3DMetal 3.0 reports values that fail that assertion, so the RHI never
initializes.

**Not the cause**, so don't chase these:

- Launch options. `-dx12` changes nothing — D3D12 is already the *default* RHI
  for this title, which is exactly why it crashes out of the box.
- Missing VC++ redistributables. A separate, real issue on some bottles that
  produces a *different* symptom (a "Microsoft Visual C++ 2015–2022
  Redistributable (x64) required" dialog). This bottle already has
  v14.51.36247 x64+x86 installed.
- Graphics settings, save files, or a game reinstall. The crash is before any of
  those are read.

**Fix.** D3DMetal 4 reports correctly. Confirmed independently on the
[CodeWeavers Satisfactory forum](https://www.codeweavers.com/compatibility/crossover/forum/satisfactory?msg=351506),
where the same assertion also hit
[StarRupture](https://www.codeweavers.com/compatibility/crossover/forum/starrupture?msg=342791).

As of CrossOver 26.3 (2026-07-21, current when this was written) no shipping
CrossOver bundles D3DMetal 4, so the swap has to be done by hand.

---

## Requirements

| | Needed | This machine |
|---|---|---|
| Hardware | Apple silicon | M5 Max, 40-core GPU |
| macOS | 15 Sequoia or newer | 26.6.2 (25G83) |
| CrossOver | 26.x | 26.3.0.39832 |
| Payload | GPTK 4.0 beta 2 | extracted to `gptk4-b2/lib/` — see below |
| Bottle graphics engine | **D3DMetal** — not DXVK, not DXMT | `CX_GRAPHICS_BACKEND=d3dmetal` |
| Permission | Terminal granted **App Management** | see below |

### App Management permission

CrossOver.app is Developer ID signed, notarized, and stapled, and lives in
`/Applications`. macOS refuses to let an ordinary process modify it — every
write fails with `Operation not permitted`, and **`sudo` does not help**.

Grant it in **System Settings → Privacy & Security → App Management** for
whichever terminal runs the script (Terminal, iTerm, Ghostty, …). Add it with **+** if it
isn't listed, and **relaunch the terminal** afterward — the permission is not
picked up by an already-running process.

This permission lets anything run from that terminal modify installed apps.
Revoking it when you're done is reasonable; just re-grant before re-applying.

### First-time setup: get the payload

The GPTK binaries are Apple's and are **not in this repo** (`.gitignore`
excludes them). Fetch them once:

1. Download **Game Porting Toolkit 4.0 beta 2** from
   <https://developer.apple.com/games/> (free Apple developer account).
2. Mount the outer DMG, then the nested *Evaluation environment for Windows
   games* DMG inside it.
3. Copy the payload next to the scripts, with `ditto` so the
   `x86_64-unix/*.so` symlinks into `libd3dshared.dylib` survive (plain `cp`
   without `-R` breaks them):

   ```sh
   ditto "<mount>/redist/lib" gptk4-b2/lib
   ```

   Optionally copy the Read Me from the outer DMG to `gptk4-b2/Apple-ReadMe.rtf`
   for reference.
4. Check it: `./reapply-gptk4.sh --status` should show `payload 4.0b2`.

Keep `gptk4-b2/` around afterward. Apple pulls beta builds when they're
superseded, and with the payload on disk, re-applying after a CrossOver update
is a one-liner.

---

## Applying it

```sh
./reapply-gptk4.sh
```

Idempotent — exits immediately if D3DMetal 4.0b2 is already active. It quits
CrossOver (and refuses to continue while any Wine process is still running),
backs up the stock libraries under the current CrossOver version, swaps in the
payload, and updates the bottle. Any `nvngx.dll` / `nvapi64.dll` already in the
bottle's `system32` is kept as `*.pre-gptk4` and put back by the revert.

The bottle defaults to `Satisfactory`; for another one (e.g. StarRupture):

```sh
BOTTLE_NAME="StarRupture" ./reapply-gptk4.sh
```

If CrossOver isn't in `/Applications`, set `CROSSOVER=/path/to/CrossOver.app`.

`./reapply-gptk4.sh --status` reports what's installed without changing
anything. `--dry-run` prints the plan.

### What it does

The procedure is **Apple's own**, from the Read Me inside the GPTK 4 disk image
(`gptk4-b2/Apple-ReadMe.rtf` if you copied it during setup):

```sh
cd /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk
mv external external.old; mv wine wine.old
ditto "<payload>/lib/" .
```

Then, still per Apple, to enable the experimental DLSS→MetalFX bridge:

- `wine/x86_64-unix/nvngx-on-metalfx.so` → `nvngx.so`
- `wine/x86_64-windows/nvngx-on-metalfx.dll` → `nvngx.dll`
- copy `nvngx.dll` and `nvapi64.dll` into the bottle's `windows/system32`

### Deltas from stock CrossOver

GPTK 4 does **not** ship `atidxx64`, which CrossOver 26.3 does; Apple's
procedure removes it. GPTK 4 **adds** `d3d10`, which CrossOver's `apple_gptk`
lacked. Both are expected. CrossOver's `bin/wine` only ever references
`apple_gptk/external/libd3dshared.dylib` by path — it never names the individual
DLLs — so the loader falls back cleanly for anything absent.

### Steam launch options

```
-dx12 -NOTEXTURESTREAMING
```

`-dx12` is redundant but explicit. `-NOTEXTURESTREAMING` turns off UE's texture
streaming and loads textures up front. It isn't part of the DX12 fix, but it
was in the working configuration. Expect higher memory use with it; drop it if
you want to test without it.

Set via Steam's UI (Properties → General), or directly in
`.../Steam/userdata/<id>/config/localconfig.vdf` under the `"526870"` block —
**with Steam closed**, or Steam overwrites the file on exit.

---

## Verifying

A good run logs this:

```
LogRHI: Using Default RHI: D3D12
LogD3D12RHI:   Max supported Feature Level 12_2, shader model 6.6,
               binding tier 3, wave ops supported, atomic64 supported
LogFSR: Successfully initialized FSR Upscaling provider using version '3.1.5'
LogXeSSRHI: Loading XeSS library 2.0.1 on AMD RHI D3D12 — Intel XeSS effect supported
```

and **no** `GGlobalSamplerDescriptorHeapSize` line.

Log: `<bottle>/drive_c/users/crossover/AppData/Local/FactoryGame/Saved/Logs/FactoryGame.log`
Crashes: `.../Saved/Crashes/*/CrashContext.runtime-xml` — `<ErrorMessage>` names the assertion.

The first launch after a swap is slow while D3DMetal rebuilds its shader cache.
That is normal and does not repeat.

---

## Known limitations

**DLSS does not work.** Despite the `nvngx` step, the log reports:

```
LogDLSS: NVIDIA NGX DLSS supported SR=0 RR=0
[streamline] Disabling DLSS-G since it is not supported on current hardware
```

Almost certainly because D3DMetal presents the GPU as **`AMD Compatibility
Mode`** (DeviceId `0x66af`), and NGX requires an NVIDIA adapter. The MetalFX
bridge is documented by Apple as experimental; it does not engage for this title.

`SR` is **Super Resolution** (the upscaler) and `RR` is **Ray Reconstruction**
(the ray-traced denoiser). Neither costs you much here:

- **SR** — you have two working substitutes. FSR 3.1 and XeSS 2 are close enough
  to DLSS 3 that the difference is a matter of taste at equivalent quality
  presets.
- **RR** — moot. Satisfactory disables ray tracing at the project level
  (`LogRendererCore: Ray tracing is disabled. Reason: disabled through project
  setting (r.RayTracing=0)`), so there is nothing for it to denoise.
- **DLSS-G** (frame generation) is separately unsupported. FSR does register an
  `FSRSwapchainProvider`, which is the hook its frame interpolation uses.

### Is the nvngx bridge worth keeping?

Yes — but understand that it is currently inert, not load-bearing.

Satisfactory ships its own NVIDIA stack (`nvngx_dlss.dll`, `nvngx_dlssd.dll`,
`nvngx_dlssg.dll`, `sl.*.dll`) and Streamline loads it from the game's own
`FactoryGame/Plugins/**/Binaries/ThirdParty/Win64` — never from `system32`. The
`system32` copies Apple's Read Me calls for are also redundant under CrossOver,
which already exposes `apple_gptk`'s DLLs to the loader; that the `d3d12.dll`
swap works at all, with nothing copied into `system32`, proves the path exists.

Keep it anyway. It costs ~100 ms of failed Streamline init at startup and some
log noise, it's Apple's documented procedure, and it is the zero-effort path to
DLSS simply starting to work if a later D3DMetal fixes the adapter vendor
reporting. Removing it buys nothing.

Not worth chasing: making D3DMetal spoof an NVIDIA vendor ID to satisfy NGX.
That is fighting the translation layer for an upscaler you already have two
working substitutes for.

**Use FSR or XeSS instead** — both initialize cleanly and are the right
upscaler choice here:

| Upscaler | Status |
|---|---|
| FSR | ✅ 3.1.5, initializes and runs |
| XeSS | ✅ 2.0.10 (library 2.0.1) |
| DLSS Super Resolution | ❌ `SR=0` |
| DLSS Ray Reconstruction | ❌ `RR=0` — irrelevant, the game ships with RT off |
| DLSS-G / frame gen | ❌ unsupported on this adapter |

**Benign noise.** `[GPUBreadCrumb] Failed to OpenExistingHeapFromAddress, error:
80004001` (`E_NOTIMPL`) appears at startup and is harmless — it's UE's crash
breadcrumb feature, unimplemented in D3DMetal.

**This is beta software.** GPTK 4.0 **beta 2**, which CodeWeavers never tested
against. Unrelated regressions elsewhere in the bottle are possible. Modifying
the bundle also breaks its code signature seal — already-launched apps aren't
re-verified and CrossOver launches fine, but it is a real modification to a
signed, notarized app. Both replacement libraries are Apple-signed
(`Authority=Software Signing`), so hardened-runtime library validation accepts
them.

---

## Tuning

D3DMetal environment variables, set per-bottle in `cxbottle.conf` under
`[EnvironmentVariables]`. Full list in `gptk4-b2/Apple-ReadMe.rtf`.

| Variable | Default | Notes |
|---|---|---|
| `D3DM_SUPPORT_DXR` | **on** for M3+ | DirectX Raytracing translation. **First thing to set to `0`** if DX12 misbehaves. |
| `D3DM_ENABLE_METALFX` | off | Maps DLSS→MetalFX where possible — see limitations. (Was `1` on the test bottle.) |
| `D3DM_MTL4` | on, **macOS 27+ only** | Metal 4 backend. Irrelevant on macOS 26 — you get the Metal 3 backend no matter what the GPU advertises. |
| `D3DM_MAX_FPS` | unset | Frame rate cap. |
| `ROSETTA_ADVERTISE_AVX` | off | Advertise AVX to translated code. |

For reference, the test bottle also carried `WINEMSYNC=1`, `WINED3DMETAL=1`,
and `DXMT_ENABLE_NVEXT=1` from bottle creation.

D3DMetal logs to the system log under category `D3DMetal`, prefix `D3DM` —
visible in Console.app, or when launching from a terminal.

---

## Rolling back

```sh
./revert-gptk4.sh
```

Restores stock D3DMetal from `backup-stock-apple_gptk-CX<version>/`, or from the
in-place `external.old` / `wine.old` if that's all there is. It also puts back
any `*.pre-gptk4` DLLs in the bottle, and deletes only `system32` files that
match a GPTK copy. If a CrossOver update already restored the stock libraries,
it only cleans up the bottle. DX12 will crash
again afterward — that's the point of the rollback, not a failure.

Fully reinstalling CrossOver also reverts everything.

**Fallback if DX12 can't be made to work at all:** `-DX11` in the launch
options. Forum-confirmed to launch 1.2.2, but with noticeable stutter. An escape
hatch, not a destination.

---

## Files here

In the repo:

| Path | Purpose |
|---|---|
| `reapply-gptk4.sh` | Apply the swap. Idempotent. `--status`, `--dry-run`. |
| `revert-gptk4.sh` | Restore stock D3DMetal. `--dry-run`. |
| `common.sh` | Paths, version (`WANT`) and helpers shared by both scripts. |

Created locally, never committed (see `.gitignore`):

| Path | Purpose |
|---|---|
| `gptk4-b2/lib/` | GPTK 4.0b2 payload, symlinks intact — see "First-time setup" |
| `gptk4-b2/Apple-ReadMe.rtf` | Apple's own instructions and env var reference |
| `backup-stock-apple_gptk-CX<version>/` | Pristine stock D3DMetal, made by the first apply on each CrossOver version |

Don't delete `gptk4-b2/` or the backups. The backup is written to `.partial`
first and renamed only once complete, so an interrupted copy is never used.

---

## Upgrading the payload

When a newer GPTK arrives (4.0 final, or a later beta):

1. Mount the outer DMG, then the nested *Evaluation environment for Windows
   games* DMG inside it.
2. `ditto "<mount>/redist/lib" gptk4-b2/lib` — `ditto` preserves the
   `x86_64-unix/*.so` symlinks that point at `libd3dshared.dylib`. Plain `cp`
   without `-R` does not.
3. Update `WANT` in `common.sh` to the new
   `CFBundleShortVersionString`, then run it.

Check a candidate's version without installing:

```sh
plutil -extract CFBundleShortVersionString raw \
  "<mount>/redist/lib/external/D3DMetal.framework/Resources/Info.plist"
```

If CrossOver eventually ships D3DMetal 4 itself, this whole workflow becomes
unnecessary — check the [changelog](https://www.codeweavers.com/crossover/changelog)
after major updates.
