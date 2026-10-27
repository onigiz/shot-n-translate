# Shot n Translate

macOS app that takes a screenshot, detects any text in the image, translates that text, and saves both the original content and the translation in a PDF.

The source language is detected automatically. The translation target is Turkish or English. The app interface is Turkish by default and can switch to English immediately.

## Status

The menu bar app, interface languages, translation target, and update history are in place. Screenshot capture, text recognition, and PDF export are not built yet.

## Platform

macOS 26 or later. Swift and SwiftUI, with no third-party packages.

## Languages

`AppLanguage.defaultLanguage` is the language used until a person chooses one in the menu. It is Turkish. Change that constant to change the default. A choice already stored on the Mac is kept.

Both English and Turkish strings live in `L10n`. Adding a string means adding it in both languages; the compiler and tests require every key in both.

## Translation

The menu stores the target language in `TranslationSettings.target`. Recognized text will be translated into that language. The user does not pick a source language.

## Updates

The menu can check for updates, show the history, install a newer version, and restore an older one. Patch notes are the English text of each GitHub Release and are shown as published.

Releases are public. Anyone can check for updates, read the patch notes, and install a version without signing in. See [docs/RELEASING.md](docs/RELEASING.md).

## Build

Swift Package Manager is enough. Full Xcode is not required.

```sh
swift run ShotNTranslateChecks
scripts/package-app.sh
open "dist/Shot n Translate.app"
```

The menu bar icon is a viewfinder. Open **Update History** from that menu.
