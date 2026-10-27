# Memory

Durable facts for this repository. Read this at the start of a session. Update it in the same session when a lasting decision changes. Do not store secrets, tokens, or passwords.

## Product

Shot n Translate is a macOS-only app. It processes a screenshot, detects text in the image, translates that text, and saves both the original content and the translation in one PDF.

- Platform: macOS 26 or later. No other platform for now.
- Stack: Swift and SwiftUI, Apple frameworks only. No third-party packages.
- Capture: ScreenCaptureKit. Text recognition: Vision. Source-language detection: NaturalLanguage. Translation: Translation. PDF: PDFKit.
- Region translation is built. The user drags a rectangle, the app reads the text, detects its language, and translates it into the selected target. The result window shows the detected language, the original text, and the translation.
- Source-language detection uses NaturalLanguage hypotheses and script heuristics (for example Turkish diacritics). Short plain Latin OCR text falls back to English. The installed Vision SDK does not expose a per-line recognition language, so that hint is not read. If the code is still unknown, translation still runs with an automatic source language.
- Text recognition normalizes the screenshot to 8-bit sRGB before Vision. `minimumTextHeight` is one pixel of the image height so body text in a tall region is kept.
- Region capture uses the display that contains the selection. `SCScreenshotManager.captureImage(in:)` only reads the main display, so a selection on another screen comes back black and OCR reports no text. The capture is 8-bit BGRA, the app's own windows are excluded, and the result window is shown only after the shot. A black shot is reported as a missing Screen Recording permission. When no text is found, the result window shows the captured image.
- 0.3.0 installed from the menu and still reported no text. 0.3.1 showed that the captured image itself was black. 0.3.2 captures the selected display. It is not published until a Mac packages and uploads the zip.
- Translation uses SwiftUI `translationTask`, so macOS can ask the user to download a missing language. If the text is already in the target language, it is not sent to the translator.
- PDF export is not built yet.
- Screen Recording permission is required. The packaged app declares `NSScreenCaptureUsageDescription`.
- Capture rectangles are clipped to the `NSScreen` that contains the selection, then converted to that display's local top-left coordinates for `SCStreamConfiguration.sourceRect`. The shot uses `SCContentFilter` for that display and an 8-bit BGRA pixel format.
- Shortcuts live in the Shortcuts menu and are registered globally with Carbon `RegisterEventHotKey`, so they work while another app is focused. Quit stays Command-Q on the menu only.
- Translate Selection: Command-Shift-T. Check for Updates: Command-Shift-U. Update History: Command-Shift-H.

## Language

- The source language is always detected from the recognized text. There is no manual source picker.
- The translation target is Turkish or English. The default target is Turkish (`TranslationTarget.defaultTarget`).
- The app UI is Turkish and English. The default UI language is Turkish (`AppLanguage.defaultLanguage`). Changing that constant changes the default. A language the user already chose is kept.
- The language switch is instant. Every user-facing string exists in both languages through `L10nKey`.
- Talk with the user about this project in Turkish. Write repository files, commits, pull requests, and patch notes in English.

## Updates

- From the menu, the user can check for updates, read the history, install a newer version, and restore an older version.
- Patch notes are the English GitHub Release text. Show them as published. Do not translate them per language.
- The repository is public. Release checks and downloads work without a GitHub account.
- Publish stable releases only. The asset is `ShotNTranslate.zip` and it contains `Shot n Translate.app`.
- Published releases: 0.1.0, 0.2.0, and 0.3.0. 0.3.0 is the current published release. Its zip is `ShotNTranslate.zip`, version 0.3.0, build 3, and it contains region translation. The user installed 0.3.0 from the menu. Source marketing version is now 0.3.2, build 5. 0.3.1 and 0.3.2 are not published. 0.3.1 still captured a black image for a text selection.
- Version and bundle identity live in `Sources/ShotNTranslateCore/AppReleaseIdentity.swift`.

## Repository

- GitHub: https://github.com/onigiz/shot-n-translate
- Owner login: `onigiz`
- Visibility: public
- Default branch: `main`

## Do not forget

- macOS only for now.
- Source language is automatic. Translation target is Turkish or English.
- Keep English and Turkish UI strings ready, with Turkish as the default.
- Keep the in-app update history, install, restore, and English patch notes.
- Keep commits, pull requests, and patch notes in English.
- Keep updates readable by anyone, without a GitHub login.
- Keep this file current in every session.
