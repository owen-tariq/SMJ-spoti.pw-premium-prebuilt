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
