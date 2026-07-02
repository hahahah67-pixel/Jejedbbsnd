<div align="center">

<img src="playstore-removebg-preview.png" width="120" alt="PenguinPlay icon">

# PenguinPlay Store 🐧 

**A one-line installer that brings a real, working Google Play Store to any Chromebook with Linux (Crostini) — even ones without native Android support.**

</div>

---
# DISCLAIMER: PLEASE READ!

the PenguinPlay store isn't a hack of ChromeOS, and it doesn't touch ARC++/ARCVM. It automates Google's own official, publicly documented developer tools — the Android SDK Command-line Tools, `sdkmanager`, `avdmanager`, the Android Emulator, and `adb` — so using them feels as close as possible to having a real Play Store app pinned to your shelf.

Click the icon once. First time, it quietly sets up a real Android device in the background. Every time after that, it just boots straight to Play Store.

## Install

Open a Linux (Crostini) terminal on your Chromebook and run:

```bash
bash <(curl -sL https://raw.githubusercontent.com/hahahah67-pixel/penguin-play-store/main/penguinplay-store-setup.sh)
```

That's it. It installs itself, creates a **Google Play Store** icon in your Chromebook's launcher, and offers to open it right away.

> Using `bash <(curl ...)` instead of `curl ... | bash` is intentional — the script pauses for your input at the end, and a plain pipe would eat that prompt. This form doesn't.

## What actually happens when you run it

1. Creates a hidden folder at `~/.playstore-emu/` to hold everything
2. Checks whether you already have the Android SDK installed anywhere — if so, it's reused as-is and nothing is downloaded
3. If not found: installs Java, then downloads Google's official SDK Command-line Tools, with a real progress bar
4. Installs `platform-tools`, the `emulator`, and a **Google Play–enabled** system image (tries a few recent Android versions until one is available for your Chromebook's CPU architecture)
5. Creates one persistent Android Virtual Device — created once, reused forever
6. Adds a **Google Play Store** entry to your ChromeOS Launcher (via `~/.local/share/applications/`, the standard integration point Crostini watches)
7. Boots Android and waits for it to actually finish starting — not just for `adb` to connect, for Android itself to be ready

## First launch vs. every launch after

The very first time the AVD boots, Android runs its own **"Set up your Android device"** wizard — sign in with a Google account, accept terms, etc. — same as unboxing a real phone. PenguinPlay waits for you to finish that (however long it takes), then opens Play Store automatically the moment you're done.

Every launch after that reuses the same virtual device, so it skips the wizard entirely, keeps your signed-in account, installed apps, game saves, and downloads, and goes straight to Play Store — just like a real phone that's already been set up.

## Requirements

- A Chromebook with Linux (Crostini) enabled (**Settings → Advanced → Developers → Turn on Linux**)
- A few GB of free space (SDK + emulator + system image + app data)
- An internet connection for first-time setup
- Developer mode turned on the chromebook. (Esc+reload+power note enabling developer options whips your chromebook data)

## Known limitations

- **Speed depends on your Chromebook.** Hardware-accelerated emulation needs `/dev/kvm`, and Google only exposes nested virtualization to Crostini on *some* boards/channels — not all. PenguinPlay checks and warns you if it's unavailable, but will still run in slower software mode either way. This is a ChromeOS platform limit, not something the script can work around.
- **This is the official Android Emulator, not ARC++.** It won't be pixel-identical in performance or integration to a Chromebook's native Play Store on models that have one — it's the closest thing Google's public tooling supports for models that don't.
- Play-enabled system images are signed with a release key on purpose, so root access isn't available — that's intentional and matches how a real, certified Android device behaves.

## Uninstall

```bash
rm -rf ~/.playstore-emu ~/AndroidSDK
rm -f ~/.local/share/applications/playstore.desktop
```

## FAQ

**Is this made by Google?**
No. the PenguinPlay store is an independent, unofficial project that automates Google's public Android SDK tools. It isn't affiliated with or endorsed by Google.

**Will this work on my specific Chromebook?**
If Crostini (Linux) works on it at all, the PenguinPlay store should too. How *fast* it runs depends on whether your board exposes hardware acceleration to Crostini, which varies by model.

**Do I need to already have Android Studio or the SDK installed?**
No — if PenguinPlay store doesn't find one, it downloads and sets one up automatically. If you already have one, it's detected and reused instead.

**What Lisence is Penguin Play store Liscensed under?
The Penguin Play Store is lisenced under is - APGL 3.0 public lisence, for information regarding this lisence and the law, please vist dmca.com

**How do I run the already-installed application though the terminal without using the desktop?
To run the application though the terminal instead of the desktop run - ~/.playstore-emu/launch.sh
