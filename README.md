# Anchora

Anchora is a macOS PDF study workspace built on Skim: read a PDF on the left, ask an AI assistant on the right, and pin answers back into the document as editable PDF notes.

It supports selected-text questions, OCR regions, image regions, page/PDF summaries, short local conversation memory, optional web verification, and standard PDF annotations.

## Install the app

1. Open this repository's **Releases** page and download `Anchora-<version>-macos-arm64.zip`.
2. Unzip it, then drag `Anchora.app` to `/Applications`.
3. On the first launch, macOS may show an unidentified-developer warning because this build is locally signed, not notarized. Control-click `Anchora.app`, choose **Open**, then confirm once.
4. Open a PDF, show the AI pane, click `•••` → **Set OpenAI API Key…**, and enter your own OpenAI Platform API key.

The key is stored only in your macOS Keychain. It is never saved inside a PDF or committed to this repository.

> ChatGPT Plus and an OpenAI API account are billed separately. Anchora uses your OpenAI Platform API key, so API usage (including Web verify) is charged to that API account.

### System requirement

The published binary is built for Apple Silicon Macs (`arm64`). Intel support requires a separately built universal/Intel release.

## Use it

- Select text and ask a question in the AI pane.
- `Option` + drag: OCR a PDF area.
- `Command` + `Option` + drag: send an image region.
- `Web verify`: search and check current claims, then show the web sources used.
- `Pin latest answer`: add the latest AI answer as an editable anchor note in the PDF.
- `•••`: summarize the current page or the complete PDF.

## Build from source

Requirements: current Xcode and macOS.

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

After pushing the source changes, create a GitHub Release and attach the prepared `Anchora-<version>-macos-arm64.zip` asset from the local `Distribution` folder. The folder is intentionally ignored by Git so app bundles do not bloat the source repository.

Current release asset checksum:

```text
Anchora-1.0.0-macos-arm64.zip
SHA-256: d8ef7f02be9cb2fd48c74f071a819b4dc4bf60954d66517f20a072e2ef509cb4
```

## License and attribution

Anchora is a modified build of [Skim](https://skim-app.sourceforge.io/) and retains Skim's BSD 3-Clause license. See [LICENSE](LICENSE).
