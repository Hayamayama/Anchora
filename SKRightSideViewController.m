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
static const NSUInteger SKAIPaperMapMaximumOutputTokens = 16000;

@interface SKRightSideViewController ()
@property (nonatomic, nullable, strong) NSTextView *aiContextTextView;
@property (nonatomic, nullable, strong) AnchoraComposerModel *aiComposerModel;
// The transcript and the Paper Map navigator are SwiftUI.  AppKit owns only
// their position and height in the sidebar; everything inside — wrapped text
// height, bubble growth, scrolling, link handling — belongs to the framework.
@property (nonatomic, nullable, strong) AnchoraChatModel *aiChatModel;
@property (nonatomic, nullable, strong) AnchoraPaperMapModel *aiPaperMapModel;
@property (nonatomic, nullable, strong) NSView *aiChatView;
@property (nonatomic, nullable, strong) NSTextField *aiTitleLabel, *aiSubtitleLabel, *aiContextLabel;
@property (nonatomic, nullable, strong) NSSegmentedControl *aiReadingProfileControl;
@property (nonatomic, nullable, strong) NSView *aiPaperMapCard;
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiPaperMapHeightConstraint;
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
@end

@implementation SKRightSideViewController

@synthesize noteArrayController, noteOutlineView, snapshotArrayController, snapshotTableView, aiView;

- (NSScrollView *)scrollViewWithTextView:(NSTextView **)textView {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [scrollView setBorderType:NSNoBorder];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    [scrollView setDrawsBackground:NO];
    [scrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSZeroRect];
    [view setEditable:NO];
    [view setSelectable:YES];
    [view setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    [view setTextContainerInset:NSMakeSize(6.0, 6.0)];
    [view setDrawsBackground:NO];
    [scrollView setDocumentView:view];
    if (textView)
        *textView = view;
    return scrollView;
}

- (NSVisualEffectView *)aiCardView {
    NSVisualEffectView *view = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [view setMaterial:NSVisualEffectMaterialContentBackground];
    [view setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
    [view setState:NSVisualEffectStateActive];
    [view setWantsLayer:YES];
    [[view layer] setCornerRadius:12.0];
    [[view layer] setMasksToBounds:YES];
    [view setTranslatesAutoresizingMaskIntoConstraints:NO];
    return view;
}

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

- (void)updatePaperMapCardHeight {
    CGFloat height = [self.aiPaperMapModel preferredHeight];
    [self.aiPaperMapCard setHidden:height <= 0.0];
    // A hidden map must be exactly zero-height: NSView.hidden does not remove
    // Auto Layout constraints. The visible state lowers this priority so it
    // yields gracefully in a very short sidebar.
    self.aiPaperMapHeightConstraint.priority = height > 0.0 ? NSLayoutPriorityDefaultHigh : NSLayoutPriorityRequired;
    self.aiPaperMapHeightConstraint.constant = height;
}

- (NSArray<NSString *> *)pdfPageLabels {
    PDFDocument *document = [mainController pdfDocument];
    NSUInteger pageCount = [document pageCount];
    NSMutableArray<NSString *> *labels = [NSMutableArray arrayWithCapacity:pageCount];
    for (NSUInteger index = 0; index < pageCount; index++)
        [labels addObject:[[document pageAtIndex:index] label] ?: @""];
    return labels;
}

- (NSArray<NSNumber *> *)paperMapPageIndexesForText:(NSString *)text {
    return [AnchoraPaperMap pageIndexesInText:text ?: @"" pageLabels:[self pdfPageLabels]];
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
    [self.aiPaperMapModel clear];
}

- (void)presentPaperMapFromResponse:(NSString *)response {
    [self.aiPaperMapModel present:[AnchoraPaperMap sectionsFromResponse:response ?: @"" pageLabels:[self pdfPageLabels]]];
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
                                   sourcePageIndex:[sourcePageIndexes firstObject]];
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

- (void)replaceStreamingPlaceholderWithText:(NSString *)text {
    [self.aiChatModel replaceStreamingMessageWith:text ?: @""];
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
    [self.aiReadingProfileControl setSelectedSegment:scientific ? 1 : 0];
    [self.aiTitleLabel setStringValue:scientific ? @"Anchora Scientific" : @"Anchora AI"];
    [self.aiSubtitleLabel setStringValue:scientific ? @"Trace the evidence behind a paper" : @"Ask about what you are reading"];
    [self.aiContextLabel setStringValue:scientific ? @"PAPER CONTEXT" : @"CONTEXT"];
    [self.aiComposerModel setPlaceholderText:[AnchoraPrompts composerPlaceholderWithProfile:profile]];
    [self.aiComposerModel setQuickActionTitles:[AnchoraPrompts quickActionTitlesWithProfile:profile]
                                      tooltips:[AnchoraPrompts quickActionTooltipsWithProfile:profile]];
    if ([self.aiSelection hasContext] == NO && [self.aiSelection isRecognizingText] == NO)
        [self.aiContextTextView setString:[AnchoraPrompts emptyContextMessageWithProfile:profile]];
}

- (IBAction)changeAIReadingProfile:(id)sender {
    NSInteger selectedSegment = [(NSSegmentedControl *)sender selectedSegment];
    [[AnchoraSettings sharedSettings] setReadingProfile:selectedSegment == 1 ? AnchoraReadingProfileScientific : AnchoraReadingProfileStudy];
    [self updateAIReadingProfileInterface];
}

- (void)buildAIInterface {
    NSVisualEffectView *rootView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [rootView setMaterial:NSVisualEffectMaterialSidebar];
    [rootView setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [rootView setState:NSVisualEffectStateFollowsWindowActiveState];
    [rootView setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSStackView *header = [[NSStackView alloc] initWithFrame:NSZeroRect];
    [header setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [header setAlignment:NSLayoutAttributeLeading];
    [header setSpacing:8.0];
    [header setTranslatesAutoresizingMaskIntoConstraints:NO];
    [rootView addSubview:header];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:16.0],
        [header.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-16.0]
    ]];
    self.aiTopConstraint = [header.topAnchor constraintEqualToAnchor:rootView.topAnchor constant:12.0];
    self.aiTopConstraint.active = YES;

    NSStackView *titleStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    [titleStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [titleStack setAlignment:NSLayoutAttributeLeading];
    [titleStack setSpacing:1.0];
    NSTextField *title = [NSTextField labelWithString:@"Anchora AI"];
    [title setFont:[NSFont boldSystemFontOfSize:16.0]];
    [title setTextColor:[NSColor labelColor]];
    NSTextField *subtitle = [NSTextField labelWithString:@"Ask about what you are reading"];
    [subtitle setTextColor:[NSColor secondaryLabelColor]];
    [subtitle setFont:[NSFont systemFontOfSize:11.0]];
    [titleStack addArrangedSubview:title];
    [titleStack addArrangedSubview:subtitle];
    self.aiTitleLabel = title;
    self.aiSubtitleLabel = subtitle;
    NSStackView *titleRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    [titleRow setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [titleRow setAlignment:NSLayoutAttributeTop];
    [titleRow addArrangedSubview:titleStack];
    NSView *titleSpacer = [NSView new];
    [titleSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [titleRow addArrangedSubview:titleSpacer];
    NSSegmentedControl *profileControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    [profileControl setSegmentCount:2];
    [profileControl setLabel:@"Study" forSegment:0];
    [profileControl setLabel:@"Scientific" forSegment:1];
    [profileControl setTrackingMode:NSSegmentSwitchTrackingSelectOne];
    [profileControl setControlSize:NSControlSizeSmall];
    [profileControl setTarget:self];
    [profileControl setAction:@selector(changeAIReadingProfile:)];
    [titleRow addArrangedSubview:profileControl];
    self.aiReadingProfileControl = profileControl;
    NSButton *moreButton = [NSButton buttonWithTitle:@"•••" target:self action:@selector(showAIMoreActions:)];
    [moreButton setBezelStyle:NSBezelStyleAccessoryBarAction];
    [moreButton setToolTip:@"PDF summary and API settings"];
    [titleRow addArrangedSubview:moreButton];
    [header addArrangedSubview:titleRow];

    NSVisualEffectView *contextCard = [self aiCardView];
    [rootView addSubview:contextCard];
    NSTextField *contextLabel = [NSTextField labelWithString:@"CONTEXT"];
    [contextLabel setTextColor:[NSColor secondaryLabelColor]];
    [contextLabel setFont:[NSFont boldSystemFontOfSize:10.0]];
    [contextLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [contextCard addSubview:contextLabel];
    self.aiContextLabel = contextLabel;
    NSTextView *contextTextView = nil;
    NSScrollView *contextScrollView = [self scrollViewWithTextView:&contextTextView];
    [contextTextView setFont:[NSFont systemFontOfSize:12.0]];
    [contextTextView setTextColor:[NSColor labelColor]];
    [contextCard addSubview:contextScrollView];
    [NSLayoutConstraint activateConstraints:@[
        [contextLabel.leadingAnchor constraintEqualToAnchor:contextCard.leadingAnchor constant:10.0],
        [contextLabel.topAnchor constraintEqualToAnchor:contextCard.topAnchor constant:8.0],
        [contextScrollView.leadingAnchor constraintEqualToAnchor:contextCard.leadingAnchor constant:4.0],
        [contextScrollView.trailingAnchor constraintEqualToAnchor:contextCard.trailingAnchor constant:-4.0],
        [contextScrollView.topAnchor constraintEqualToAnchor:contextLabel.bottomAnchor constant:1.0],
        [contextScrollView.bottomAnchor constraintEqualToAnchor:contextCard.bottomAnchor constant:-5.0]
    ]];

    // A paper map is a fixed-height navigator with its own scrollable detail
    // area.  It deliberately does not sit inside the chat view: large
    // scientific answers must never feed back into chat sizing while a PDF is
    // opening or a response is streaming.
    AnchoraPaperMapModel *paperMapModel = [[AnchoraPaperMapModel alloc] init];
    NSView *paperMapCard = [AnchoraHosting paperMapViewWithModel:paperMapModel pageLabels:[self pdfPageLabels]];
    [paperMapCard setHidden:YES];
    [rootView addSubview:paperMapCard];

    AnchoraChatModel *chatModel = [[AnchoraChatModel alloc] init];
    NSView *chatView = [AnchoraHosting chatViewWithModel:chatModel];
    [rootView addSubview:chatView];

    // Quick actions and the ask bar are one SwiftUI view.  Building the quick
    // action row from NSStackView arranged subviews is what used to make
    // AppKit measure it recursively while a PDF was opening.
    AnchoraComposerModel *composerModel = [[AnchoraComposerModel alloc] init];
    NSView *composer = [AnchoraHosting composerViewWithModel:composerModel];
    [rootView addSubview:composer positioned:NSWindowAbove relativeTo:chatView];

    [NSLayoutConstraint activateConstraints:@[
        [contextCard.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:12.0],
        [contextCard.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-12.0],
        [contextCard.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10.0],
        [contextCard.heightAnchor constraintEqualToConstant:86.0],
        [paperMapCard.leadingAnchor constraintEqualToAnchor:contextCard.leadingAnchor],
        [paperMapCard.trailingAnchor constraintEqualToAnchor:contextCard.trailingAnchor],
        [paperMapCard.topAnchor constraintEqualToAnchor:contextCard.bottomAnchor constant:8.0],
        [chatView.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:8.0],
        [chatView.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-8.0],
        [chatView.topAnchor constraintEqualToAnchor:paperMapCard.bottomAnchor constant:8.0],
        [chatView.bottomAnchor constraintEqualToAnchor:composer.topAnchor constant:-8.0],
        [chatView.heightAnchor constraintGreaterThanOrEqualToConstant:120.0],
        [composer.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:12.0],
        [composer.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-12.0],
        [composer.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor constant:-12.0],
        // A fixed height rather than an intrinsic one: nothing in the composer
        // wraps, so its height must not be allowed to depend on the sidebar's
        // width.
        [composer.heightAnchor constraintEqualToConstant:[AnchoraHosting composerHeight]]
    ]];

    self.aiView = rootView;
    self.aiContextTextView = contextTextView;
    self.aiPaperMapCard = paperMapCard;
    self.aiPaperMapModel = paperMapModel;
    self.aiPaperMapHeightConstraint = [paperMapCard.heightAnchor constraintEqualToConstant:0.0];
    self.aiPaperMapHeightConstraint.priority = NSLayoutPriorityRequired;
    self.aiPaperMapHeightConstraint.active = YES;
    self.aiChatView = chatView;
    self.aiChatModel = chatModel;
    self.aiComposerModel = composerModel;

    __weak SKRightSideViewController *weakSelf = self;
    [chatModel setOnOpenPage:^(NSInteger pageIndex) {
        [weakSelf goToPDFPageAtIndex:pageIndex];
    }];
    [paperMapModel setOnOpenPage:^(NSInteger pageIndex) {
        [weakSelf goToPDFPageAtIndex:pageIndex];
    }];
    [paperMapModel setOnOpenQuote:^(NSString *quote, NSInteger pageIndex) {
        [weakSelf selectPaperMapQuote:quote onPageAtIndex:pageIndex];
    }];
    [paperMapModel setPageLabelProvider:^NSString *(NSInteger pageIndex) {
        NSArray<NSString *> *labels = [weakSelf pdfPageLabels];
        return (pageIndex >= 0 && (NSUInteger)pageIndex < [labels count]) ? [labels objectAtIndex:(NSUInteger)pageIndex] : @"";
    }];
    [paperMapModel setOnLayoutChange:^{
        [weakSelf updatePaperMapCardHeight];
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
}

- (void)applySelection:(AnchoraSelection *)selection {
    self.aiSelection = selection;
    [self.aiContextTextView setString:[selection contextDescription]];
}

- (void)updateSelectionContext:(NSNotification *)notification {
    SKPDFView *pdfView = [mainController pdfView];
    if (pdfView == nil || self.aiContextTextView == nil)
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
        [self.aiContextTextView setString:[AnchoraPrompts imageCaptureFailureMessage]];
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

    NSString *question = [[self.aiComposerModel questionText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([question length] == 0)
        question = @"Explain this";
    [self startAIRequestWithQuestion:question
                          sourceText:[selection text]
                        imageDataURL:[selection imageDataURL]
                         fileDataURL:nil
                            fileName:nil
                           selection:[selection selection]
                                page:[selection page]
                            pageRect:[selection pageRect]
                     displayQuestion:question];
}

- (void)performQuickActionAtIndex:(NSInteger)tag {
    if ([self isScientificReadingProfile] == NO) {
        [self.aiComposerModel setQuestionText:[AnchoraPrompts studyQuickActionPromptWithTag:tag]];
        [self askAI:nil];
        return;
    }

    if (self.aiClient) {
        [self cancelCurrentAIRequest];
        return;
    }
    NSString *question = [AnchoraPrompts scientificQuickActionPromptWithTag:tag];
    if ([self.aiSelection hasContext] == NO)
        [self updateSelectionContext:nil];
    BOOL hasDirectContext = [self.aiSelection hasContext];
    NSString *displayQuestion = [AnchoraPrompts scientificQuickActionDisplayTitleWithTag:tag];
    // Paper is always a whole-document action. The other actions use a live
    // selection when present; otherwise they remain useful by using the
    // complete paper (or the visible page for Figure).
    if (tag == 0) {
        [self startWholeDocumentRequestWithQuestion:question displayQuestion:displayQuestion];
    } else if (hasDirectContext) {
        [self.aiComposerModel setQuestionText:question];
        [self askAI:nil];
    } else if (tag == 4) {
        [self analyzeCurrentPageWithQuestion:question displayQuestion:@"Analyze current page figure"];
    } else {
        [self startWholeDocumentRequestWithQuestion:question displayQuestion:displayQuestion];
    }
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
    [menu addItemWithTitle:@"Set OpenAI API Key…" action:@selector(configureOpenAIAPIKey:) target:self];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0.0, NSHeight([sender bounds])) inView:sender];
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

- (NSArray *)conversationInputItems {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *message in self.aiConversation) {
        BOOL isAssistant = [message[@"role"] isEqualToString:@"assistant"];
        [items addObject:@{
            @"role": message[@"role"],
            @"content": @[@{ @"type": isAssistant ? @"output_text" : @"input_text", @"text": message[@"text"] }]
        }];
    }
    return items;
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
    [request setMaxOutputTokens:([fileDataURL length] && [self isScientificReadingProfile]) ? SKAIPaperMapMaximumOutputTokens : SKAIStandardMaximumOutputTokens];
    // A full-paper map can legitimately take longer than a selected sentence.
    // It remains cancellable through the Stop button in the composer.
    [request setTimeout:[fileDataURL length] ? 300.0 : 120.0];

    [self.aiClient cancel];
    // A Paper Map is the sole full-document response rendered into the
    // navigator. All other requests remain normal chat replies.
    BOOL isPaperMap = [self isScientificReadingProfile] && [fileDataURL length] > 0 &&
        ([displayQuestion rangeOfString:@"Paper Map" options:NSCaseInsensitiveSearch].location != NSNotFound ||
         [question rangeOfString:@"Paper map" options:NSCaseInsensitiveSearch].location != NSNotFound);
    NSString *conversationUserText = [sourceText length] ? [NSString stringWithFormat:@"%@\n\nPDF context used:\n%@", displayQuestion, [sourceText substringToIndex:MIN((NSUInteger)6000, [sourceText length])]] : displayQuestion;
    self.aiTurn = [[AnchoraTurn alloc] initWithQuestion:displayQuestion
                                   conversationUserText:conversationUserText
                                              selection:selection
                                       hasTextSelection:[selection hasCharacters]
                                                   page:page
                                               pageRect:pageRect
                                           imageDataURL:imageDataURL
                                      sourcePageIndexes:sourcePageIndexes
                                             isPaperMap:isPaperMap
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
    SKPDFView *pdfView = [mainController pdfView];
    PDFPage *page = [pdfView currentPage];
    PDFDisplayBox box = [pdfView displayBox];
    NSString *pageImageDataURL = [self imageDataURLForEntirePage:page displayBox:box];
    if ([pageImageDataURL length] == 0) {
        NSBeep();
        [self appendChatMessageFrom:SKAIAssistantName text:@"I could not render this page as an image."];
        return;
    }
    NSUInteger pageNumber = [page pageIndex] + 1;
    [self.aiContextTextView setString:[NSString stringWithFormat:@"Page %lu image attached for visual summary", (unsigned long)pageNumber]];
    [self startAIRequestWithQuestion:question
                           sourceText:@"A complete rendered image of this PDF page is attached."
                         imageDataURL:pageImageDataURL
                          fileDataURL:nil
                             fileName:nil
                            selection:nil page:page pageRect:[page boundsForBox:box]
                       displayQuestion:displayQuestion];
}

- (void)startWholeDocumentRequestWithQuestion:(NSString *)question displayQuestion:(NSString *)displayQuestion {
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
    [self.aiContextTextView setString:[NSString stringWithFormat:@"Complete PDF attached: %lu pages", (unsigned long)pageCount]];
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
                                displayQuestion:[AnchoraPrompts documentSummaryDisplayTitleWithProfile:profile]];
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
        if ([turn isPaperMap]) {
            [self presentPaperMapFromResponse:[turn response]];
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

- (void)resetAIConversationForNewDocument {
    [self.aiClient cancel];
    self.aiClient = nil;
    if (self.aiPaperMapCard)
        [AnchoraHosting updatePaperMapView:self.aiPaperMapCard model:self.aiPaperMapModel pageLabels:[self pdfPageLabels]];
    self.aiConversation = [NSMutableArray array];
    self.aiTurn = nil;
    [self clearPaperMap];
    [self.aiChatModel clear];
    [self queueWelcomeMessage];
}

- (IBAction)clearAIConversation:(id)sender {
    [self.aiClient cancel];
    self.aiClient = nil;
    self.aiConversation = [NSMutableArray array];
    self.aiTurn = nil;
    [self clearPaperMap];
    [self.aiChatModel clear];
    [self.aiComposerModel setPinEnabled:NO];
    [self.aiComposerModel setRequestInFlight:NO];
}

- (IBAction)pinResponseToPDF:(id)sender {
    AnchoraTurn *turn = self.aiTurn;
    // A PDF note holds plain text, and it has to stay readable in other PDF
    // apps too, so the answer's Markdown is flattened rather than pinned raw.
    NSString *response = [[turn response] length] ? [AnchoraMarkdown plainTextFrom:[turn response]] : nil;
    if ([response length] == 0) {
        NSBeep();
        return;
    }
    if ([[turn selection] hasCharacters])
        [mainController pinAIResponse:response title:[turn question] forSelection:[turn selection]];
    else if ([turn page])
        [mainController pinAIResponse:response title:[turn question] nearRect:[turn pageRect] onPage:[turn page]];
    else
        NSBeep();
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
