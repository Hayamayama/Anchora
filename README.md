# Anchora

Anchora is a macOS reading companion built on Skim: read a PDF on the left, ask an AI assistant on the right, and get the feedback loop studying actually needs — Recall and Quiz turn a page you just read into a real signal about whether it worked, and a Study map plans the whole document instead of summarizing it.

**[hayamayama.github.io/Anchora](https://hayamayama.github.io/Anchora/)** is the install page — a plain-language walkthrough for anyone who isn't going to read the rest of this file. This README stays technical: build instructions, release process, and what's under the hood.

## Install the app

Every release from `v1.9.0` onward is **signed with a Developer ID and notarized by Apple** — download it, unzip it, drag `Anchora.app` to `/Applications`, and open it. No warning, no workaround.

Grab the latest build from the **[Releases page](https://github.com/Hayamayama/Anchora/releases/latest)**. If a particular build somehow still gets flagged as unverified — a release published without notarization, or a stapled ticket that didn't survive some transfer — open **System Settings → Privacy & Security** and click **Open Anyway** next to the message about Anchora; that shouldn't normally be necessary.

Then open a PDF, show the AI pane, click `•••` → **Set OpenAI API Key…**, and
enter your own OpenAI Platform API key.

The key is stored only in your macOS Keychain. It is never saved inside a PDF or committed to this repository.

> ChatGPT Plus and an OpenAI API account are billed separately. Anchora uses your OpenAI Platform API key, so API usage (including Web verify) is charged to that API account.

### System requirements

- **macOS 14.0 or later.**
- **Apple Silicon (`arm64`).** Intel support requires a separately built universal/Intel release.

## Use it

- Select text, `Option`-drag to OCR a region, or `Command`-`Option`-drag to send an image region — the AI pane answers with citations back to the page.
- **Recall**: write one sentence from memory in the ask bar, then press it. You get told exactly what was right, wrong, and missed — a diff against the page, not a summary.
- **Quiz**: two or three questions on the page you just read, no answers or hints included. Type your answers in the ask bar and send them for marking.
- **Review queue**: every Recall and Quiz correction comes back later on a schedule (a day, then three, then a week, then longer) in the sidebar's `Review` tab, across every open document.
- **Study map** / **Paper map**: a plan for the whole document — what order, what to focus on, what to skip — or an evidence-first breakdown of a paper (Scientific profile). Each ends in a self-test section whose questions can be checked off; the checklist survives rebuilding the map.
- `Web verify`: search and check current claims, then show the web sources used.
- `Pin latest answer`, or under any answer `Pin as note` / `Pin as text`: write an AI answer back into the PDF as an ordinary, editable annotation. Older answers keep their own anchor, so a question asked three turns ago can still be pinned where it belongs.
- **Photos into the page**: right-click → **Import from iPhone or iPad** (Continuity Camera) or **Insert Picture…**, or paste / drag a picture in. It lands as a movable, resizable note on the page.
- **Thought inbox**: `⌘⇧J` from anywhere in the app catches a stray thought in one line without leaving the page you're reading; the sidebar's `Inbox` tab manages it.
- `•••`: summarize the current page or the complete PDF, switch response language, or change the AI model.

## Build from source

Requirements: current Xcode, and macOS 14.0 or later (the deployment target).

```sh
xcodebuild -project Skim.xcodeproj -scheme Skim -configuration Release \
  -derivedDataPath /private/tmp/anchora-derived \
  build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- MACOSX_DEPLOYMENT_TARGET=14.0
```

The `MACOSX_DEPLOYMENT_TARGET` override is there on purpose: Skim's own target
already sets 14.0, but a few third-party projects vendored in (Sparkle,
SkimNotes, SkimTransitions, SkimImporter) still carry their own upstream
10.13, and current Xcode/SDK releases refuse to build anything below 12.0 at
all. The override reaches every target in the build, sub-projects included,
without editing files this repository doesn't own.

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
hand (or with `gh release create`) rather than committing it. Verify the
attached asset is the one you just built — a release page can exist before
its attachment does, and replacing an asset later needs a manual check that
the two actually match.

### Signing it properly

With an Apple Developer Program membership the same command produces a build
that opens with no warning and needs none of the install steps above:

```sh
xcrun notarytool store-credentials AnchoraNotary \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD

ANCHORA_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ANCHORA_NOTARY_PROFILE=AnchoraNotary \
  Tools/package-release.sh
```

The script signs every embedded Mach-O individually (not just the four
bundle types that happen to be their own directories — a loose tool or a
framework's secondary binary needs its own signature too), applies the
hardened runtime and a secure timestamp, submits the archive to Apple,
staples the ticket to the app, and rebuilds the archive so the ticket
travels with it. To check on a submission afterward:

```sh
xcrun notarytool history --keychain-profile AnchoraNotary
xcrun notarytool log <submission-id> --keychain-profile AnchoraNotary
```

This path is exercised as of `v1.9.0` — `spctl -a -vv` on that release's
downloaded, quarantined `.app` reports `accepted, source=Notarized Developer
ID`. A first submission from a brand-new Developer ID can take an hour or
more while Apple establishes trust for that Team ID; later ones are faster.

Each release's exact checksum is on its own [Releases page](https://github.com/Hayamayama/Anchora/releases) entry rather than duplicated here, where it would only ever describe one past version.

## Run the tests

Anchora's own logic — the paper map parser, prompts, settings, and the chat
transcript model — is Swift with no AppKit or Skim dependency, so it can be
exercised without building the app:

```sh
Tools/run-anchora-tests.sh
```

## License and attribution

Anchora is a modified build of [Skim](https://skim-app.sourceforge.io/) and retains Skim's BSD 3-Clause license. See [LICENSE](LICENSE).
