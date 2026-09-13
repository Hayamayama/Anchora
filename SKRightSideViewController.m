//
//  SKRightSideViewController.m
//  Skim
//
//  Created by Christiaan Hofman on 3/28/10.
/*
 This software is Copyright (c) 2010
 Christiaan Hofman. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

 - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

 - Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

 - Neither the name of Christiaan Hofman nor the names of any
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SKRightSideViewController.h"
#import "SKMainWindowController.h"
#import "SKMainWindowController_Actions.h"
#import "SKMainWindowController_UI.h"
#import "NSMenu_SKExtensions.h"
#import "NSSegmentedControl_SKExtensions.h"
#import "SKTypeSelectHelper.h"
#import "SKNoteOutlineView.h"
#import "SKTableView.h"
#import "NSColor_SKExtensions.h"
#import <SkimNotes/SkimNotes.h>
#import "PDFAnnotation_SKExtensions.h"
#import "SKSnapshotWindowController.h"
#import "NSURL_SKExtensions.h"
#import "PDFPage_SKExtensions.h"
#import "PDFSelection_SKExtensions.h"
#import "NSString_SKExtensions.h"
#import "SKPDFView.h"
#import "SKTopBarView.h"
#import <Vision/Vision.h>
#import "Anchora-Swift.h"

static NSString * const SKAIAssistantName = @"Anchora";
// The earlier 2,400-token ceiling was a temporary guard while the streaming
// UI was being stabilized.  A paper map needs room for methods, results,
// figures, caveats, and page citations; its renderer is now throttled.
static const NSUInteger SKAIStandardMaximumOutputTokens = 8000;
static const NSUInteger SKAIMapMaximumOutputTokens = 16000;

@interface SKRightSideViewController ()
@property (nonatomic, nullable, strong) AnchoraHeaderModel *aiHeaderModel;
@property (nonatomic, nullable, strong) NSView *aiHeaderView;
@property (nonatomic, nullable, strong) AnchoraComposerModel *aiComposerModel;
// The ask bar grows with what is typed into it.
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiComposerHeightConstraint;
// The transcript and the Paper Map navigator are SwiftUI.  AppKit owns only
// their position and height in the sidebar; everything inside — wrapped text
// height, bubble growth, scrolling, link handling — belongs to the framework.
@property (nonatomic, nullable, strong) AnchoraChatModel *aiChatModel;
@property (nonatomic, nullable, strong) AnchoraMapModel *aiMapModel;
@property (nonatomic, nullable, strong) AnchoraInboxModel *aiInboxModel;
// Which of the sidebar's three faces is showing.  The transcript, the map and
// the inbox take turns in one area rather than competing for it.
@property (nonatomic, nullable, strong) AnchoraPaneModel *aiPaneModel;
@property (nonatomic, nullable, strong) NSView *aiPaneView;
// The reader's live selection, and the snapshot the in-flight answer was
// asked about.  Keeping these as two values rather than sixteen parallel
// properties is what stops the two from being confused.
@property (nonatomic, nullable, strong) AnchoraSelection *aiSelection;
@property (nonatomic, nullable, strong) AnchoraTurn *aiTurn;
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiTopConstraint;
// The whole OpenAI turn -- request body, streaming, delta batching, error
// mapping -- lives in the Swift core.  Non-nil only while a turn is live.
@property (nonatomic, nullable, strong) AnchoraResponsesClient *aiClient;
@property (nonatomic, nullable, strong) NSPopover *selectionActionPopover;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSString *> *> *aiConversation;
@property (nonatomic) BOOL webVerificationEnabled;
// Set just before a whole-document request starts and consumed as its turn is
// built.  A map is always a whole-document answer, so this never has to
// survive longer than that one call.
@property (nonatomic) AnchoraMapKind aiPendingMapKind;
// Set while a quiz is waiting to be answered.  The page is held with it
// because the reader can scroll away between the questions and the answers,
// and the marking has to see the page the questions came from.
@property (nonatomic) BOOL aiQuizPending;
@property (nonatomic, nullable, strong) PDFPage *aiQuizPage;
@end

@implementation SKRightSideViewController

@synthesize noteArrayController, noteOutlineView, snapshotArrayController, snapshotTableView, aiView;

- (NSString *)sourceLabelForPageIndexes:(NSArray<NSNumber *> *)pageIndexes {
    if ([pageIndexes count] == 0)
        return nil;
    NSArray<NSString *> *pageLabels = [self pdfPageLabels];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSNumber *number in pageIndexes) {
        NSUInteger index = [number unsignedIntegerValue];
        NSString *label = index < [pageLabels count] ? [pageLabels objectAtIndex:index] : @"";
        if ([label length] == 0)
            label = [NSString stringWithFormat:@"%lu", (unsigned long)index + 1];
        if ([labels containsObject:label] == NO)
            [labels addObject:label];
    }
    if ([labels count] == 0)
        return nil;
    return [NSString stringWithFormat:@"p. %@", [labels componentsJoinedByString:@", "]];
}

- (void)goToPDFPageAtIndex:(NSInteger)pageIndex {
    PDFDocument *document = [mainController pdfDocument];
    PDFPage *page = (pageIndex >= 0 && (NSUInteger)pageIndex < [document pageCount]) ? [document pageAtIndex:(NSUInteger)pageIndex] : nil;
    if (page)
        [[mainController pdfView] goToPage:page];
    else
        NSBeep();
}

- (void)selectPaperMapQuote:(NSString *)quote onPageAtIndex:(NSInteger)pageIndex {
    PDFDocument *document = [mainController pdfDocument];
    PDFPage *page = (pageIndex >= 0 && (NSUInteger)pageIndex < [document pageCount]) ? [document pageAtIndex:(NSUInteger)pageIndex] : nil;
    PDFSelection *selection = [self paperMapSelectionForQuote:quote onPage:page];
    SKPDFView *pdfView = [mainController pdfView];
    if ([selection hasCharacters]) {
        [pdfView goToSelection:selection];
        [pdfView setCurrentSelection:selection animate:YES];
    } else if (page) {
        // The PDF text layer may not match a quote the model read from the
        // page image.  Land on the right page rather than fake a highlight.
        [pdfView goToPage:page];
        NSBeep();
    }
}

/// Where the reader is, for a note that wants to record it.
- (NSString *)currentDocumentTitle {
    NSString *displayName = [(NSDocument *)[mainController document] displayName];
    return [displayName length] ? displayName : @"";
}

- (NSInteger)currentPageNumber {
    PDFPage *page = [[mainController pdfView] currentPage];
    return page ? (NSInteger)[page pageIndex] + 1 : 0;
}

/// The key a saved map is filed under.  Empty for a document that has never
/// been saved to disk, which is also the case where there is nothing stable to
/// file it against.
- (NSString *)currentDocumentPath {
    NSURL *fileURL = [(NSDocument *)[mainController document] fileURL];
    return [fileURL isFileURL] ? [fileURL path] : @"";
}

/// Whichever document sidebar the reader last worked in answers ⌘⇧J's
/// question about where they are.
- (void)claimQuickCaptureSource {
    __weak SKRightSideViewController *weakSelf = self;
    AnchoraQuickCapture *capture = [AnchoraQuickCapture shared];
    [capture setSourceTitleProvider:^NSString *{
        return [weakSelf currentDocumentTitle];
    }];
    [capture setSourcePageProvider:^NSInteger{
        return [weakSelf currentPageNumber];
    }];
}

- (NSArray<NSString *> *)pdfPageLabels {
    PDFDocument *document = [mainController pdfDocument];
    NSUInteger pageCount = [document pageCount];
    NSMutableArray<NSString *> *labels = [NSMutableArray arrayWithCapacity:pageCount];
    for (NSUInteger index = 0; index < pageCount; index++)
        [labels addObject:[[document pageAtIndex:index] label] ?: @""];
    return labels;
}

- (PDFSelection *)paperMapSelectionForQuote:(NSString *)quote onPage:(PDFPage *)page {
    NSString *pageText = [page string];
    if ([quote length] == 0 || [pageText length] == 0)
        return nil;
    NSRange range = [pageText rangeOfString:quote options:NSCaseInsensitiveSearch];
    if (range.location == NSNotFound) {
        // The PDF text layer may insert line breaks differently from a quote
        // returned from vision/PDF input. A distinctive opening fragment is
        // still preferable to jumping to an unhighlighted whole page.
        NSArray<NSString *> *words = [quote componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSMutableArray<NSString *> *nonEmptyWords = [NSMutableArray array];
        for (NSString *word in words) {
            if ([word length])
                [nonEmptyWords addObject:word];
            if ([nonEmptyWords count] == 9)
                break;
        }
        if ([nonEmptyWords count] >= 4) {
            NSString *fragment = [nonEmptyWords componentsJoinedByString:@" "];
            range = [pageText rangeOfString:fragment options:NSCaseInsensitiveSearch];
        }
    }
    return range.location == NSNotFound ? nil : [page selectionForRange:range];
}

- (void)clearPaperMap {
    [self.aiMapModel clear];
    [self.aiPaneModel leaveTabIfShowing:AnchoraPaneTabMap];
}

/// A map costs a whole-PDF upload, so it is kept: reopening the document
/// brings back the one that was built for it rather than asking for it again.
- (void)restoreSavedMap {
    NSString *path = [self currentDocumentPath];
    AnchoraSavedMap *saved = [path length] ? [[AnchoraStore shared] latestMapWithDocumentPath:path] : nil;
    if (saved == nil)
        return;
    [self presentMapFromResponse:[saved response] kind:(AnchoraMapKind)[saved kindRawValue] select:NO];
}

- (void)presentMapFromResponse:(NSString *)response kind:(AnchoraMapKind)kind select:(BOOL)select {
    NSArray<NSString *> *pageLabels = [self pdfPageLabels];
    NSArray<AnchoraMapSection *> *sections = kind == AnchoraMapKindStudy
        ? [AnchoraStudyMap sectionsFromResponse:response ?: @"" pageLabels:pageLabels]
        : [AnchoraPaperMap sectionsFromResponse:response ?: @"" pageLabels:pageLabels];
    if ([sections count] == 0)
        return;
    [self.aiMapModel present:sections kind:kind];
    // A map the reader just asked for is what they want to look at.  One
    // restored on open is not: it waits behind its tab.
    if (select)
        [self.aiPaneModel showMap];
}

- (void)appendChatMessageFrom:(NSString *)sender text:(NSString *)text sourcePageIndexes:(NSArray<NSNumber *> *)sourcePageIndexes {
    void (^appendMessage)(void) = ^{
        AnchoraChatModel *model = self.aiChatModel;
        if (model == nil)
            return;
        if ([sender isEqualToString:@"You"]) {
            [model appendUserMessage:text ?: @""];
        } else if ([sender isEqualToString:@"Web sources"]) {
            [model appendWebSourcesMessage:text ?: @""];
        } else if (text == nil) {
            // A streaming turn must have a visible destination before the
            // request starts, showing its phase until output arrives.
            [model beginStreamingMessageWithStatus:[self.aiTurn status] ?: @"Preparing request…"
                                       sourceLabel:[self sourceLabelForPageIndexes:sourcePageIndexes]
                                   sourcePageIndex:[sourcePageIndexes firstObject]
                                              turn:self.aiTurn];
        } else {
            [model appendAssistantMessage:text];
        }
    };
    // Requests are initiated on the main thread.  Creating the streaming
    // bubble synchronously keeps it ahead of the first delta.
    if ([NSThread isMainThread])
        appendMessage();
    else
        dispatch_async(dispatch_get_main_queue(), appendMessage);
}

- (void)appendChatMessageFrom:(NSString *)sender text:(NSString *)text {
    [self appendChatMessageFrom:sender text:text sourcePageIndexes:nil];
}

- (void)updateAIRequestStatus:(NSString *)status {
    void (^updateStatus)(void) = ^{
        [self.aiTurn setStatus:status];
        [self.aiChatModel updateStreamingStatus:status ?: @""];
    };
    if ([NSThread isMainThread])
        updateStatus();
    else
        dispatch_async(dispatch_get_main_queue(), updateStatus);
}

- (void)cancelCurrentAIRequest {
    // -cancel reports back through onFinish, so the UI reset lives in one
    // place rather than being duplicated here.
    [self.aiClient cancel];
}

- (BOOL)isScientificReadingProfile {
    return [[AnchoraSettings sharedSettings] isScientific];
}

- (BOOL)usesTraditionalChineseResponses {
    return [[AnchoraSettings sharedSettings] usesTraditionalChinese];
}

- (NSString *)selectedAIModel {
    return [[AnchoraSettings sharedSettings] modelIdentifier];
}

- (IBAction)changeAIModel:(id)sender {
    NSString *model = [(NSMenuItem *)sender representedObject];
    if ([model length] == 0 || [model isEqualToString:[self selectedAIModel]])
        return;
    [[AnchoraSettings sharedSettings] setModelIdentifier:model];
    [self appendChatMessageFrom:SKAIAssistantName text:[NSString stringWithFormat:@"Model changed to %@. It will be used for your next request.", model]];
}

- (NSString *)welcomeMessageForCurrentReadingProfile {
    return [AnchoraPrompts welcomeMessageWithProfile:[[AnchoraSettings sharedSettings] readingProfile]];
}

- (void)queueWelcomeMessage {
    [self appendChatMessageFrom:SKAIAssistantName text:[self welcomeMessageForCurrentReadingProfile]];
}

- (IBAction)changeAIResponseLanguage:(id)sender {
    [[AnchoraSettings sharedSettings] setResponseLanguage:[sender tag] == AnchoraResponseLanguageEnglish ? AnchoraResponseLanguageEnglish : AnchoraResponseLanguageTraditionalChinese];
}

- (void)updateAIReadingProfileInterface {
    AnchoraReadingProfile profile = [[AnchoraSettings sharedSettings] readingProfile];
    BOOL scientific = profile == AnchoraReadingProfileScientific;
    [self.aiHeaderModel setProfileWithScientific:scientific
                                           title:scientific ? @"Anchora Scientific" : @"Anchora AI"
                                        subtitle:scientific ? @"Trace the evidence behind a paper" : @"Ask about what you are reading"
                                    contextTitle:scientific ? @"PAPER CONTEXT" : @"CONTEXT"];
    self.aiQuizPending = NO;
    self.aiQuizPage = nil;
    [self.aiComposerModel setPlaceholderText:[AnchoraPrompts composerPlaceholderWithProfile:profile]];
    [self.aiComposerModel setQuickActionTitles:[AnchoraPrompts quickActionTitlesWithProfile:profile]
                                      tooltips:[AnchoraPrompts quickActionTooltipsWithProfile:profile]];
    if ([self.aiSelection hasContext] == NO && [self.aiSelection isRecognizingText] == NO)
        [self.aiHeaderModel setContextText:[AnchoraPrompts emptyContextMessageWithProfile:profile] expandable:NO];
}

- (void)changeAIReadingProfileToScientific:(BOOL)scientific {
    [[AnchoraSettings sharedSettings] setReadingProfile:scientific ? AnchoraReadingProfileScientific : AnchoraReadingProfileStudy];
    [self updateAIReadingProfileInterface];
}

- (void)showAIMoreActionsFromHeader {
    // The menu is still built here because it counts the document's notes and
    // shows their colours.  Anchor it to the header's top-right corner.
    NSView *header = self.aiHeaderView;
    if (header == nil)
        return;
    [self showAIMoreActions:header];
}

- (void)buildAIInterface {
    NSVisualEffectView *rootView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [rootView setMaterial:NSVisualEffectMaterialSidebar];
    [rootView setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [rootView setState:NSVisualEffectStateFollowsWindowActiveState];
    [rootView setTranslatesAutoresizingMaskIntoConstraints:NO];

    AnchoraHeaderModel *headerModel = [[AnchoraHeaderModel alloc] init];
    NSView *header = [AnchoraHosting headerViewWithModel:headerModel];
    [rootView addSubview:header];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:12.0],
        [header.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-12.0],
        [header.heightAnchor constraintEqualToConstant:[AnchoraHosting headerHeight]]
    ]];
    self.aiTopConstraint = [header.topAnchor constraintEqualToAnchor:rootView.topAnchor constant:12.0];
    self.aiTopConstraint.active = YES;

    // The transcript, the map navigator and the thought inbox are one hosting
    // view with a tab strip.  A map used to be a card above the chat whose
    // height this controller recalculated by hand; giving the three faces the
    // same area removes that arithmetic and gives a study plan room to be read
    // in.
    AnchoraMapModel *mapModel = [[AnchoraMapModel alloc] init];
    AnchoraChatModel *chatModel = [[AnchoraChatModel alloc] init];
    AnchoraInboxModel *inboxModel = [[AnchoraInboxModel alloc] init];
    AnchoraPaneModel *paneModel = [[AnchoraPaneModel alloc] init];
    NSView *paneView = [AnchoraHosting paneViewWithPane:paneModel
                                                   chat:chatModel
                                                    map:mapModel
                                                  inbox:inboxModel
                                             pageLabels:[self pdfPageLabels]];
    [rootView addSubview:paneView];

    // Quick actions and the ask bar are one SwiftUI view.  Building the quick
    // action row from NSStackView arranged subviews is what used to make
    // AppKit measure it recursively while a PDF was opening.
    AnchoraComposerModel *composerModel = [[AnchoraComposerModel alloc] init];
    NSView *composer = [AnchoraHosting composerViewWithModel:composerModel];
    [rootView addSubview:composer positioned:NSWindowAbove relativeTo:paneView];

    [NSLayoutConstraint activateConstraints:@[
        [paneView.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:8.0],
        [paneView.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-8.0],
        [paneView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:6.0],
        [paneView.bottomAnchor constraintEqualToAnchor:composer.topAnchor constant:-8.0],
        [paneView.heightAnchor constraintGreaterThanOrEqualToConstant:140.0],
        [composer.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:12.0],
        [composer.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-12.0],
        [composer.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor constant:-12.0],
    ]];
    // Still an explicit height rather than an intrinsic one -- the composer is
    // never allowed to measure itself into the sidebar's layout.  The number
    // now comes from the view, which lays the typed text out at the width the
    // sidebar gave it and reports what it needs.  Below required, so a very
    // short sidebar takes it back rather than breaking.
    self.aiComposerHeightConstraint = [composer.heightAnchor constraintEqualToConstant:[AnchoraHosting composerHeight]];
    self.aiComposerHeightConstraint.priority = NSLayoutPriorityDefaultHigh;
    self.aiComposerHeightConstraint.active = YES;

    self.aiView = rootView;
    self.aiMapModel = mapModel;
    self.aiPaneModel = paneModel;
    self.aiPaneView = paneView;
    self.aiInboxModel = inboxModel;
    self.aiHeaderModel = headerModel;
    self.aiHeaderView = header;
    self.aiChatModel = chatModel;
    self.aiComposerModel = composerModel;

    __weak SKRightSideViewController *weakSelf = self;
    [chatModel setOnOpenPage:^(NSInteger pageIndex) {
        [weakSelf goToPDFPageAtIndex:pageIndex];
    }];
    [chatModel setOnCopy:^(NSString *text) {
        [weakSelf copyAnswerText:text];
    }];
    [chatModel setOnPinAnchor:^(AnchoraTurn *turn) {
        [weakSelf pinTurn:turn asTextNote:NO];
    }];
    [chatModel setOnPinTextNote:^(AnchoraTurn *turn) {
        [weakSelf pinTurn:turn asTextNote:YES];
    }];
    [mapModel setOnOpenPage:^(NSInteger pageIndex) {
        [weakSelf goToPDFPageAtIndex:pageIndex];
    }];
    [mapModel setOnOpenQuote:^(NSString *quote, NSInteger pageIndex) {
        [weakSelf selectPaperMapQuote:quote onPageAtIndex:pageIndex];
    }];
    [mapModel setPageLabelProvider:^NSString *(NSInteger pageIndex) {
        NSArray<NSString *> *labels = [weakSelf pdfPageLabels];
        return (pageIndex >= 0 && (NSUInteger)pageIndex < [labels count]) ? [labels objectAtIndex:(NSUInteger)pageIndex] : @"";
    }];
    // A note records where the reader was, and is asked for it only as the
    // note is written -- nothing has to keep pace with scrolling.
    [inboxModel setSourceTitleProvider:^NSString *{
        return [weakSelf currentDocumentTitle];
    }];
    [inboxModel setSourcePageProvider:^NSInteger{
        return [weakSelf currentPageNumber];
    }];
    [composerModel setOnSubmit:^{
        [weakSelf askAI:nil];
    }];
    [composerModel setOnQuickAction:^(NSInteger index) {
        [weakSelf performQuickActionAtIndex:index];
    }];
    [composerModel setOnPin:^{
        [weakSelf pinResponseToPDF:nil];
    }];
    [composerModel setOnClear:^{
        [weakSelf clearAIConversation:nil];
    }];
    [composerModel setOnWebVerifyChanged:^(BOOL enabled) {
        [weakSelf setWebVerificationEnabledFromComposer:enabled];
    }];
    [composerModel setOnHeightChange:^(CGFloat height) {
        weakSelf.aiComposerHeightConstraint.constant = height;
    }];
    [headerModel setOnProfileChange:^(BOOL scientific) {
        [weakSelf changeAIReadingProfileToScientific:scientific];
    }];
    [headerModel setOnMoreActions:^{
        [weakSelf showAIMoreActionsFromHeader];
    }];
    [self updateAIReadingProfileInterface];
    [self queueWelcomeMessage];
}

- (NSPopover *)selectionActionPopover {
    if (_selectionActionPopover == nil) {
        NSStackView *actions = [[NSStackView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 0.0, 0.0)];
        [actions setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
        [actions setSpacing:6.0];
        [actions setEdgeInsets:NSEdgeInsetsMake(7.0, 8.0, 7.0, 8.0)];
        [actions addArrangedSubview:[NSButton buttonWithTitle:@"Highlight" target:self action:@selector(addHighlightFromSelection:)]];
        [actions addArrangedSubview:[NSButton buttonWithTitle:@"Text Note" target:self action:@selector(addTextNoteFromSelection:)]];
        [actions addArrangedSubview:[NSButton buttonWithTitle:@"Ask AI" target:self action:@selector(askAIFromSelection:)]];
        [actions layoutSubtreeIfNeeded];

        NSViewController *controller = [[NSViewController alloc] init];
        [controller setView:actions];
        NSPopover *popover = [[NSPopover alloc] init];
        [popover setBehavior:NSPopoverBehaviorSemitransient];
        [popover setContentViewController:controller];
        _selectionActionPopover = popover;
    }
    return _selectionActionPopover;
}

- (void)showSelectionActionsForSelection:(PDFSelection *)selection {
    if ([selection hasCharacters] == NO) {
        [self.selectionActionPopover close];
        return;
    }
    SKPDFView *pdfView = [mainController pdfView];
    NSRect rect = [pdfView currentSelectionRect];
    if (NSIsEmptyRect(rect) || [[pdfView window] isKeyWindow] == NO)
        return;
    [self.selectionActionPopover showRelativeToRect:rect ofView:pdfView preferredEdge:NSMinYEdge];
}

- (IBAction)addHighlightFromSelection:(id)sender {
    [self.selectionActionPopover close];
    NSButton *noteButton = (NSButton *)sender;
    [noteButton setTag:SKHighlightNote];
    [mainController createNewNote:noteButton];
}

- (IBAction)addTextNoteFromSelection:(id)sender {
    [self.selectionActionPopover close];
    NSButton *noteButton = (NSButton *)sender;
    [noteButton setTag:SKFreeTextNote];
    [mainController createNewNote:noteButton];
}

- (IBAction)askAIFromSelection:(id)sender {
    [self.selectionActionPopover close];
    if ([mainController rightSidePaneIsOpen] == NO)
        [mainController toggleRightSidePane:nil];
    [mainController setRightSidePaneState:SKSidePaneStateAI];
    // The pane has to be on screen before its ask bar can take focus.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.aiComposerModel focusQuestionField];
    });
}

- (void)applySelection:(AnchoraSelection *)selection {
    self.aiSelection = selection;
    [self.aiHeaderModel setContextText:[selection contextDescription] expandable:[selection isContextExpandable]];
}

- (void)updateSelectionContext:(NSNotification *)notification {
    SKPDFView *pdfView = [mainController pdfView];
    if (pdfView == nil || self.aiHeaderModel == nil)
        return;
    [self claimQuickCaptureSource];

    // Option-drag and Command-Option-drag each post their own notification
    // when the drag finishes, and are handled by their own capture path.
    NSString *notificationName = [notification name];
    if ([notificationName isEqualToString:SKPDFViewAISelectionAreaChangedNotification]) {
        [self captureAISelectionArea];
        return;
    }
    if ([notificationName isEqualToString:SKPDFViewAIImageSelectionAreaChangedNotification]) {
        [self captureAIImageSelectionArea];
        return;
    }
    // A rectangle drag also posts the ordinary selection notification on every
    // mouse-move while it tracks.  Waiting for its own final notification stops
    // those from clearing the previous context once per event.
    if (NSIsEmptyRect([pdfView currentSelectionRect]) == NO && [[pdfView currentSelection] hasCharacters] == NO)
        return;

    PDFSelection *selection = [pdfView currentSelection];
    if ([selection hasCharacters] == NO) {
        [self applySelection:[AnchoraSelection emptyWithMessage:[AnchoraPrompts emptyContextMessageWithProfile:[[AnchoraSettings sharedSettings] readingProfile]]
                                                          after:self.aiSelection]];
        [self.selectionActionPopover close];
        return;
    }

    NSString *rawText = [selection string] ?: @"";
    NSString *cleanText = [selection cleanedString] ?: @"";
    if ([AnchoraTextQuality needsRecognitionWithRawText:rawText cleanedText:cleanText textWithoutAliens:[rawText stringByRemovingAliens]]) {
        PDFPage *page = [[selection pages] firstObject];
        [self applySelection:[AnchoraSelection recognizingWithSelection:selection
                                                      hasTextSelection:YES
                                                                  page:page
                                                              pageRect:page ? [selection boundsForPage:page] : NSZeroRect
                                                               message:[AnchoraPrompts recognizingSelectionMessage]
                                                                 after:self.aiSelection]];
        [self recognizeTextForCurrentSelection];
    } else {
        [self applySelection:[AnchoraSelection text:cleanText selection:selection after:self.aiSelection]];
    }
    [self showSelectionActionsForSelection:selection];
}

- (void)captureAISelectionArea {
    SKPDFView *pdfView = [mainController pdfView];
    PDFPage *page = [pdfView currentSelectionPage];
    NSRect pageRect = [pdfView currentSelectionRect];
    if (page == nil || NSIsEmptyRect(pageRect))
        return;
    [self applySelection:[AnchoraSelection recognizingWithSelection:nil
                                                  hasTextSelection:NO
                                                              page:page
                                                          pageRect:pageRect
                                                           message:[AnchoraPrompts recognizingRegionMessage]
                                                             after:self.aiSelection]];
    [self.selectionActionPopover close];
    [self recognizeTextForCurrentSelection];
}

- (void)captureAIImageSelectionArea {
    SKPDFView *pdfView = [mainController pdfView];
    PDFPage *page = [pdfView currentSelectionPage];
    NSRect pageRect = [pdfView currentSelectionRect];
    if (page == nil || NSIsEmptyRect(pageRect))
        return;

    NSString *dataURL = [AnchoraCapture regionImageDataURLWithPage:page box:[pdfView displayBox] rect:pageRect];
    if ([dataURL length] == 0) {
        [self.aiHeaderModel setContextText:[AnchoraPrompts imageCaptureFailureMessage] expandable:NO];
        return;
    }
    [self applySelection:[AnchoraSelection imageWithDataURL:dataURL
                                                      page:page
                                                  pageRect:pageRect
                                                      text:[AnchoraPrompts regionImageContextText]
                                                   message:[AnchoraPrompts imageReadyMessage]
                                                     after:self.aiSelection]];
    [self.selectionActionPopover close];
}

- (void)recognizeTextForCurrentSelection {
    AnchoraSelection *pending = self.aiSelection;
    PDFPage *page = [pending page];
    if (page == nil) {
        [self applySelection:[pending byFinishingRecognitionWithText:nil failureMessage:[AnchoraPrompts recognitionFailureMessage]]];
        return;
    }
    __weak SKRightSideViewController *weakSelf = self;
    [AnchoraCapture recognizeTextWithPage:page
                                      box:[[mainController pdfView] displayBox]
                                     rect:[pending pageRect]
                               completion:^(NSString *text) {
        SKRightSideViewController *strongSelf = weakSelf;
        // The reader may have moved on while Vision was working; a stale
        // result must never replace a newer selection.
        if (strongSelf == nil || [strongSelf.aiSelection generation] != [pending generation])
            return;
        [strongSelf applySelection:[strongSelf.aiSelection byFinishingRecognitionWithText:text
                                                                          failureMessage:[AnchoraPrompts recognitionFailureMessage]]];
    }];
}

- (IBAction)askAI:(id)sender {
    if (self.aiClient) {
        [self cancelCurrentAIRequest];
        return;
    }
    NSString *typed = [[self.aiComposerModel questionText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (self.aiQuizPending) {
        if ([typed length] == 0) {
            NSBeep();
            return;
        }
        // Marking re-attaches the page the questions were asked about, so the
        // answers are checked against the material rather than against the
        // model's memory of its own questions.
        PDFPage *page = self.aiQuizPage ?: [[mainController pdfView] currentPage];
        [self setQuizPending:NO page:nil];
        [self analyzePage:page
                 question:[AnchoraPrompts quizGradingPromptWithAnswers:typed]
          displayQuestion:typed];
        return;
    }
    [self askAIAboutSelectionWithQuestion:[typed length] ? typed : @"Explain this"
                          displayQuestion:[typed length] ? typed : @"Explain this"];
}

/// The shared selection path.  A quick action sends its instructions here with
/// a short display title, so the transcript shows what the reader asked for
/// rather than the paragraph of instructions that went with it.
- (void)askAIAboutSelectionWithQuestion:(NSString *)question displayQuestion:(NSString *)displayQuestion {
    if (self.aiClient) {
        [self cancelCurrentAIRequest];
        return;
    }
    if ([self.aiSelection hasContext] == NO && [self.aiSelection isRecognizingText] == NO)
        [self updateSelectionContext:nil];
    AnchoraSelection *selection = self.aiSelection;

    if ([selection hasContext] == NO && [self.aiConversation count] == 0) {
        NSBeep();
        // Repeating the same hint on every empty Send turns the transcript
        // into noise.
        if ([self.aiChatModel containsText:[AnchoraPrompts selectionHint]] == NO)
            [self appendChatMessageFrom:SKAIAssistantName text:[AnchoraPrompts selectionHint]];
        [self.aiComposerModel setPinEnabled:NO];
        return;
    }
    if ([selection isRecognizingText]) {
        NSBeep();
        [self appendChatMessageFrom:SKAIAssistantName text:[AnchoraPrompts recognitionInProgressHint]];
        return;
    }

    [self startAIRequestWithQuestion:question
                          sourceText:[selection text]
                        imageDataURL:[selection imageDataURL]
                         fileDataURL:nil
                            fileName:nil
                           selection:[selection selection]
                                page:[selection page]
                            pageRect:[selection pageRect]
                     displayQuestion:displayQuestion];
}

- (void)performQuickActionAtIndex:(NSInteger)index {
    [self performAnchoraQuickAction:[AnchoraPrompts rowActionWithProfile:[[AnchoraSettings sharedSettings] readingProfile]
                                                                   index:index]];
}

/// The ``•••`` entries carry their action in the menu item's tag, so an action
/// means the same thing wherever it is offered.
- (IBAction)performAnchoraMenuAction:(id)sender {
    [self performAnchoraQuickAction:(AnchoraQuickAction)[(NSMenuItem *)sender tag]];
}

- (void)performAnchoraQuickAction:(AnchoraQuickAction)action {
    if (self.aiClient) {
        [self cancelCurrentAIRequest];
        return;
    }
    NSString *question = [AnchoraPrompts promptForAction:action];
    NSString *displayQuestion = [AnchoraPrompts displayTitleForAction:action];

    switch ([AnchoraPrompts scopeForAction:action]) {
        case AnchoraActionScopeDocument:
            [self startWholeDocumentRequestWithQuestion:question
                                        displayQuestion:displayQuestion
                                                mapKind:[AnchoraPrompts mapKindForAction:action]];
            return;
        case AnchoraActionScopePage:
            [self performPageAction:action];
            return;
        case AnchoraActionScopeSelection:
            break;
    }

    // A study action explains what the reader picked out, and says so when
    // nothing is picked.  The scientific questions stay answerable from the
    // whole paper, which is how a reader asks them before selecting anything.
    if ([self isScientificReadingProfile] == NO) {
        [self askAIAboutSelectionWithQuestion:question displayQuestion:displayQuestion];
        return;
    }
    if ([self.aiSelection hasContext] == NO)
        [self updateSelectionContext:nil];
    if ([self.aiSelection hasContext]) {
        [self askAIAboutSelectionWithQuestion:question displayQuestion:displayQuestion];
    } else if (action == AnchoraQuickActionFigure) {
        [self analyzeCurrentPageWithQuestion:question displayQuestion:@"Analyze current page figure"];
    } else {
        [self startWholeDocumentRequestWithQuestion:question displayQuestion:displayQuestion];
    }
}

/// Recall and Quiz both act on the page in front of the reader rather than on
/// a selection: they are asked once a page has been read, not about a phrase
/// inside it.
- (void)performPageAction:(AnchoraQuickAction)action {
    PDFPage *page = [[mainController pdfView] currentPage];
    if (page == nil) {
        NSBeep();
        return;
    }
    if (action == AnchoraQuickActionRecall) {
        NSString *summary = [[self.aiComposerModel questionText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([summary length] == 0) {
            NSBeep();
            if ([self.aiChatModel containsText:[AnchoraPrompts recallNeedsSummaryMessage]] == NO)
                [self appendChatMessageFrom:SKAIAssistantName text:[AnchoraPrompts recallNeedsSummaryMessage]];
            [self.aiComposerModel focusQuestionField];
            return;
        }
        // The transcript keeps what the reader claimed with the correction
        // under it; that pairing is the feedback, so the display question is
        // the reader's own sentence rather than a label.
        [self analyzePage:page
                 question:[AnchoraPrompts recallPromptWithSummary:summary]
          displayQuestion:summary];
        return;
    }

    if ([self analyzePage:page
                 question:[AnchoraPrompts quizPrompt]
          displayQuestion:[AnchoraPrompts quizDisplayTitleWithPageNumber:[page pageIndex] + 1]])
        [self setQuizPending:YES page:page];
}

/// While a quiz is pending the ask bar says what it now wants.  A mode with no
/// visible sign of being on is a mode that swallows the next question.
- (void)setQuizPending:(BOOL)pending page:(PDFPage *)page {
    self.aiQuizPending = pending;
    self.aiQuizPage = pending ? page : nil;
    [self.aiComposerModel setPlaceholderText:pending
        ? [AnchoraPrompts quizAnswerPlaceholder]
        : [AnchoraPrompts composerPlaceholderWithProfile:[[AnchoraSettings sharedSettings] readingProfile]]];
}

- (void)setWebVerificationEnabledFromComposer:(BOOL)enabled {
    self.webVerificationEnabled = enabled;
}

- (void)showNotesDashboardWithPredicate:(NSPredicate *)predicate label:(NSString *)label {
    [mainController setRightSidePaneState:SKSidePaneStateNote];
    [searchField setStringValue:@""];
    [searchField setPlaceholderString:[NSString stringWithFormat:@"Search %@", label ?: @"notes"]];
    [noteArrayController setFilterPredicate:predicate];
    [noteArrayController rearrangeObjects];
    [noteOutlineView reloadData];
}

- (IBAction)showAIInbox:(id)sender {
    [self.aiInboxModel reload];
    [self.aiPaneModel showInbox];
    [self.aiInboxModel focusDraftField];
}

- (IBAction)captureThought:(id)sender {
    [self claimQuickCaptureSource];
    [[AnchoraQuickCapture shared] show];
}

- (IBAction)showAllNotesDashboard:(id)sender {
    [self showNotesDashboardWithPredicate:nil label:@"all notes"];
}

- (IBAction)showAINotesDashboard:(id)sender {
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PDFAnnotation *annotation, NSDictionary *bindings) {
        return [[annotation userName] isEqualToString:SKAIAssistantName];
    }];
    [self showNotesDashboardWithPredicate:predicate label:@"AI answers"];
}

- (IBAction)showTextNotesDashboard:(id)sender {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"type == %@", SKNFreeTextString];
    [self showNotesDashboardWithPredicate:predicate label:@"text notes"];
}

- (IBAction)showHighlightsDashboard:(id)sender {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"type == %@", SKNHighlightString];
    [self showNotesDashboardWithPredicate:predicate label:@"highlights"];
}

- (IBAction)showBoxNotesDashboard:(id)sender {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"type == %@", SKNSquareString];
    [self showNotesDashboardWithPredicate:predicate label:@"box notes"];
}

- (IBAction)showNotesWithColor:(id)sender {
    NSColor *color = [sender representedObject];
    if (color == nil)
        return;
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PDFAnnotation *annotation, NSDictionary *bindings) {
        return [[annotation color] isEqual:color];
    }];
    [self showNotesDashboardWithPredicate:predicate label:@"notes with this color"];
}

- (NSMenuItem *)notesDashboardItemWithTitle:(NSString *)title action:(SEL)action count:(NSUInteger)count {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%lu)", title, (unsigned long)count] action:action keyEquivalent:@""];
    [item setTarget:self];
    return item;
}

- (IBAction)showAIMoreActions:(id)sender {
    NSMenu *menu = [NSMenu menu];
    BOOL scientific = [self isScientificReadingProfile];
    [menu addItemWithTitle:scientific ? @"Analyze This Paper Page" : @"Summarize This Page" action:@selector(summarizeCurrentPage:) target:self];
    [menu addItemWithTitle:scientific ? @"Build Paper Map (PDF)" : @"Summarize This PDF" action:@selector(summarizeDocument:) target:self];
    // The quick action row holds only the reading loop -- what a reader
    // presses on nearly every page.  The rest of the profile's actions live
    // here, where a row of six buttons used to.
    for (NSNumber *rawAction in [AnchoraPrompts overflowActionsWithProfile:[[AnchoraSettings sharedSettings] readingProfile]]) {
        AnchoraQuickAction action = (AnchoraQuickAction)[rawAction integerValue];
        NSMenuItem *actionItem = [[NSMenuItem alloc] initWithTitle:[AnchoraPrompts menuTitleForAction:action]
                                                            action:@selector(performAnchoraMenuAction:)
                                                     keyEquivalent:@""];
        [actionItem setTarget:self];
        [actionItem setTag:action];
        [actionItem setToolTip:[AnchoraPrompts tooltipForAction:action]];
        [menu addItem:actionItem];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenu *languageMenu = [[NSMenu alloc] initWithTitle:@"Response language"];
    NSMenuItem *chineseItem = [[NSMenuItem alloc] initWithTitle:@"繁體中文" action:@selector(changeAIResponseLanguage:) keyEquivalent:@""];
    [chineseItem setTarget:self];
    [chineseItem setTag:AnchoraResponseLanguageTraditionalChinese];
    [chineseItem setState:[self usesTraditionalChineseResponses] ? NSControlStateValueOn : NSControlStateValueOff];
    [languageMenu addItem:chineseItem];
    NSMenuItem *englishItem = [[NSMenuItem alloc] initWithTitle:@"English" action:@selector(changeAIResponseLanguage:) keyEquivalent:@""];
    [englishItem setTarget:self];
    [englishItem setTag:AnchoraResponseLanguageEnglish];
    [englishItem setState:[self usesTraditionalChineseResponses] ? NSControlStateValueOff : NSControlStateValueOn];
    [languageMenu addItem:englishItem];
    NSMenuItem *languageItem = [[NSMenuItem alloc] initWithTitle:@"Response language" action:nil keyEquivalent:@""];
    [languageItem setSubmenu:languageMenu];
    [menu addItem:languageItem];
    NSMenu *modelMenu = [[NSMenu alloc] initWithTitle:@"AI model"];
    NSString *selectedModel = [self selectedAIModel];
    for (AnchoraModelChoice *choice in [AnchoraSettings availableModels]) {
        NSString *model = [choice identifier];
        NSMenuItem *modelItem = [[NSMenuItem alloc] initWithTitle:[choice title] action:@selector(changeAIModel:) keyEquivalent:@""];
        [modelItem setTarget:self];
        [modelItem setRepresentedObject:model];
        [modelItem setState:[model isEqualToString:selectedModel] ? NSControlStateValueOn : NSControlStateValueOff];
        [modelMenu addItem:modelItem];
    }
    NSMenuItem *modelItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"AI model (%@)", selectedModel] action:nil keyEquivalent:@""];
    [modelItem setSubmenu:modelMenu];
    [menu addItem:modelItem];
    [menu addItem:[NSMenuItem separatorItem]];
    NSArray<PDFAnnotation *> *notes = [mainController notes] ?: @[];
    NSUInteger aiCount = 0, textCount = 0, highlightCount = 0, boxCount = 0;
    NSMutableOrderedSet<NSColor *> *colors = [NSMutableOrderedSet orderedSet];
    for (PDFAnnotation *annotation in notes) {
        if ([[annotation userName] isEqualToString:SKAIAssistantName]) aiCount++;
        if ([[annotation type] isEqualToString:SKNFreeTextString]) textCount++;
        if ([[annotation type] isEqualToString:SKNHighlightString]) highlightCount++;
        if ([[annotation type] isEqualToString:SKNSquareString]) boxCount++;
        if ([annotation color]) [colors addObject:[annotation color]];
    }
    NSMenu *notesMenu = [[NSMenu alloc] initWithTitle:@"Notes dashboard"];
    [notesMenu addItem:[self notesDashboardItemWithTitle:@"All notes" action:@selector(showAllNotesDashboard:) count:[notes count]]];
    [notesMenu addItem:[self notesDashboardItemWithTitle:@"AI answers" action:@selector(showAINotesDashboard:) count:aiCount]];
    [notesMenu addItem:[self notesDashboardItemWithTitle:@"Text notes" action:@selector(showTextNotesDashboard:) count:textCount]];
    [notesMenu addItem:[self notesDashboardItemWithTitle:@"Highlights" action:@selector(showHighlightsDashboard:) count:highlightCount]];
    [notesMenu addItem:[self notesDashboardItemWithTitle:@"Box notes" action:@selector(showBoxNotesDashboard:) count:boxCount]];
    if ([colors count]) {
        NSMenu *colorMenu = [[NSMenu alloc] initWithTitle:@"Filter by color"];
        NSUInteger index = 1;
        for (NSColor *color in colors) {
            NSMenuItem *colorItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Color %lu", (unsigned long)index++] action:@selector(showNotesWithColor:) keyEquivalent:@""];
            [colorItem setTarget:self];
            [colorItem setRepresentedObject:color];
            [colorItem setImage:[NSImage imageWithSize:NSMakeSize(12.0, 12.0) flipped:NO drawingHandler:^BOOL(NSRect rect) {
                [color set];
                [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1.0, 1.0)] fill];
                return YES;
            }]];
            [colorMenu addItem:colorItem];
        }
        NSMenuItem *colorItem = [[NSMenuItem alloc] initWithTitle:@"Filter by color" action:nil keyEquivalent:@""];
        [colorItem setSubmenu:colorMenu];
        [notesMenu addItem:colorItem];
    }
    NSMenuItem *dashboardItem = [[NSMenuItem alloc] initWithTitle:@"Notes dashboard" action:nil keyEquivalent:@""];
    [dashboardItem setSubmenu:notesMenu];
    [menu addItem:dashboardItem];
    [menu addItem:[NSMenuItem separatorItem]];
    NSUInteger waiting = [[AnchoraStore shared] openNoteCount];
    NSString *inboxTitle = waiting > 0
        ? [NSString stringWithFormat:@"Inbox (%lu waiting)", (unsigned long)waiting]
        : @"Inbox";
    [menu addItemWithTitle:inboxTitle action:@selector(showAIInbox:) target:self];
    NSMenuItem *captureItem = [[NSMenuItem alloc] initWithTitle:@"Capture a Thought…"
                                                         action:@selector(captureThought:)
                                                  keyEquivalent:@"j"];
    [captureItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [captureItem setTarget:self];
    [menu addItem:captureItem];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Set OpenAI API Key…" action:@selector(configureOpenAIAPIKey:) target:self];
    NSView *view = (NSView *)sender;
    NSPoint location = [self.aiHeaderModel moreActionsMenuLocationInViewBounds:[view bounds] isFlipped:[view isFlipped]];
    [menu popUpMenuPositioningItem:nil atLocation:location inView:view];
}

- (void)recordAIConversationRole:(NSString *)role text:(NSString *)text {
    if ([text length] == 0)
        return;
    if (self.aiConversation == nil)
        self.aiConversation = [NSMutableArray array];
    [self.aiConversation addObject:@{ @"role": role, @"text": text }];
    while ([self.aiConversation count] > 12)
        [self.aiConversation removeObjectAtIndex:0];
}

- (NSArray<NSNumber *> *)sourcePageIndexesForSelection:(PDFSelection *)selection fallbackPage:(PDFPage *)fallbackPage {
    NSMutableOrderedSet<NSNumber *> *indexes = [NSMutableOrderedSet orderedSet];
    for (PDFPage *page in [selection pages]) {
        if (page)
            [indexes addObject:@([page pageIndex])];
    }
    if ([indexes count] == 0 && fallbackPage)
        [indexes addObject:@([fallbackPage pageIndex])];
    return [indexes array];
}

- (NSString *)requestSourceDescriptionForPageIndexes:(NSArray<NSNumber *> *)pageIndexes {
    return [self sourceLabelForPageIndexes:pageIndexes] ?: @"unknown page";
}

- (void)startAIRequestWithQuestion:(NSString *)question sourceText:(NSString *)sourceText imageDataURL:(NSString *)imageDataURL fileDataURL:(NSString *)fileDataURL fileName:(NSString *)fileName selection:(PDFSelection *)selection page:(PDFPage *)page pageRect:(NSRect)pageRect displayQuestion:(NSString *)displayQuestion {
    NSString *apiKey = [AnchoraCredentials openAIAPIKey];
    if ([apiKey length] == 0) {
        if ([self configureOpenAIAPIKey:nil] == NO)
            return;
        apiKey = [AnchoraCredentials openAIAPIKey];
        if ([apiKey length] == 0)
            return;
    }

    NSArray<NSNumber *> *sourcePageIndexes = [self sourcePageIndexesForSelection:selection fallbackPage:page];
    // Follow-up questions intentionally work without a new selection. Keep a
    // traceable source in that case rather than making the answer look uncited.
    if ([sourcePageIndexes count] == 0)
        sourcePageIndexes = [self.aiTurn sourcePageIndexes] ?: @[];
    NSString *sourceDescription = [self requestSourceDescriptionForPageIndexes:sourcePageIndexes];

    // Whichever map this is was decided by the action the reader chose, rather
    // than inferred from the wording of the question.
    AnchoraMapKind mapKind = [fileDataURL length] > 0 ? self.aiPendingMapKind : AnchoraMapKindNone;
    self.aiPendingMapKind = AnchoraMapKindNone;

    AnchoraRequest *request = [[AnchoraRequest alloc] init];
    [request setModel:[self selectedAIModel]];
    [request setInstructions:[AnchoraPrompts systemInstructionsWithProfile:[[AnchoraSettings sharedSettings] readingProfile]
                                                                 language:[[AnchoraSettings sharedSettings] responseLanguage]
                                                          webVerification:self.webVerificationEnabled]];
    [request setPrompt:[AnchoraPrompts userPromptWithQuestion:question sourceText:sourceText sourceDescription:sourceDescription]];
    [request setImageDataURL:imageDataURL];
    [request setFileDataURL:fileDataURL];
    [request setFileName:fileName];
    [request setPriorMessages:self.aiConversation ?: @[]];
    [request setWebSearchEnabled:self.webVerificationEnabled];
    // A map has to lay out the whole document, so a short answer would cut it
    // off mid-structure.
    [request setMaxOutputTokens:mapKind != AnchoraMapKindNone ? SKAIMapMaximumOutputTokens : SKAIStandardMaximumOutputTokens];
    // A full-paper map can legitimately take longer than a selected sentence.
    // It remains cancellable through the Stop button in the composer.
    [request setTimeout:[fileDataURL length] ? 300.0 : 120.0];

    [self.aiClient cancel];
    NSString *conversationUserText = [sourceText length] ? [NSString stringWithFormat:@"%@\n\nPDF context used:\n%@", displayQuestion, [sourceText substringToIndex:MIN((NSUInteger)6000, [sourceText length])]] : displayQuestion;
    self.aiTurn = [[AnchoraTurn alloc] initWithQuestion:displayQuestion
                                   conversationUserText:conversationUserText
                                              selection:selection
                                       hasTextSelection:[selection hasCharacters]
                                                   page:page
                                               pageRect:pageRect
                                           imageDataURL:imageDataURL
                                      sourcePageIndexes:sourcePageIndexes
                                                mapKind:mapKind
                                                 status:[AnchoraPrompts preparingStatusWithHasFile:[fileDataURL length] > 0 hasImage:[imageDataURL length] > 0]];
    [self recordAIConversationRole:@"user" text:conversationUserText];
    [self appendChatMessageFrom:@"You" text:displayQuestion];
    [self appendChatMessageFrom:SKAIAssistantName text:nil sourcePageIndexes:sourcePageIndexes];
    [self.aiComposerModel setQuestionText:@""];
    [self.aiComposerModel setPinEnabled:NO];
    // The same control becomes Stop while a request is live.  A full-PDF
    // request can legitimately take longer than a selection, so this makes
    // the wait explicit and always escapable.
    [self.aiComposerModel setRequestInFlight:YES];
    [self updateAIRequestStatus:[AnchoraPrompts sendingStatusWithHasFile:[fileDataURL length] > 0 hasImage:[imageDataURL length] > 0]];

    AnchoraResponsesClient *client = [[AnchoraResponsesClient alloc] initWithApiKey:apiKey request:request];
    __weak SKRightSideViewController *weakSelf = self;
    [client setOnStatus:^(NSString *status) {
        [weakSelf updateAIRequestStatus:status];
    }];
    [client setOnDelta:^(NSString *text) {
        [weakSelf appendStreamedAIText:text];
    }];
    [client setOnFinish:^(NSString *text, NSArray<NSString *> *webSources, NSString *errorMessage, BOOL cancelled) {
        [weakSelf finishAIRequestWithText:text webSources:webSources errorMessage:errorMessage cancelled:cancelled];
    }];
    self.aiClient = client;
    [client start];
}

- (NSString *)imageDataURLForEntirePage:(PDFPage *)page displayBox:(PDFDisplayBox)box {
    return page ? [AnchoraCapture pageImageDataURLWithPage:page box:box] : nil;
}

- (IBAction)summarizeCurrentPage:(id)sender {
    NSString *question = [AnchoraPrompts pageSummaryPromptWithProfile:[[AnchoraSettings sharedSettings] readingProfile]];
    SKPDFView *pdfView = [mainController pdfView];
    NSUInteger pageNumber = [[pdfView currentPage] pageIndex] + 1;
    [self analyzeCurrentPageWithQuestion:question displayQuestion:[NSString stringWithFormat:[self isScientificReadingProfile] ? @"Analyze paper page %lu" : @"Summarize page %lu", (unsigned long)pageNumber]];
}

- (void)analyzeCurrentPageWithQuestion:(NSString *)question displayQuestion:(NSString *)displayQuestion {
    [self analyzePage:[[mainController pdfView] currentPage] question:question displayQuestion:displayQuestion];
}

/// Returns NO when the page could not be rendered, so a caller that was about
/// to enter a mode -- a quiz waiting for answers -- does not enter it.
- (BOOL)analyzePage:(PDFPage *)page question:(NSString *)question displayQuestion:(NSString *)displayQuestion {
    PDFDisplayBox box = [[mainController pdfView] displayBox];
    NSString *pageImageDataURL = [self imageDataURLForEntirePage:page displayBox:box];
    if ([pageImageDataURL length] == 0) {
        NSBeep();
        [self appendChatMessageFrom:SKAIAssistantName text:[AnchoraPrompts pageRenderFailureMessage]];
        return NO;
    }
    NSUInteger pageNumber = [page pageIndex] + 1;
    [self.aiHeaderModel setContextText:[AnchoraPrompts pageAttachedMessageWithPageNumber:pageNumber] expandable:NO];
    [self startAIRequestWithQuestion:question
                           sourceText:[AnchoraPrompts pageImageContextText]
                         imageDataURL:pageImageDataURL
                          fileDataURL:nil
                             fileName:nil
                            selection:nil page:page pageRect:[page boundsForBox:box]
                       displayQuestion:displayQuestion];
    return YES;
}

- (void)startWholeDocumentRequestWithQuestion:(NSString *)question displayQuestion:(NSString *)displayQuestion {
    [self startWholeDocumentRequestWithQuestion:question displayQuestion:displayQuestion mapKind:AnchoraMapKindNone];
}

- (void)startWholeDocumentRequestWithQuestion:(NSString *)question displayQuestion:(NSString *)displayQuestion mapKind:(AnchoraMapKind)mapKind {
    self.aiPendingMapKind = mapKind;
    PDFDocument *document = [mainController pdfDocument];
    NSUInteger pageCount = [document pageCount];
    if (pageCount == 0) {
        NSBeep();
        return;
    }
    NSData *pdfData = [document dataRepresentation];
    static const NSUInteger SKMaximumPDFInputBytes = 50 * 1024 * 1024;
    if ([pdfData length] == 0) {
        NSBeep();
        [self appendChatMessageFrom:SKAIAssistantName text:@"I could not read this PDF’s data for a whole-document summary."];
        return;
    }
    if ([pdfData length] >= SKMaximumPDFInputBytes) {
        NSBeep();
        [self appendChatMessageFrom:SKAIAssistantName text:@"This PDF is 50 MB or larger, which exceeds the API’s single-file input limit."];
        return;
    }
    NSURL *fileURL = [(NSDocument *)[mainController document] fileURL];
    NSString *fileName = [[fileURL lastPathComponent] length] ? [fileURL lastPathComponent] : @"document.pdf";
    NSString *fileDataURL = [@"data:application/pdf;base64," stringByAppendingString:[pdfData base64EncodedStringWithOptions:0]];
    [self.aiHeaderModel setContextText:[AnchoraPrompts documentAttachedMessageWithPageCount:pageCount] expandable:NO];
    PDFPage *page = [[mainController pdfView] currentPage];
    [self startAIRequestWithQuestion:question
                           sourceText:@"The complete original PDF is attached."
                         imageDataURL:nil
                          fileDataURL:fileDataURL
                             fileName:fileName
                            selection:nil page:page pageRect:[page boundsForBox:[[mainController pdfView] displayBox]]
                       displayQuestion:displayQuestion];
}

- (IBAction)summarizeDocument:(id)sender {
    AnchoraReadingProfile profile = [[AnchoraSettings sharedSettings] readingProfile];
    [self startWholeDocumentRequestWithQuestion:[AnchoraPrompts documentSummaryPromptWithProfile:profile]
                                displayQuestion:[AnchoraPrompts documentSummaryDisplayTitleWithProfile:profile]
                                        mapKind:profile == AnchoraReadingProfileScientific ? AnchoraMapKindPaper : AnchoraMapKindNone];
}

- (BOOL)configureOpenAIAPIKey:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Connect OpenAI API"];
    [alert setInformativeText:@"Paste your OpenAI API key. Anchora stores it only in your macOS Keychain; it is never saved in the PDF or bundled with the app. API usage needs separate API billing from ChatGPT Plus."];
    [alert addButtonWithTitle:@"Save Key"];
    [alert addButtonWithTitle:@"Cancel"];

    NSSecureTextField *keyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 360.0, 24.0)];
    [keyField setPlaceholderString:@"sk-…"];
    [alert setAccessoryView:keyField];
    if ([alert runModal] != NSAlertFirstButtonReturn)
        return NO;

    NSString *key = [[keyField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([key length] == 0)
        return NO;
    [AnchoraCredentials storeOpenAIAPIKey:key];
    return YES;
}

- (void)appendStreamedAIText:(NSString *)text {
    if ([text length] == 0)
        return;
    [self.aiTurn setReceivedOutput:YES];
    [[self.aiTurn response] appendString:text];
    [self.aiChatModel appendStreamedText:text];
}

- (void)finishAIRequestWithText:(NSString *)text webSources:(NSArray<NSString *> *)webSources errorMessage:(NSString *)errorMessage cancelled:(BOOL)cancelled {
    self.aiClient = nil;
    AnchoraTurn *turn = self.aiTurn;
    if (cancelled) {
        [self.aiChatModel replaceStreamingMessageWith:[AnchoraPrompts stoppedMessage]];
    } else if ([errorMessage length]) {
        [self.aiChatModel replaceStreamingMessageWith:errorMessage];
    } else {
        // Keep the complete response for Pin latest answer and memory, while
        // presenting the Paper Map itself as a compact navigator.  Do this
        // before adding web sources so the parser only sees the structured
        // paper analysis.
        if ([text length] && [[turn response] length] == 0)
            [[turn response] setString:text];
        if ([turn isMap]) {
            [self presentMapFromResponse:[turn response] kind:[turn mapKind] select:YES];
            [self saveMapFromTurn:turn];
            [self.aiChatModel removeStreamingMessage];
        }
        if ([webSources count]) {
            NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:[webSources count]];
            for (NSString *URLString in webSources)
                [lines addObject:[NSString stringWithFormat:@"• %@", URLString]];
            NSString *sources = [lines componentsJoinedByString:@"\n"];
            [self appendChatMessageFrom:@"Web sources" text:sources];
            [[turn response] appendFormat:@"\n\nWeb sources:\n%@", sources];
        }
        [self recordAIConversationRole:@"assistant" text:[turn response]];
        [self.aiChatModel endStreaming];
    }
    [self.aiComposerModel setPinEnabled:[turn canPin]];
    [self.aiComposerModel setRequestInFlight:NO];
    [turn setStatus:nil];
}

- (void)saveMapFromTurn:(AnchoraTurn *)turn {
    NSString *path = [self currentDocumentPath];
    if ([path length] == 0 || [[turn response] length] == 0)
        return;
    [[AnchoraStore shared] saveMapWithResponse:[turn response]
                                  kindRawValue:[turn mapKind]
                                  documentPath:path
                                         title:[self currentDocumentTitle]];
}

- (void)resetAIConversationForNewDocument {
    [self.aiClient cancel];
    self.aiClient = nil;
    // The page labels are captured when the pane view is built, so the
    // navigator has to be rebuilt against the document now open.
    if (self.aiPaneView)
        [AnchoraHosting updatePaneView:self.aiPaneView
                                  pane:self.aiPaneModel
                                  chat:self.aiChatModel
                                   map:self.aiMapModel
                                 inbox:self.aiInboxModel
                            pageLabels:[self pdfPageLabels]];
    self.aiConversation = [NSMutableArray array];
    self.aiTurn = nil;
    [self setQuizPending:NO page:nil];
    [self clearPaperMap];
    [self.aiChatModel clear];
    [self.aiInboxModel reload];
    [self claimQuickCaptureSource];
    [self restoreSavedMap];
    [self queueWelcomeMessage];
}

- (IBAction)clearAIConversation:(id)sender {
    [self.aiClient cancel];
    self.aiClient = nil;
    self.aiConversation = [NSMutableArray array];
    self.aiTurn = nil;
    [self setQuizPending:NO page:nil];
    // The map is not cleared with the chat. It belongs to the document, it is
    // saved, and rebuilding it costs another whole-PDF upload.
    [self.aiChatModel clear];
    [self.aiComposerModel setPinEnabled:NO];
    [self.aiComposerModel setRequestInFlight:NO];
}

- (void)copyAnswerText:(NSString *)text {
    // The clipboard gets plain text: an answer pasted into notes, mail or a
    // manuscript should not arrive full of Markdown punctuation.
    NSString *plain = [text length] ? [AnchoraMarkdown plainTextFrom:text] : nil;
    if ([plain length] == 0) {
        NSBeep();
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[plain]];
}

- (void)pinTurn:(AnchoraTurn *)turn asTextNote:(BOOL)asTextNote {
    // A PDF note holds plain text, and it has to stay readable in other PDF
    // apps too, so the answer's Markdown is flattened rather than pinned raw.
    NSString *response = [[turn response] length] ? [AnchoraMarkdown plainTextFrom:[turn response]] : nil;
    if ([response length] == 0) {
        NSBeep();
        return;
    }
    NSString *title = [turn question];
    if ([[turn selection] hasCharacters]) {
        if (asTextNote)
            [mainController pinAIResponse:response title:title asTextNoteForSelection:[turn selection]];
        else
            [mainController pinAIResponse:response title:title forSelection:[turn selection]];
    } else if ([turn page]) {
        if (asTextNote)
            [mainController pinAIResponse:response title:title asTextNoteNearRect:[turn pageRect] onPage:[turn page]];
        else
            [mainController pinAIResponse:response title:title nearRect:[turn pageRect] onPage:[turn page]];
    } else {
        NSBeep();
    }
}

- (IBAction)pinResponseToPDF:(id)sender {
    [self pinTurn:self.aiTurn asTextNote:NO];
}

- (void)showAIInterface:(BOOL)show {
    [searchField setHidden:show];
    if (show) {
        // With full-size window content, this view can extend below the native
        // sidebar toolbar. Start below it so the controls do not overlap.
        self.aiTopConstraint.constant = [self topInset] + NSHeight([topBar frame]) + 12.0;
        [self updateSelectionContext:nil];
        // The pane now has a real width; finish deferred chat sizing here.
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [snapshotTableView setDelegate:nil];
    [snapshotTableView setDataSource:nil];
    [noteOutlineView setDelegate:nil];
    [noteOutlineView setDataSource:nil];
}

- (NSString *)nibName {
    return @"RightSideView";
}

- (void)handleSnapshotViewFrameChanged:(NSNotification *)notification {
    NSView *view = [notification object];
    [[[view subviews] firstObject] setFrame:[view bounds]];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [button setSegmentCount:3];
    [button setLabel:@"AI" forSegment:SKSidePaneStateAI];
    [button setTag:SKSidePaneStateAI forSegment:SKSidePaneStateAI];
    [button setHelp:@"Ask AI about selected text" forSegment:SKSidePaneStateAI];
    // The original two tabs relied only on a Cocoa binding. Adding the third
    // tab programmatically made that binding unreliable, so route every click
    // through an explicit action as well.
    [button setTarget:self];
    [button setAction:@selector(changeRightSidePane:)];
    [self buildAIInterface];

    [button setHelp:NSLocalizedString(@"View Notes", @"Tool tip message") forSegment:SKSidePaneStateNote];
    [button setHelp:NSLocalizedString(@"View Snapshots", @"Tool tip message") forSegment:SKSidePaneStateSnapshot];

    NSMenu *menu = [NSMenu menu];
    [menu addItemWithTitle:NSLocalizedString(@"Ignore Case", @"Menu item title") action:@selector(toggleCaseInsensitiveFilter:) target:mainController];
    [[searchField cell] setSearchMenuTemplate:menu];
    [[searchField cell] setPlaceholderString:NSLocalizedString(@"Filter", @"placeholder")];

    [searchField setAction:@selector(searchNotes:)];
    [searchField setTarget:mainController];

    [noteOutlineView setAutoresizesOutlineColumn: NO];

    [noteOutlineView setStronglyReferencesItems:YES];

    [noteOutlineView setDelegate:mainController];
    [noteOutlineView setDataSource:mainController];
    [snapshotTableView setDelegate:mainController];
    [snapshotTableView setDataSource:mainController];
    [[noteOutlineView menu] setDelegate:mainController];
    [[snapshotTableView menu] setDelegate:mainController];

    [noteOutlineView setDoubleAction:@selector(selectSelectedNote:)];
    [noteOutlineView setTarget:mainController];
    [snapshotTableView setDoubleAction:@selector(toggleSelectedSnapshots:)];
    [snapshotTableView setTarget:mainController];

    [noteOutlineView setTypeSelectHelper:[SKTypeSelectHelper typeSelectHelperWithMatchOption:SKSubstringMatch]];

    NSSortDescriptor *pageIndexSortDescriptor = [[NSSortDescriptor alloc] initWithKey:SKNPDFAnnotationPageIndexKey ascending:YES];
    NSSortDescriptor *boundsSortDescriptor = [[NSSortDescriptor alloc] initWithKey:SKPDFAnnotationBoundsOrderKey ascending:YES selector:@selector(compare:)];
    [noteArrayController setSortDescriptors:@[pageIndexSortDescriptor, boundsSortDescriptor]];
    [snapshotArrayController setSortDescriptors:@[pageIndexSortDescriptor]];

    [noteOutlineView setIndentationPerLevel:1.0];

    [noteOutlineView registerForDraggedTypes:[NSColor readableTypesForPasteboard:[NSPasteboard pasteboardWithName:NSPasteboardNameDrag]]];
    [noteOutlineView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];

    [snapshotTableView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
}

- (IBAction)changeRightSidePane:(id)sender {
    [mainController setRightSidePaneState:[button selectedTag]];
}

- (void)setMainController:(SKMainWindowController *)newMainController {
    if (mainController && newMainController == nil) {
        [snapshotTableView setDelegate:nil];
        [snapshotTableView setDataSource:nil];
        [noteOutlineView setDelegate:nil];
        [noteOutlineView setDataSource:nil];
    }
    if (mainController) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SKPDFViewSelectionChangedNotification object:[mainController pdfView]];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SKPDFViewAISelectionAreaChangedNotification object:[mainController pdfView]];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SKPDFViewAIImageSelectionAreaChangedNotification object:[mainController pdfView]];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:PDFViewSelectionChangedNotification object:[mainController pdfView]];
    }
    [super setMainController:newMainController];
    if (newMainController) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateSelectionContext:) name:SKPDFViewSelectionChangedNotification object:[newMainController pdfView]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateSelectionContext:) name:SKPDFViewAISelectionAreaChangedNotification object:[newMainController pdfView]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateSelectionContext:) name:SKPDFViewAIImageSelectionAreaChangedNotification object:[newMainController pdfView]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateSelectionContext:) name:PDFViewSelectionChangedNotification object:[newMainController pdfView]];
        [self updateSelectionContext:nil];
    }
}

- (NSArray *)tableViews {
    return [NSArray arrayWithObjects:noteOutlineView, snapshotTableView, nil];
}

@end
