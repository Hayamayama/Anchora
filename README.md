# Anchora

Anchora is a macOS PDF study workspace built on Skim: read a PDF on the left, ask an AI assistant on the right, and pin answers back into the document as editable PDF notes.

It supports selected-text questions, OCR regions, image regions, page/PDF summaries, short local conversation memory, optional web verification, and standard PDF annotations.

## Install the app

Anchora is signed ad-hoc rather than with an Apple Developer ID, so macOS
quarantines it when a browser downloads it. On macOS 15 and later,
Control-clicking and choosing **Open** no longer gets past that.

**The short way.** Paste this into Terminal, replacing the URL with the one
from this repository's Releases page:

```sh
curl -L -o /tmp/Anchora.zip "PASTE_THE_RELEASE_URL_HERE" \
  && ditto -x -k /tmp/Anchora.zip /Applications \
  && xattr -dr com.apple.quarantine /Applications/Anchora.app \
  && open /Applications/Anchora.app
```

That downloads it, installs it, and clears the quarantine flag macOS attaches
to downloads. Clearing that flag is what skips the warning, so only run this
for a build you actually trust — check the checksum below against the file if
you want to be sure.

**The Finder way.** Unzip, drag `Anchora.app` to `/Applications`, double-click
it, and let macOS refuse. Then open **System Settings → Privacy & Security**,
scroll to the message about Anchora, click **Open Anyway**, and confirm. macOS
asks once per version.

Then open a PDF, show the AI pane, click `•••` → **Set OpenAI API Key…**, and
enter your own OpenAI Platform API key.

The key is stored only in your macOS Keychain. It is never saved inside a PDF or committed to this repository.

> ChatGPT Plus and an OpenAI API account are billed separately. Anchora uses your OpenAI Platform API key, so API usage (including Web verify) is charged to that API account.

### System requirements

- **macOS 14.0 or later.**
- **Apple Silicon (`arm64`).** Intel support requires a separately built universal/Intel release.

## Use it

- Select text and ask a question in the AI pane.
- `Option` + drag: OCR a PDF area. Recognition covers Traditional Chinese, Simplified Chinese and English.
- `Command` + `Option` + drag: send an image region.
- `Web verify`: search and check current claims, then show the web sources used.
- `Pin latest answer`: add the latest AI answer as an editable anchor note in the PDF.
- Under any answer: `Copy` it as plain text, `Pin as note` (a compact anchored note) or `Pin as text` (a text note visible on the page). Older answers keep their own PDF anchor, so a question asked three turns ago can still be pinned where it belongs.
- `Study map`: ask for a plan for working through the whole document — what order, what to focus on, what to skip, and what to be able to answer afterwards. Study profile only; it needs no selection.
- `•••`: summarize the current page or the complete PDF.

## Build from source

Requirements: current Xcode, and macOS 14.0 or later (the deployment target).

```sh
xcodebuild -project Skim.xcodeproj -scheme Skim -configuration Release \
  -derivedDataPath /private/tmp/anchora-derived \
  build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

The resulting app is at:

```text
/private/tmp/anchora-derived/Build/Products/Release/Anchora.app
```

## Publish a GitHub Release

```sh
Tools/package-release.sh
```

This runs the tests, builds Release, signs the bundle inside out, and writes
`Distribution/Anchora-<version>-macos-arm64.zip` with its checksum. The
`Distribution` folder is ignored by Git, so attach that file to the Release by
hand (or with `gh release create`) rather than committing it.

### Signing it properly

With an Apple Developer Program membership the same command produces a build
that opens with no warning and needs none of the install steps above:

```sh
xcrun notarytool store-credentials anchora \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD

ANCHORA_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ANCHORA_NOTARY_PROFILE=anchora \
  Tools/package-release.sh
```

The script then signs with the hardened runtime and a secure timestamp,
submits the archive to Apple, staples the ticket to the app, and rebuilds the
archive so the ticket travels with it.

This path has not been exercised: no Developer ID certificate has been
available on the machine Anchora is built on. Expect the first notarisation to
report something to fix — the bundle embeds Sparkle, its Updater helper app,
SkimNotes and a Spotlight importer, and every one of them has to satisfy the
hardened runtime.

Current release asset checksum:

```text
Anchora-1.5.0-macos-arm64.zip
SHA-256: 59444ff7b126bbde61fb6c1e1740be8149fd33d97f907b573078748e77cc13a5
```

## Run the tests

Anchora's own logic — the paper map parser, prompts, settings, and the chat
transcript model — is Swift with no AppKit or Skim dependency, so it can be
exercised without building the app:

```sh
Tools/run-anchora-tests.sh
```

## License and attribution

Anchora is a modified build of [Skim](https://skim-app.sourceforge.io/) and retains Skim's BSD 3-Clause license. See [LICENSE](LICENSE).
