<p align="center">
  <img src="docs/icon.png" width="96" alt="">
</p>

<h1 align="center">taurus.</h1>

<p align="center">Spotify for iOS, rebuilt to look and feel like Apple Music.<br>A fork of spoti.pw from before it went closed-source, kept going with features of its own.</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-15%2B-000000?style=for-the-badge&logo=ios&logoColor=white" alt="iOS 15+">
  <img src="https://img.shields.io/badge/Spotify-9.1.88-1ED760?style=for-the-badge&logo=spotify&logoColor=white" alt="Spotify 9.1.88">
  <img src="https://img.shields.io/badge/Objective--C-3A95E3?style=for-the-badge&logo=apple&logoColor=white" alt="Objective-C">
  <img src="https://img.shields.io/badge/GitHub_Actions-2671E5?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Actions">
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#compared-with-the-original-spotipw-051">Compared with the original</a> ·
  <a href="#build-it">Build it</a> ·
  <a href="docs/player-parity-status.md">Status notes</a>
</p>

<p align="center">
  <img src="docs/screenshots/now-playing.webp" width="16%" alt="Full screen player with lyrics">
  <img src="docs/screenshots/album.webp" width="16%" alt="Album">
  <img src="docs/screenshots/playlist.webp" width="16%" alt="Playlist">
  <img src="docs/screenshots/queue.webp" width="16%" alt="Queue">
  <img src="docs/screenshots/live-activity.webp" width="16%" alt="Live Activity on the lock screen">
  <img src="docs/screenshots/home.webp" width="16%" alt="Home">
</p>

A no-jailbreak Theos tweak injected into your own decrypted Spotify IPA and signed with your own
certificate. No IPA is distributed here.

The goal is simple: Spotify should look and behave like Apple Music. Liquid Glass, the Music app's
player, its tab bar, its star, its lyrics.

## Features

Everything new is **off by default** unless it says *on by default*, so turning on the mod doesn't
change your app in ways you didn't ask for. All switches live in **Settings → Mod Settings**.

### Inherited from spoti.pw (before it closed)

The base this fork started from. Credit for all of it goes to the original author.

- **Liquid Glass redesign** of Home, Search, Library, albums, playlists, artists and the player
- **Apple Music–style full-screen player** with bare playback glyphs, lyrics in place of the cover,
  and the cover morphing out of the now playing bar
- **Fluid artwork** background (the cover warped and blurred behind the player) and **animated
  artwork** (Canvas or Apple Music's animated covers)
- **Synced and word-by-word lyrics** from several sources, translations, **lyric meanings**
- **Lyrics on the lock screen** and a **Live Activity** (iOS 17+)
- **Sing**: on-device vocal removal for karaoke (see the note under *Known limits*)
- **Audio effects**: EQ, graphic EQ (AutoEq), headphone correction (DDC), reverb, crossfeed, Liveprog
- **Speed and pitch**, **Vibrations** (control haptics and music haptics), gestures
- Custom tab bar, accent colour, AMOLED black, app icons, artist blocking, privacy options

### Added in this fork

**Apple Music look**
- **Tab bar minimizes on scroll** *(on by default)*: scroll down and the bar folds into a small glass
  circle holding the current tab, like the Music app; scroll up or tap it to bring it back. Works on
  every iOS version, not only iOS 26.
- **Favourite star** *(on by default)*: the green add button in the player becomes the Music app's
  star, filled in your accent colour once a song is saved.
- **Follow artwork colours**: the accent colour follows the current song's cover. Also offered for
  the classic look (it reuses the last colour from the redesign).
- **Accent intensity** and **glass strength** sliders.
- **Home title collapses on scroll** into a small centred title over a hairline.
- **Home shelves only**: Home starts with its first shelf, like Top Picks.
- **Home shortcuts on glass** and the **DJ card in the player's look**.
- **Tinted Play and Shuffle** on album and playlist headers.

**Player**
- **Device volume slider** in the player (controls this iPhone's output; not Spotify Connect).
- **Audio visualizer**: a third player background, soft glows in the cover's colours that move with
  the bass, mids and highs. Intensity, motion, glow count and colour source are adjustable, and you
  can save a look.
- **Transitions**: softens the start of each new track with a short volume ramp and filter sweep.
- **Sleep timer**: 15–90 minutes or end of track. Pauses playback; it doesn't fade.

**Library** (new Mod Settings page). Import your own files from the Files app; nothing is downloaded:
- Lyrics **fonts** (.ttf / .otf), then pick one under Lyrics → Font
- Audio presets and headphone corrections
- Visualizer **looks** (.json)
- A custom **Sing voice model** (`separator.mlmodelc`) in place of the 489 MB download

**Diagnostics**
- **Hook report** (About): every Spotify class the mod looks for, found or missing, with a Copy
  button. When Spotify updates, it shows exactly what broke.

## Compared with the original spoti.pw 0.51

The original's 0.51 release ([notes](https://github.com/skopevoj/spoti.pw/releases/tag/v0.51.0)) ships
as a compiled build; its newer source isn't public. Everything in the right-hand column was written
independently for this fork. Nothing was copied from the original's closed releases.

| Original 0.51 feature | In this fork |
|---|---|
| Visualizer | ✅ Own implementation: audio visualizer background with its own settings and saved looks |
| The Workshop (downloadable shaders, presets, corrections, fonts) | 🟡 **Library** instead: you import your own files; there's no download catalogue |
| AutoMix | 🟡 **Transitions**: softens each track's start. It doesn't beat-match or blend two songs, so it's not AutoMix |
| Lighter Sing voice model | 🟡 You can load your own smaller model in Library; no smaller model is included |
| Volume slider in the player | ✅ |
| Accent colour that follows the song | ✅ For both looks |
| Animated artwork, artist logos, lyric meanings, Vibrations | ✅ Animated artwork, lyric meanings and Vibrations (inherited). ❌ Artist logos |
| More Appearance options | ✅ Glass strength, accent intensity, Home and header options |
| Home shortcuts on tinted glass | ✅ |
| DJ in the redesigned player | ✅ DJ card styled like the player |
| Spotify 9.1.90 support | ❌ Not yet. Builds against 9.1.88; the Hook report is there for the move |
| Sign in through the browser with passkeys | ❌ Not attempted: it changes Spotify's login and can't be done safely blind |
| — | ➕ Tab bar minimizing on any iOS, favourite star, Home title collapse, shelves-only Home, tinted Play/Shuffle, sleep timer, Hook report |

✅ done · 🟡 partly, or a different approach · ❌ not in this fork · ➕ only in this fork

## Known limits

- **Sing needs Spotify 9.1.78.** It reads Spotify's audio engine at addresses taken from that exact
  build. On any other version it can't start, and it now says so instead of blaming the audio format.
  With a 9.1.78 IPA it works at 44.1, 48, 88.2 and 96 kHz, lossless included.
- **The sleep timer doesn't fade.** Spotify gives the mod no player-volume control, and the mod
  won't change your system volume.
- **Some features are only lightly device-tested.** The Home glass tiles, DJ card and Home title
  collapse were laid out without screenshots of every phone size. Reports with screenshots help.
- The redesign uses real Liquid Glass on **iOS 26**; on earlier versions it falls back to a blur.

## Build it

Bring your own decrypted Spotify IPA (**9.1.88** for this build; **9.1.78** if you want Sing). You get
an unsigned `.ipa` to sign with SideStore, Feather, AltStore or Sideloadly.

### Build with GitHub Actions (no Mac needed)

1. Fork this repo and enable **Actions**.
2. Store a direct link to your decrypted IPA as the repository secret `IPA_URL`, or paste it when you run the workflow.
3. Run **Build IPA from your own Spotify IPA** and set **upload_method** to `artifacts`.
4. Download **spoti.ipa** from the **Artifacts** section at the bottom of the run page. It arrives
   zipped; unzip it to get the `.ipa`.

Keep `upload_method` on `artifacts`. The `release` option publishes the IPA on your public
Releases page.

### Build on a Mac

Theos in `~/theos` and Xcode with an iPhoneOS 26 SDK (`xcode-select` it). Then:

    brew install make ldid dpkg zsign ideviceinstaller libimobiledevice
    uv tool install "cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw"

Put the decrypted `.ipa` in `ipa/`, then:

    make release    # out/spoti.pw-<version>.ipa, ready to sign
    make install    # the same, signed with your certificate and pushed over USB

`make install` reads `SIGN_P12`, `SIGN_PROFILE` and `SIGN_P12_PASSWORD` from `.signing.env`; copy
`.signing.env.example` and fill it in.

### Signing

Sign with a bundle id matching your certificate's App ID, or tapping the lock-screen player won't open
the app (the app tells you which id to use on first launch). In Feather, copy the App ID into
**Identifier** and leave **PPQ protection** off. The app keeps Spotify's bundle id, so it installs over
the real Spotify.

## Credits

- [spoti.pw / chroma.pw](https://github.com/skopevoj/spoti.pw) by darkk: the redesign and most of
  the inherited features. If you like the original work, [support the author](https://ko-fi.com/darkksh).
- [cyan](https://github.com/asdfzxcvbn/pyzule-rw) injects, [Theos](https://theos.dev) builds,
  [FLEX](https://github.com/FLEXTool/FLEX) (AutoFLEX in `vendor/`) inspects.
- Sing's model: [MelBandRoformer vocal CoreML](https://huggingface.co/mlboydaisuke/MelBandRoformer-Vocal-CoreAI) (MIT).

## License

This fork's history is mixed. Code taken from spoti.pw up to **v0.21.1** was published under
**GPL-3.0** and stays under it. Later upstream code is under the original's
[PolyForm Strict 1.0.0](LICENSE) terms. Files written for this fork say so in their own
`SPDX-License-Identifier` header. See [docs/player-parity-status.md](docs/player-parity-status.md)
for which files came from where. Files in `vendor/` keep their own licences.

Not affiliated with Spotify or Apple.
