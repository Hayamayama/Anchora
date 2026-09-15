# PDFBuddy / Skim technical reconnaissance

## Baseline

- Source: `scris/skim-pdf`, a public mirror of Skim's SourceForge repository.
- Checked-out commit: `6cdd41f` (`Don't use year range in copyright notice...`).
- Environment: Xcode 26.6 (build 17F113), macOS SDK 26.5, Apple Silicon.
- Baseline build: **passed** with `xcodebuild -project Skim.xcodeproj -scheme Skim -configuration Debug ... CODE_SIGNING_ALLOWED=NO`.

The build's output application is intentionally outside the repository, at
`/private/tmp/pdfbuddy-skim-derived/Build/Products/Debug/Skim.app`.

## Code map

| Concern | Primary code | Notes |
| --- | --- | --- |
| Document model / lifecycle | `SKMainDocument.m` | Owns the loaded `SKPDFDocument`, original PDF bytes, save/export policy, and Skim note sidecar/xattr loading. |
| PDF document wrapper | `SKPDFDocument.{h,m}`, `PDFDocument_SKExtensions.m` | Wraps PDFKit and provides annotation add/remove/move notifications. |
| Main PDF interaction | `SKPDFView.{h,m}` | Text selection, mouse handling, annotation creation, undo integration. |
| Highlight / sticky-note factory | `SKPDFView.m` (`addAnnotationWithType:selection:page:bounds:`) | Uses `PDFAnnotationMarkup` for markup and `SKNPDFAnnotationNote` for anchored notes. |
| Annotation extensions / serialization | `PDFAnnotation*_SKExtensions.m` | Defines Skim's in-memory annotation helpers and FDF export representation. |
| Existing right pane | `SKMainWindowController.{h,m}`, `SKMainWindowController_Actions.m`, `SKRightSideViewController.m` | A three-pane split view; the right pane is the best initial host for a compact AI/Notes surface. |
| Toolbar | `SKMainToolbarController.m` | Keep existing tools initially; hide rather than delete in a later UI pass. |
| Private note storage | `SKMainDocument.m`, `SkimNotes/NSFileManager_SKNExtensions.m` | Reads/writes Skim-specific extended attributes and optional `.skim` backup files. |

## Annotation creation path

1. A toolbar/menu command calls `createNewNote:` in `SKMainWindowController_Actions.m`.
2. That calls `-[SKPDFView addAnnotationWithType:]`.
3. `-[SKPDFView addAnnotationWithType:selection:page:bounds:]` maps the chosen tool to a PDF subtype, constructs an annotation, assigns the selected text to `string` / contents, registers the author, and calls `[[self document] addAnnotation:toPage:]`.
4. `-[PDFDocument(SKExtensions) addAnnotation:toPage:]` calls PDFKit's `-[PDFPage addAnnotation:]` and emits Skim's change notification.

For selected text, highlights are built through `+[PDFAnnotation SkimNotesAndPagesWithSelection:forType:]`; this produces page-aware markup annotations and retains their quadrilateral geometry.

## The critical persistence finding

Skim does **not** embed newly created annotations into the PDF during its ordinary Save flow.

- `SKMainDocument` keeps the original bytes in `pdfData`.
- Its normal PDF save branch writes those original bytes back to disk (`[pdfData writeToURL:...]`).
- It then calls `attachNotesAtURL:`, which writes Skim annotation dictionaries, text notes, and rich-text notes to macOS extended attributes. An optional `.skim` backup may also be written.
- Only the explicit **Export with Embedded Notes** path takes `[[self pdfDocument] writeToURL:]`, which asks PDFKit to serialize annotations into the PDF.

This means the proposed product cannot merely adjust the note factory: it must change the normal native-PDF save policy to serialize `pdfDocument`, and must stop treating extended attributes / `.skim` as the primary persistence store.

## Minimum safe MVP change set

1. Add a `PDFBuddyStandardAnnotationWriter` helper, scoped only to Highlight and Text annotations.
   - Use Skim's existing `PDFAnnotationMarkup` and `PDFAnnotationText` classes (the generic `PDFAnnotation(bounds:forType:...)` constructor did not serialize newly-created markup/text objects correctly in this Xcode 26.6 smoke test). Their serialized output is still standard `/Highlight`, `/Text`, and `/Popup` PDF annotation objects.
   - Highlight: preserve text-selection `quadrilateralPoints`, write AI response to `contents`, use `userName = "PDFBuddy AI"` and (optionally) `subject = "Explanation"` where supported.
   - Sticky note: write note to `contents`, author `PDFBuddy` or `PDFBuddy AI`.
2. Route `SKPDFView`'s Highlight and anchored-note actions through that helper. Retain the existing geometry and undo calls.
3. In the native PDF branch of `-[SKMainDocument writeToURL:ofType:error:]`, always call `[[self pdfDocument] writeToURL:absoluteURL]` for PDFBuddy-managed editable PDFs. Do not gate it behind `SKExportOptionWithEmbeddedNotes`. **Implemented.**
4. In `writeSafelyToURL:...`, do not call `attachNotesAtURL:` for normal PDFBuddy saves. After a successful standard-PDF save, remove legacy Skim note xattrs so reopening cannot duplicate imported notes. Legacy xattrs are still readable for migration. **Implemented.**
5. Add a regression check that saves, reopens through PDFKit, and validates `/Subtype`, `/Contents`, author, and highlight quadrilateral points. Then manually open the fixture in Preview and Acrobat/PDF Expert before claiming cross-reader support.

## Dummy AI end-to-end insertion point

The first UI proof should be deliberately small:

1. Obtain `[pdfView currentSelection]`.
2. Build the standard highlight annotation from that selection.
3. Assign `contents = @"Hello world — AI explanation attached to this highlight."`.
4. Add it via `[[pdfView document] addAnnotation:toPage:]`.
5. Call the normal Save command, now backed by PDFKit document serialization.

This keeps the first milestone independent of a network provider or AI sidebar. Once the saved fixture is readable in Preview, replace only the fixed `contents` value with a provider response.

### Implemented prototype action

The Notes menu now contains **Pin Demo AI Explanation** (`⌘⇧P`). It takes the current text selection, uses Skim's existing highlight workflow, then replaces the new highlight's annotation `Contents` / author with a provider-free `Hello world` response from `PDFBuddy AI`. Combined with the embedded-save change above, this is the first in-app selection → AI-shaped text → standard-PDF path.

## Current automated smoke test

`Tools/StandardAnnotationSmokeTest.swift` is a framework-level persistence proof. It creates a small PDF, adds a standard `/Highlight` annotation with `Contents` and quadrilateral points plus a standard `/Text` sticky note, saves with PDFKit, reopens it, and asserts that both annotations and their contents remain. PDFKit adds a standard `/Popup` child for the Text annotation, so the reopened document contains three objects.

It proves the target PDFKit serialization contract, but it does **not** yet prove Preview/Acrobat visual rendering or wire the behaviour into Skim's UI. Those are the next two validation layers.
