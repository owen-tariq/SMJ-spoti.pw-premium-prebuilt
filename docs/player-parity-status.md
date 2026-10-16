# Original-release feature parity: first implementation batch

Reference: https://github.com/skopevoj/spoti.pw/releases/tag/v0.51.0

This branch is an implementation candidate, not a declaration of 0.51 feature parity.
It does not change version.txt, publish an IPA, change paid-service entitlements, or
remove the fork's pre-existing customizations. The default branch is unchanged.

## Implemented in this branch, not yet device-validated

### Player device volume

Enable Redesigned UI, then Mod Settings > Appearance > Player device volume.

An original MPVolumeView-backed row is inserted immediately before the player footer
when the host exposes the expected vertical UIStackView hierarchy. It controls the
current iOS audio route. It is NOT remote Spotify Connect volume. The system control
retains its native adjustment and accessibility behavior. Existing visible system
volume controls are detected before insertion; unsupported layouts are left alone.
No global volume setters, media rights changes, or replacement playback actions.

### Artwork-following Kit accents

Enable Mod Settings > Appearance > Follow artwork colours.

An original bounded, off-main-thread RGBA histogram chooses a saturated artwork colour
and lifts it to at least 4.5:1 contrast against #121212. It is used by the redesign's
SGRAccent token. On missing/gray art, track changes, or disable, the manually selected
accent (or the existing green fallback) remains available. Stale async results from
previous tracks or artwork identities are discarded. The volume row repaints on the
change notification. Other Kit consumers see the new token when they next read it;
this is NOT a claim that every cached Spotify icon or native screen repaints instantly.
No images, accounts, or artwork pixels are sent to a new service.

Both features are opt-in, off by default. Neither setting changes paid-service access.

## Remaining original 0.51 release gaps

| Original feature | Fork status at the start of this branch | This batch |
| --- | --- | --- |
| Audio-reactive visualizer | No matching implementation found | Not implemented |
| Workshop downloads | Existing local effects/preset tools, no matching Workshop | Not implemented |
| New AutoMix transitions | Flag references do not establish engine parity | Not implemented |
| Animated artwork | Existing implementation | Latest release fixes not verified |
| Artist logos | Not established by this audit | Not implemented or verified |
| Lyric meanings | Existing implementation | Latest release fixes not verified |
| Vibrations/music haptics | Existing implementation | Latest release fixes not verified |
| Player volume slider | Not found in inspected controls | Device-volume candidate added |
| Song-following accent | Manual choice only | Kit-token candidate added |
| Lightweight Sing model | Existing ~489 MB model weights | Not implemented |
| Redesigned DJ and Home changes | Dedicated new behavior not established | Not implemented |
| Browser/passkey account sign-in | No dedicated implementation found | Not implemented |
| Spotify 9.1.90 compatibility and speed/lyrics fixes | Not device-tested | Not verified |

Source presence is not evidence that a feature works on a device. This matrix does
not claim a complete inventory of every original setting or backend-dependent feature.
A feature can be similar without being 1:1 equivalent to the original implementation.

## Why version labels cannot drive source parity

Upstream tags v0.50.0 and v0.51.0 both resolved to source commit
425d68bc1761e90a6b5828864720511bcef79fa9 during the audit. The fork's October 14
commit 8f4342e updated only version.txt and .last-built-og-tag. Rebuilding that code
cannot supply missing feature implementations. Do not describe this branch as a
merge of new upstream 0.51 implementation code.

Future work should compare source SHAs and actual feature tests, not automatically
copy upstream release notes into a relabelled build. Monitoring a release does not
by itself implement or validate an independently written equivalent.

## Source provenance and scope

The only pre-existing files edited by this batch are:

- tweak/Sources/Redesigned/Kit/SGRTokens.m
- tweak/Sources/Redesigned/Kit/SGRAppearanceSettings.m

Their pre-edit contents match the GPL-3.0 snapshot at upstream v0.21.1, commit
a08b38b9e293f0893e92ff7a9b7b9d92f903431a, byte-for-byte. The GPL copy and upstream
attribution remain in history; these two files are marked GPL-3.0-only. The new
feature modules and test scripts were independently written and marked MIT.
No closed release binaries or later restricted implementations were copied to create
these additions. This limited provenance check does NOT relicense the rest of this
mixed-history fork or authorize distribution of a proprietary Spotify application.
Resolve the whole-tree licence and asset rights before any public binary release.

## Validation

Portable checks:

    sh harness/player-parity/check.sh

Apple SDK syntax checks (macOS/Xcode, with the Logos checkout in LOGOS_DIR):

    sh harness/player-parity/check-ios.sh

The added Player parity checks workflow runs both on pull requests and can be started
manually. It has read-only repository permissions, no signing or IPA secrets, and
publishes no releases. Syntax checks are not a full tweak link or a device test.

Before merging or shipping, verify:

- iPhoneOS syntax checks and a full supported-host tweak build succeed.
- Volume row appears exactly once and adjusts the current audio route.
- Remote Connect, fixed-volume routes, Bluetooth, AirPlay, rotation and small screens.
- No footer/lyrics/control clipping or Auto Layout warnings.
- VoiceOver volume adjustment and large accessibility text.
- Artwork A to B while A's extraction is in flight; no stale colour.
- Same-track artwork identity replacement and late exact artwork delivery.
- Missing/offline/gray artwork and rapid enable/disable/reset transitions.
- Existing customizations behave as before, with both additions switched off.

No ready-to-install build or 1:1 feature parity is asserted by these source changes.

# Batch B: the remaining 0.51 features (October 15, 2026)

All switches below are off by default. Nothing here changes paid-service behaviour,
version.txt, or the fork's existing customizations. Not yet compiled for iOS or tested on
a device at the time of writing: the first "Build IPA" run is the compile test.

| Original 0.51 feature | What this batch adds | Where |
| --- | --- | --- |
| Visualizer | Audio visualizer: a third player background. Soft glows in the cover's colours moving with low/mid/high bands, read from the output audio through a new pipeline stage. 30 fps, 15 in Low Power Mode, still under Reduce Motion. | Mod Settings > Player > background choice |
| The Workshop | Library: import YOUR OWN files from the Files app. Lyrics fonts (.ttf/.otf), audio presets and headphone corrections (reuses the existing import pages), visualizer looks (.json), and a Sing voice model folder or .zip. No download server is contacted. | Mod Settings > Library |
| Lighter Sing model | "Use custom model" in Library: Sing loads a user-supplied separator.mlmodelc instead of the ~489 MB download. I cannot train or export a smaller model here; this makes one usable if you have it. | Mod Settings > Library > Sing voice model |
| AutoMix | Transitions: NOT AutoMix. A gain ramp (-12 dB to 0) and a low-pass sweep over the first 200-2000 ms of each new track. It cannot beat-match or fade the outgoing track, because the output tap only sees the audio being played. The switch's info text says so. | Mod Settings > Player > Transitions |
| Home shortcuts on tinted glass | Shortcut tiles drawn as glass tinted toward their cover colour. Needs a screenshot to tune. | Appearance > Home shortcuts on glass |
| DJ gets the redesigned player | DJ card restyled with the artwork field, Kit radius and a glass control. Found by shape; if the view tree differs nothing changes and one log line says so. | Appearance > DJ card in the player's look |
| More Appearance options | Glass strength (50-150%) and Accent intensity (60-140%, kept at >= 4.5:1 on #121212). Native look gets a "Follow artwork colours" row, but it only replays a colour last read under Redesigned UI (the native look has no artwork reader yet); the row says so. | Appearance |
| Spotify 9.1.90 support | Not done (needs that IPA). Added "Hook report" under About: lists every Spotify class the hooks asked for, found or missing, with a Copy button, so a move to 9.1.90 shows exactly what broke. | Mod Settings > About > Hook report |
| Sign in in the browser with passkeys | Not done. It rewires Spotify's account login; cannot be done or tested safely here. | - |
| Artist logos | Not done; no data source without the original's backend. | - |
| Animated artwork, lyric meanings, Vibrations free | Already in the fork from the GPL base with no paid gate. | - |

## Files

New (all MIT): Shared/Visualizer/*, Shared/Transitions/*, Shared/Library/*,
Shared/Player/TrackAccentBridge.*, Redesigned/Kit/SGRVisualizerLayer.*,
Redesigned/Player/PlayerVisualizer.x, App/About/HookReport.m, harness/parity-b/*.

Edited pre-existing files: 27. Of these, 15 were byte-identical to the GPL-3.0 v0.21.1
snapshot before this batch (SGLog.h/.m, Native/Appearance/*, Redesigned/Home/*,
SGRGlass.h, SGRTokens.h, Redesigned/Lyrics/LyricsText*.{h,m}, LyricsTextSettings.m);
8 had already diverged from it in the fork; 4 did not exist in the GPL snapshot
(SGRTrackAccent.m from batch A, PlayerBackgroundSettings.m, SGAudioPipeline.h,
SGSingModel.m). Edits to the last group are small (an enum line, a model-path check)
and are listed in the PR. This is a record, not a relicensing of the fork.

## Validation done here

Standalone C tests for the band analyser (sine at 100 Hz / 1 kHz / 8 kHz, silence, NaN,
clipping) and the transition DSP (monotonic gain, stable biquad, identity at zero length,
bit-exact across render sizes), both under UBSan. Logos preprocessing of all six touched
.x files with balanced output. Layer-boundary check. A read-through review that found and
fixed five runtime bugs (a two-writer seqlock, a torn parameter struct on the render
thread, a presentation inside the picker's dismissal, an inflate loop with no progress
guard, and a misleading row subtitle). No iOS compile here.

## Device checklist

- Build succeeds. If not, send the log: the new pipeline stages and the Metal shader are
  the most likely culprits.
- Visualizer: pick it, play music; glows move with the beat; still under Reduce Motion;
  no stutter in the player; battery acceptable.
- Transitions: skip tracks; the entry is softened; pause/resume does nothing; Status row
  counts entries.
- Library: import a .ttf, pick it under Lyrics > Font, lyrics change; import a .json look;
  import a model folder, switch on, Sing still works.
- Home glass tiles and DJ card: screenshots, please; both are blind restyles.
- Hook report: open it once now on 9.1.88 to record the baseline (Copy report).
