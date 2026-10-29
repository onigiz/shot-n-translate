# Memory

Durable facts for this repository. Read this at the start of a session. Update it in the same session when a lasting decision changes. Do not store secrets, tokens, or passwords.

## Product

Shot n Translate is a macOS-only app. It processes a screenshot, detects text in the image, translates that text, and saves both the original content and the translation in one PDF.

- Platform: macOS 26 or later. No other platform for now.
- Stack: Swift and SwiftUI, Apple frameworks only. No third-party packages.
- Capture: ScreenCaptureKit, with `/usr/sbin/screencapture -R` as a fallback when the SCK crop is still nearly black. Text recognition: Vision + Live Text. Source-language detection: NaturalLanguage. Translation: Translation. PDF: PDFKit.
- Region translation is built. The user drags a rectangle, the app reads the text, detects its language, and translates it into the selected target. The preview keeps the whole screenshot on top. Under it, the translation is a basic word-style editor: the text itself, bold, italic, underline, text color, size, and left, center, or right alignment. The editor background is light or dark. Closing without saving discards the capture. Save writes one PDF with the image and the edited text on that same background.
- Translation area is a menu setting, stored in `TranslationSettings.scope`. The default is immediate: the whole screenshot is translated, and the preview can later select a region and translate that text again. The other choice asks for the region before the first translation. Either way the stored screenshot is not cropped; only recognition uses the selected pixels. While that image region is being chosen, Command-A selects the whole screenshot and continues. That shortcut is local to the region window. It is not a global Carbon shortcut.
- Source-language detection uses NaturalLanguage hypotheses and script heuristics (for example Turkish diacritics). Mostly Latin text cannot be labeled Japanese, Chinese, or Korean because of a stray OCR character; NaturalLanguage is limited to Latin languages in that case, and English is the confident fallback. A confident code is passed to Translation. A weak code, including a Vision hint alone, is not. The preview can correct the source language and translate again. Short plain Latin OCR text falls back to English. The installed Vision SDK does not expose a per-line recognition language, so that hint is not read.
- Text recognition normalizes the screenshot to 8-bit sRGB, then runs Live Text (`ImageAnalyzer`) and Vision horizontal bands. The chosen transcript is the one that still contains the words after paragraph preparation. A line-broken copy of the same words does not beat a paragraph transcript. Dark pages (low mean luminance with real contrast) are inverted and scanned again. Accurate Vision passes time out into a fast pass so a compiling on-device model cannot block the capture. Row clustering keeps reading order left-to-right within visual rows.
- Region capture uses the display that contains the selection. `SCScreenshotManager.captureImage(in:)` only reads the main display, so a selection on another screen comes back black and OCR reports no text. The capture is 8-bit BGRA, the app's own windows are excluded, and the result window is shown only after the shot. When no text is found, the result window shows the captured image. A permission error is shown only when this build itself lacks Screen Recording access.
- 0.3.0 installed from the menu and still reported no text. 0.3.1 showed that the captured image itself was black. Later packages kept asking for Screen Recording because an older grant stayed switched on while its code requirement no longer matched the running app. macOS then shows a dialog with no Allow button. 0.3.9 does not call ScreenCaptureKit until permission is already granted, and Reset Permission runs `tccutil reset ScreenCapture` once so the switch can apply to this copy. The package signature must not be pinned to a cdhash. A short region was read in 0.3.9, and a taller region on the same page came back empty. 0.3.11 scans with Live Text. 0.3.12 adds screencapture fallback, dark-page inversion, accurate→fast timeout, and picks the richest Live Text/Vision candidate. 0.3.13 shortens the Screen Recording denial UI so Reset Permission stays visible. 0.3.13 is the published release that includes those fixes. 0.3.1 through 0.3.12 were not published separately.
- Translation uses SwiftUI `translationTask`, so macOS can ask the user to download a missing language. Before that call, wrapped lines become sentences and end-of-line hyphenation is joined. OCR line gaps separate paragraphs. A short title is its own heading, and a heading underline read as a bar is not part of the sentence. A blank line, a list item, or a short line that ends a sentence before a new capitalised line is also a paragraph. Apple Translation then translates one paragraph at a time. The editor and the PDF keep one blank line between those paragraphs. A full-width line that merely ends a sentence stays in the same paragraph. The on-device model remains the limit on meaning. If the text is already in the target language, it is not sent to the translator.
- PDF export writes the screenshot and the edited translation. Formatting from the editor is kept. The PDF is not written when the window closes.
- Screen Recording permission is required. The packaged app declares `NSScreenCaptureUsageDescription`. `scripts/sign-app.sh` signs with an Apple Development or Developer ID identity when one is in the keychain, otherwise with one local certificate stored in `~/Library/Application Support/Shot n Translate/signing`. The designated requirement is the bundle identifier and that certificate, never the build hash. A shortcut must not call ScreenCaptureKit or `CGRequestScreenCaptureAccess` while preflight is false; those calls show the system dialog again. Reset Permission clears the stored grant once, then asks once. The user turns the switch on and quits and reopens. Shareable content is listed off the main thread, because doing it on the main thread reports a false denial.
- Capture rectangles are clipped to the `NSScreen` that contains the selection, then converted to that display's local top-left coordinates for `SCStreamConfiguration.sourceRect`. The shot uses `SCContentFilter` for that display and an 8-bit BGRA pixel format.
- Shortcuts live in the Shortcuts menu and are registered globally with Carbon `RegisterEventHotKey`, so they work while another app is focused. Quit stays Command-Q on the menu only.
- Translate Selection: Command-Shift-T. Check for Updates: Command-Shift-U. Update History: Command-Shift-H.

## Language

- The source language is detected from the recognized text. The preview menu can correct it. There is no source picker in the menu bar.
- The translation target is Turkish or English. The default target is Turkish (`TranslationTarget.defaultTarget`).
- The app UI is Turkish and English. The default UI language is Turkish (`AppLanguage.defaultLanguage`). Changing that constant changes the default. A language the user already chose is kept.
- The language switch is instant. Every user-facing string exists in both languages through `L10nKey`.
- Talk with the user about this project in Turkish. Write repository files, commits, pull requests, and patch notes in English.

## Updates

- From the menu, the user can check for updates, read the history, install a newer version, and restore an older version.
- Patch notes are the English GitHub Release text. Show them as published. Do not translate them per language.
- The repository is public. Release checks and downloads work without a GitHub account.
- Publish stable releases only. The asset is `ShotNTranslate.zip` and it contains `Shot n Translate.app`.
- Published releases: 0.1.0, 0.2.0, 0.3.0, 0.3.13, 0.3.15, 0.3.17, and 0.3.18. 0.3.18 is the current published release. Its zip is `ShotNTranslate.zip`, version 0.3.18, build 21. Source marketing version is 0.3.18, build 21. 0.3.14 and 0.3.16 were not published separately.
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
