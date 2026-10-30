# Shot n Translate

macOS app that takes a screenshot, detects any text in the image, translates that text, and saves both the original content and the translation in a PDF.

The source language is detected automatically. Text that is sideways, upside down, or diagonal is turned upright for recognition, in steps of 5 degrees around the circle. The screenshot in the preview stays as it was captured. After translation, a handle on that image rotates it around its center. The image can also be cropped, and squares or circles can be drawn on it in a chosen color and outline thickness. The PDF uses that rotation, crop, and those outlines. The preview can correct that source and translate again. The translation target is Turkish or English. The menu can translate the whole screenshot immediately, or ask for a region of that screenshot first. The screenshot stays whole either way. The app interface is Turkish by default and can switch to English immediately.

## Status

The menu bar app, interface languages, translation target, update history, and region translation are in place. A shortcut menu assigns the keyboard shortcuts. The preview keeps the whole screenshot above an editable translation. The user can limit translation to a dragged area of that screenshot; Command-A during that choice uses the whole image. Save as PDF writes the image and the edited text. Closing the preview without saving discards it.

## Platform

macOS 26 or later. Swift and SwiftUI, with no third-party packages.

## Languages

`AppLanguage.defaultLanguage` is the language used until a person chooses one in the menu. It is Turkish. Change that constant to change the default. A choice already stored on the Mac is kept.

Both English and Turkish strings live in `L10n`. Adding a string means adding it in both languages; the compiler and tests require every key in both.

## Translation

The menu stores the target language in `TranslationSettings.target`. Recognized text will be translated into that language. The preview menu can correct the detected source. `TranslationSettings.scope` chooses whether translation starts on the whole screenshot or after the user drags a region. The preview can select that region again and replace the editor text. The stored screenshot is not cropped.

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
