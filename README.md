# Jarvis — a JARVIS-like AI assistant for Android

A Flutter app: chat + voice with Claude, an "open app / set an alarm /
call someone" on-device command layer, and a foreground wake-word
("Jarvis") listening mode. Full source is in this folder — read
**"Why you're getting source, not a .apk"** below before anything else.

## Why you're getting source, not a .apk

Building an Android app means compiling against Google's Android SDK and
(for Flutter) downloading Flutter's engine binaries — both served only
from Google's own servers (`dl.google.com`, `storage.googleapis.com`).
The sandboxed environment this project was built in has its outbound
network access restricted to a handful of package registries (npm,
pypi, GitHub) and cannot reach either of those Google hosts, so there is
no way to actually run `flutter build apk` there. Rather than hand you a
half-built project, everything below gets you a real, installable
`app-release.apk` in a few minutes using infrastructure that **can**
reach Google's servers.

## Fastest path: let GitHub build it for you (no installs, ~5 min)

This repo already includes `.github/workflows/build-apk.yml`, a GitHub
Actions workflow that builds a release APK on GitHub's own servers
(which have full internet access) every time you push.

1. Create a new **public or private** repo on GitHub (empty, no README).
2. Upload this whole folder to it. Easiest way, no `git` required:
   on the new repo's page, click **"uploading an existing file"** and
   drag in everything in this folder (or use `git push` if you're
   comfortable with git — see below).
3. Open the repo's **Actions** tab. A run called "Build Jarvis APK"
   starts automatically (or click **"Run workflow"** if it doesn't).
4. When it finishes (green check, a few minutes), click into the run →
   **Artifacts** → download **jarvis-release-apk**. Unzip it — that's
   your `app-release.apk`.
5. AirDrop/email/Drive it to your phone, or just download it directly
   from GitHub on your phone's browser.

If you'd rather use git from a terminal:

```bash
cd jarvis_app
git init
git add .
git commit -m "Jarvis assistant"
git branch -M main
git remote add origin https://github.com/<you>/<repo>.git
git push -u origin main
```

## Alternative: build it yourself locally

If you already have (or want) Flutter installed:

```bash
cd jarvis_app
flutter pub get
flutter build apk --release
# APK lands at build/app/outputs/flutter-apk/app-release.apk
```

Flutter install docs: https://docs.flutter.dev/get-started/install
(the installer also grabs the Android SDK bits Flutter needs).

## Installing the APK on your phone

1. Copy `app-release.apk` to your phone (Drive, email, USB, whatever).
2. Tap the file. Android will prompt you to allow installs from that
   source ("Install unknown apps") — allow it, then tap **Install**.
3. This is a self-signed personal build (fine for sideloading, same as
   the debug key Android Studio uses) — you may see a Play Protect
   warning; tap "Install anyway."

## Setting it up after install

1. Open the app, tap the gear icon (top right) → Settings.
2. Paste an **Anthropic API key** (get one at console.anthropic.com →
   API Keys). It's stored only in Android's encrypted storage on your
   phone and sent straight to `api.anthropic.com`. This works standalone
   with no backend server — or see step 6 to add persistent memory.
3. Optionally flip on **"Speak replies aloud"** and the **wake-word
   toggle**, and set a personality/system prompt.
4. Grant the microphone / phone permissions when Android asks.
5. To use the **overspeed alarm**, flip on "Enable overspeed alarm" and
   set your speed limit (km/h). Android will ask for location
   permission twice — first "while using the app," then a second
   prompt for **"Allow all the time"**; you need to accept the second
   one too, or the alarm will stop working as soon as you lock your
   screen (which defeats the point while driving).
6. **Optional — persistent memory.** Deploy the companion
   `jarvis_server/` project (a small self-hosted server — see its own
   README) on a Raspberry Pi/NAS/home server, then in Settings →
   "Private server" enter its URL and token. Once set, chat routes
   through your server instead of straight to Claude: it remembers past
   conversations, preferences/goals you save in the new **Memory**
   screen (brain icon, top bar), and notes/documents you add in the new
   **Documents** screen (page icon, top bar) — pulling in whichever are
   relevant to each question automatically.

## What's actually built vs. what's a stub

Built and working out of the box:
- Text + voice chat with Claude (tap the mic, or type).
- Text-to-speech replies.
- On-device commands that don't touch Claude at all: "open spotify",
  "open whatsapp", "set an alarm for 7am", "set a timer for 10 min",
  "call mom", "search for nearby coffee" (see the app-name → package
  map in `lib/services/device_control_service.dart` — add more apps
  there).
- A wake-word toggle that continuously listens for the word "Jarvis"
  **while the app is open/foregrounded**.
- An **overspeed alarm**: watches GPS speed — including with the
  screen off, via a background location service — and fires a spoken
  warning + vibration + notification whenever you're over the km/h
  limit you set in Settings, with a 20-second cooldown so it doesn't
  nag continuously. Shows a persistent "monitoring" notification while
  active (Android requires this for background GPS tracking to keep
  running) and a live speed chip in the app's top bar.
- Optional **persistent memory** via the companion `jarvis_server/`
  project: once configured in Settings, chat automatically gets your
  saved preferences/goals and relevant documents injected as context,
  and conversations survive app restarts. The app talks to it over
  plain HTTP by design (`usesCleartextTraffic="true"` in the manifest)
  since a home server on your LAN/Tailscale usually isn't running a TLS
  cert — Claude calls (when no server is configured) always stay HTTPS
  regardless.
- **Memory** and **Documents** screens (icons in the chat top bar) for
  viewing/adding/deleting what your private server remembers.

Stubbed, on purpose, because they need info only you have:
- **True always-on wake word** (screen off, app fully backgrounded).
  Android does not let a normal app hot-listen to the mic in the
  background without a dedicated low-power wake-word engine running in
  a foreground service. The most common way to add this is
  [Picovoice Porcupine](https://picovoice.ai/) (has a free tier) — sign
  up for an `AccessKey`, then swap the loop in
  `lib/services/voice_service.dart` for their `porcupine_flutter`
  plugin. The permissions for a foreground mic service are already
  declared in `AndroidManifest.xml`.
- **Smart home control** ("turn off the lights"). No hub/vendor was
  specified, so `lib/services/smart_home_service.dart` ships as a clean
  interface plus a documented example (`HueBridgeExample`) for a
  typical HTTP+token hub (Philips Hue, Home Assistant's REST API,
  SmartThings, etc.) — fill in your bridge's URL/token and swap it in
  where `NoOpSmartHomeService` is constructed in `lib/screens/chat_screen.dart`.

## Project layout

```
lib/
  main.dart                     app entry point + theme wiring
  theme.dart                    dark "arc reactor" color theme
  models/message.dart           chat message model
  screens/chat_screen.dart      main chat UI, ties everything together
  screens/settings_screen.dart  API key / server / model / prompt / toggles
  screens/memory_screen.dart    preferences/goals CRUD (needs a server)
  screens/documents_screen.dart notes/documents CRUD (needs a server)
  services/claude_service.dart  calls Anthropic's Messages API directly
  services/jarvis_server_service.dart    calls your private server instead
  services/voice_service.dart   speech-to-text, text-to-speech, wake loop
  services/device_control_service.dart   open apps / alarms / calls
  services/overspeed_service.dart        GPS speed alarm
  services/smart_home_service.dart       extensibility stub
  services/storage_service.dart          secure storage + settings
  widgets/chat_bubble.dart      chat bubble UI
android/                        standard Flutter Android project
.github/workflows/build-apk.yml CI that builds the release APK
```

The companion backend lives in a sibling `jarvis_server/` folder (own
README, own repo if you want) — it's a separate deployable project, not
part of this Flutter app's build.

## Before you publish this anywhere public

- `android/app/build.gradle` uses `applicationId "com.jarvis.assistant"`
  — change it to something you own if you ever publish to the Play
  Store.
- The release build is signed with the auto-generated Android **debug**
  key, which is fine for installing on your own phone but not for
  distributing to others or publishing. Generate a real signing key
  (`keytool -genkey ...`) and point `signingConfigs` at it before
  sharing this more broadly.
