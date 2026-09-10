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
@property (nonatomic, nullable, strong) NSTextField *aiQuestionField;
@property (nonatomic, nullable, strong) NSButton *askAIButton, *pinResponseButton;
// The transcript and the Paper Map navigator are SwiftUI.  AppKit owns only
// their position and height in the sidebar; everything inside — wrapped text
// height, bubble growth, scrolling, link handling — belongs to the framework.
@property (nonatomic, nullable, strong) AnchoraChatModel *aiChatModel;
@property (nonatomic, nullable, strong) AnchoraPaperMapModel *aiPaperMapModel;
@property (nonatomic, nullable, strong) NSView *aiChatView;
@property (nonatomic, nullable, strong) NSView *aiQuickActions;
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiQuickActionsHeightConstraint;
@property (nonatomic, nullable, copy) NSArray<NSLayoutConstraint *> *aiQuickActionConstraints;
@property (nonatomic, nullable, strong) NSTextField *aiTitleLabel, *aiSubtitleLabel, *aiContextLabel;
@property (nonatomic, nullable, strong) NSSegmentedControl *aiReadingProfileControl;
@property (nonatomic, nullable, strong) NSView *aiPaperMapCard;
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiPaperMapHeightConstraint;
@property (nonatomic, nullable, strong) PDFSelection *aiSelection;
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiTopConstraint;
// The whole OpenAI turn -- request body, streaming, delta batching, error
// mapping -- lives in the Swift core.  Non-nil only while a turn is live.
@property (nonatomic, nullable, strong) AnchoraResponsesClient *aiClient;
@property (nonatomic, nullable, strong) NSPopover *selectionActionPopover;
@property (nonatomic, nullable, strong) NSMutableString *latestAIResponse;
// A streaming turn must have a visible destination before the request starts.
// Keeping this state separately also lets us explain long PDF requests instead
// of leaving the user with an empty bubble while the model is working.
@property (nonatomic, nullable, copy) NSString *aiRequestStatus;
@property (nonatomic, nullable, copy) NSString *aiSelectionText;
@property (nonatomic, nullable, copy) NSString *aiSelectionImageDataURL;
@property (nonatomic, nullable, strong) PDFPage *aiSelectionPage;
@property (nonatomic) NSRect aiSelectionPageRect;
// The source of the in-flight / latest answer.  These deliberately do not
// change while the user keeps reading and selecting other material.
@property (nonatomic, nullable, strong) PDFSelection *aiRequestSelection;
@property (nonatomic, nullable, strong) PDFPage *aiRequestPage;
@property (nonatomic) NSRect aiRequestPageRect;
@property (nonatomic, nullable, copy) NSString *aiRequestImageDataURL;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSString *> *> *aiConversation;
@property (nonatomic, nullable, copy) NSString *aiRequestConversationUserText;
@property (nonatomic, nullable, copy) NSString *aiRequestQuestion;
// Keep the page provenance for an answer separate from the live selection.
// The user often keeps reading while a response is streaming.
@property (nonatomic, nullable, copy) NSArray<NSNumber *> *aiRequestSourcePageIndexes;
@property (nonatomic) NSUInteger aiSelectionGeneration;
@property (nonatomic) BOOL aiSelectionOCRInProgress;
@property (nonatomic) BOOL aiReceivedOutput;
@property (nonatomic) BOOL webVerificationEnabled;
@property (nonatomic) BOOL aiRequestIsPaperMap;
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
            [model beginStreamingMessageWithStatus:self.aiRequestStatus ?: @"Preparing request…"
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
        self.aiRequestStatus = status;
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

- (NSButton *)quickActionButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    // Do not use +buttonWithTitle:target:action: here.  On macOS 26 that
    // convenience factory calls -sizeToFit while the right-side controller is
    // still loading.  With Scientific mode selected, AppKit enters its
    // SwiftUI/AttributeGraph sizing bridge and can allocate indefinitely
    // before the PDF window finishes opening.  A concrete initial frame lets
    // the enclosing stack take over sizing after the view is installed.
    NSButton *actionButton = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 26.0)];
    [actionButton setTitle:title];
    [actionButton setTarget:self];
    [actionButton setAction:@selector(askAIQuickAction:)];
    [actionButton setTag:tag];
    [actionButton setBezelStyle:NSBezelStyleAccessoryBarAction];
    [actionButton setToolTip:title];
    [actionButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    return actionButton;
}

- (void)rebuildAIQuickActions {
    NSView *quickActions = self.aiQuickActions;
    if (quickActions == nil)
        return;
    [NSLayoutConstraint deactivateConstraints:self.aiQuickActionConstraints];
    self.aiQuickActionConstraints = nil;
    for (NSView *view in [[quickActions subviews] copy])
        [view removeFromSuperview];

    NSArray<NSString *> *titles = [AnchoraPrompts quickActionTitlesWithProfile:[[AnchoraSettings sharedSettings] readingProfile]];
    NSMutableArray<NSButton *> *buttons = [NSMutableArray arrayWithCapacity:[titles count]];
    for (NSUInteger index = 0; index < [titles count]; index++) {
        NSButton *actionButton = [self quickActionButtonWithTitle:titles[index] tag:index];
        if ([self isScientificReadingProfile] && index == 5)
            [actionButton setToolTip:@"Build an evidence chain: direct result, author interpretation, inference, and what remains unproven."];
        [quickActions addSubview:actionButton];
        [buttons addObject:actionButton];
    }

    // NSStackView's addArrangedSubview: is the allocation loop seen in the
    // live process sample. Direct constraints retain responsive equal-width
    // controls without entering that AppKit implementation during startup.
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    for (NSUInteger index = 0; index < [buttons count]; index++) {
        NSButton *actionButton = buttons[index];
        [constraints addObjectsFromArray:@[
            [actionButton.topAnchor constraintEqualToAnchor:quickActions.topAnchor],
            [actionButton.bottomAnchor constraintEqualToAnchor:quickActions.bottomAnchor]
        ]];
        if (index == 0) {
            [constraints addObject:[actionButton.leadingAnchor constraintEqualToAnchor:quickActions.leadingAnchor]];
        } else {
            NSButton *previous = buttons[index - 1];
            [constraints addObject:[actionButton.leadingAnchor constraintEqualToAnchor:previous.trailingAnchor constant:4.0]];
            [constraints addObject:[actionButton.widthAnchor constraintEqualToAnchor:buttons.firstObject.widthAnchor]];
        }
        if (index == [buttons count] - 1)
            [constraints addObject:[actionButton.trailingAnchor constraintEqualToAnchor:quickActions.trailingAnchor]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    self.aiQuickActionConstraints = constraints;
    [self.aiQuickActionsHeightConstraint setConstant:26.0];
}

- (void)updateAIReadingProfileInterface {
    BOOL scientific = [self isScientificReadingProfile];
    [self.aiReadingProfileControl setSelectedSegment:scientific ? 1 : 0];
    [self.aiTitleLabel setStringValue:scientific ? @"Anchora Scientific" : @"Anchora AI"];
    [self.aiSubtitleLabel setStringValue:scientific ? @"Trace the evidence behind a paper" : @"Ask about what you are reading"];
    [self.aiContextLabel setStringValue:scientific ? @"PAPER CONTEXT" : @"CONTEXT"];
    [self.aiQuestionField setPlaceholderString:scientific ? @"Ask about this paper…" : @"Ask about this selection…"];
    [self rebuildAIQuickActions];
    if ([self.aiSelectionText length] == 0 && [self.aiSelectionImageDataURL length] == 0 && self.aiSelectionOCRInProgress == NO)
        [self.aiContextTextView setString:scientific ? @"Select paper text, or capture a figure with Command-Option-drag." : @"Select text in the PDF to give AI context."];
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

    NSView *quickActions = [[NSView alloc] initWithFrame:NSZeroRect];
    [quickActions setTranslatesAutoresizingMaskIntoConstraints:NO];

    AnchoraChatModel *chatModel = [[AnchoraChatModel alloc] init];
    NSView *chatView = [AnchoraHosting chatViewWithModel:chatModel];
    [rootView addSubview:chatView];

    // Keep the action bar above the transparent chat scroll view in the view
    // hierarchy.  Constraints keep the views separated visually, but z-order
    // also determines which view receives mouse clicks during a live reflow.
    [rootView addSubview:quickActions positioned:NSWindowAbove relativeTo:chatView];

    NSVisualEffectView *composer = [self aiCardView];
    [rootView addSubview:composer];
    NSTextField *questionField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [questionField setPlaceholderString:@"Ask about this selection…"];
    [questionField setTextColor:[NSColor textColor]];
    [questionField setBackgroundColor:[NSColor clearColor]];
    [questionField setTarget:self];
    [questionField setAction:@selector(askAI:)];
    [questionField setTranslatesAutoresizingMaskIntoConstraints:NO];
    [composer addSubview:questionField];
    NSButton *askButton = [NSButton buttonWithTitle:@"Send" target:self action:@selector(askAI:)];
    [askButton setBezelStyle:NSBezelStyleRounded];
    [askButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [composer addSubview:askButton];
    NSButton *pinButton = [NSButton buttonWithTitle:@"Pin latest answer" target:self action:@selector(pinResponseToPDF:)];
    [pinButton setBezelStyle:NSBezelStyleAccessoryBarAction];
    [pinButton setEnabled:NO];
    [pinButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [composer addSubview:pinButton];
    NSButton *clearButton = [NSButton buttonWithTitle:@"Clear chat" target:self action:@selector(clearAIConversation:)];
    [clearButton setBezelStyle:NSBezelStyleAccessoryBarAction];
    [clearButton setToolTip:@"Clear this conversation and its local memory"];
    [clearButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [composer addSubview:clearButton];
    NSButton *webButton = [NSButton buttonWithTitle:@"Web verify" target:self action:@selector(toggleWebVerification:)];
    [webButton setButtonType:NSButtonTypePushOnPushOff];
    [webButton setBezelStyle:NSBezelStyleAccessoryBarAction];
    [webButton setToolTip:@"Off: answer from the PDF and general knowledge. On: search the web, verify claims, and show sources."];
    [webButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [composer addSubview:webButton];
    [NSLayoutConstraint activateConstraints:@[
        [questionField.leadingAnchor constraintEqualToAnchor:composer.leadingAnchor constant:10.0],
        [questionField.topAnchor constraintEqualToAnchor:composer.topAnchor constant:9.0],
        [questionField.trailingAnchor constraintEqualToAnchor:askButton.leadingAnchor constant:-8.0],
        [askButton.trailingAnchor constraintEqualToAnchor:composer.trailingAnchor constant:-10.0],
        [askButton.centerYAnchor constraintEqualToAnchor:questionField.centerYAnchor],
        [pinButton.leadingAnchor constraintEqualToAnchor:composer.leadingAnchor constant:8.0],
        [pinButton.topAnchor constraintEqualToAnchor:questionField.bottomAnchor constant:4.0],
        [clearButton.leadingAnchor constraintEqualToAnchor:pinButton.trailingAnchor constant:6.0],
        [clearButton.centerYAnchor constraintEqualToAnchor:pinButton.centerYAnchor],
        [webButton.trailingAnchor constraintEqualToAnchor:composer.trailingAnchor constant:-8.0],
        [webButton.centerYAnchor constraintEqualToAnchor:pinButton.centerYAnchor],
        [clearButton.trailingAnchor constraintLessThanOrEqualToAnchor:webButton.leadingAnchor constant:-6.0],
        [pinButton.bottomAnchor constraintEqualToAnchor:composer.bottomAnchor constant:-6.0]
    ]];

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
        [chatView.bottomAnchor constraintEqualToAnchor:quickActions.topAnchor constant:-8.0],
        [chatView.heightAnchor constraintGreaterThanOrEqualToConstant:120.0],
        [quickActions.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:12.0],
        [quickActions.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-12.0],
        [quickActions.bottomAnchor constraintEqualToAnchor:composer.topAnchor constant:-8.0],
        [composer.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:12.0],
        [composer.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:-12.0],
        [composer.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor constant:-12.0]
    ]];

    self.aiView = rootView;
    self.aiContextTextView = contextTextView;
    self.aiPaperMapCard = paperMapCard;
    self.aiPaperMapModel = paperMapModel;
    self.aiPaperMapHeightConstraint = [paperMapCard.heightAnchor constraintEqualToConstant:0.0];
    self.aiPaperMapHeightConstraint.priority = NSLayoutPriorityRequired;
    self.aiPaperMapHeightConstraint.active = YES;
    self.aiQuestionField = questionField;
    self.aiChatView = chatView;
    self.aiChatModel = chatModel;

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
    self.aiQuickActions = quickActions;
    self.aiQuickActionsHeightConstraint = [quickActions.heightAnchor constraintEqualToConstant:26.0];
    self.aiQuickActionsHeightConstraint.active = YES;
    self.askAIButton = askButton;
    self.pinResponseButton = pinButton;
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
    [[mainController window] makeFirstResponder:self.aiQuestionField];
}

- (void)updateSelectionContext:(NSNotification *)notification {
    SKPDFView *pdfView = [mainController pdfView];
    if ([[notification name] isEqualToString:SKPDFViewAISelectionAreaChangedNotification]) {
        [self captureAISelectionArea];
        return;
    }
    if ([[notification name] isEqualToString:SKPDFViewAIImageSelectionAreaChangedNotification]) {
        [self captureAIImageSelectionArea];
        return;
    }
    // Rectangle drags send the normal selection notification while tracking.
    // Wait for their dedicated final notification instead of clearing the
    // previous context once for every mouse-move event.
    if (NSIsEmptyRect([pdfView currentSelectionRect]) == NO && [[pdfView currentSelection] hasCharacters] == NO)
        return;
    PDFSelection *selection = [pdfView currentSelection];
    NSTextView *contextTextView = self.aiContextTextView;
    if ([selection hasCharacters]) {
        self.aiSelection = [selection copy];
        self.aiSelectionImageDataURL = nil;
        self.aiSelectionPage = nil;
        self.aiSelectionPageRect = NSZeroRect;
        self.aiSelectionGeneration += 1;
        NSString *rawText = [selection string] ?: @"";
        NSString *cleanText = [selection cleanedString] ?: @"";
        if ([self selectionNeedsOCR:rawText cleanedText:cleanText]) {
            self.aiSelectionText = nil;
            self.aiSelectionOCRInProgress = YES;
            [contextTextView setString:@"Reading selected text with OCR…"];
            [self recognizeTextForCurrentSelection:selection generation:self.aiSelectionGeneration];
        } else {
            self.aiSelectionOCRInProgress = NO;
            self.aiSelectionText = cleanText;
            [contextTextView setString:cleanText];
        }
        [self showSelectionActionsForSelection:selection];
    } else {
        self.aiSelection = nil;
        self.aiSelectionImageDataURL = nil;
        self.aiSelectionPage = nil;
        self.aiSelectionPageRect = NSZeroRect;
        self.aiSelectionText = nil;
        self.aiSelectionOCRInProgress = NO;
        self.aiSelectionGeneration += 1;
        [contextTextView setString:@"Select text in the PDF to give AI context."];
        [self.selectionActionPopover close];
    }
}

- (void)captureAISelectionArea {
    SKPDFView *pdfView = [mainController pdfView];
    PDFPage *page = [pdfView currentSelectionPage];
    NSRect pageRect = [pdfView currentSelectionRect];
    if (page == nil || NSIsEmptyRect(pageRect))
        return;
    self.aiSelection = nil;
    self.aiSelectionImageDataURL = nil;
    self.aiSelectionPage = page;
    self.aiSelectionPageRect = pageRect;
    self.aiSelectionText = nil;
    self.aiSelectionGeneration += 1;
    self.aiSelectionOCRInProgress = YES;
    [self.aiContextTextView setString:@"Reading selected area with OCR…"];
    [self.selectionActionPopover close];
    [self recognizeTextInPageRect:pageRect page:page generation:self.aiSelectionGeneration];
}

- (void)captureAIImageSelectionArea {
    SKPDFView *pdfView = [mainController pdfView];
    PDFPage *page = [pdfView currentSelectionPage];
    NSRect pageRect = [pdfView currentSelectionRect];
    if (page == nil || NSIsEmptyRect(pageRect))
        return;

    PDFDisplayBox box = [pdfView displayBox];
    NSRect pageBounds = [page boundsForBox:box];
    pageRect = NSIntersectionRect(NSInsetRect(pageRect, -3.0, -3.0), pageBounds);
    CGFloat renderScale = 2.0;
    NSInteger pixelsWide = (NSInteger)ceil(NSWidth(pageRect) * renderScale);
    NSInteger pixelsHigh = (NSInteger)ceil(NSHeight(pageRect) * renderScale);
    NSBitmapImageRep *imageRep = (pixelsWide > 0 && pixelsHigh > 0) ? [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:pixelsWide pixelsHigh:pixelsHigh bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bitmapFormat:0 bytesPerRow:0 bitsPerPixel:32] : nil;
    if (imageRep) {
        CGContextRef context = [[NSGraphicsContext graphicsContextWithBitmapImageRep:imageRep] CGContext];
        CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
        CGContextFillRect(context, CGRectMake(0.0, 0.0, pixelsWide, pixelsHigh));
        CGContextScaleCTM(context, renderScale, renderScale);
        CGContextTranslateCTM(context, -NSMinX(pageRect), -NSMinY(pageRect));
        [page drawWithBox:box toContext:context];
    }
    NSData *jpegData = [imageRep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @0.82}];
    if ([jpegData length] == 0) {
        [self.aiContextTextView setString:@"Could not capture this PDF area as an image. Try a smaller region."];
        return;
    }

    self.aiSelection = nil;
    self.aiSelectionPage = page;
    self.aiSelectionPageRect = pageRect;
    self.aiSelectionImageDataURL = [@"data:image/jpeg;base64," stringByAppendingString:[jpegData base64EncodedStringWithOptions:0]];
    self.aiSelectionText = @"A visual region of the PDF is attached.";
    self.aiSelectionOCRInProgress = NO;
    self.aiSelectionGeneration += 1;
    [self.aiContextTextView setString:@"Image ready — ask AI about this diagram, chart, or slide region."];
    [self.selectionActionPopover close];
}

- (BOOL)selectionNeedsOCR:(NSString *)rawText cleanedText:(NSString *)cleanText {
    if ([rawText length] == 0)
        return YES;
    NSUInteger removedCharacterCount = [rawText length] - [rawText.stringByRemovingAliens length];
    return removedCharacterCount > 0 && (removedCharacterCount * 3 >= [rawText length] || [cleanText length] == 0);
}

- (void)recognizeTextForCurrentSelection:(PDFSelection *)selection generation:(NSUInteger)generation {
    PDFPage *page = [[selection pages] firstObject];
    NSRect pageRect = page ? [selection boundsForPage:page] : NSZeroRect;
    [self recognizeTextInPageRect:pageRect page:page generation:generation];
}

- (void)recognizeTextInPageRect:(NSRect)pageRect page:(PDFPage *)page generation:(NSUInteger)generation {
    SKPDFView *pdfView = [mainController pdfView];
    PDFDisplayBox box = [pdfView displayBox];
    NSRect pageBounds = page ? [page boundsForBox:box] : NSZeroRect;
    // Render PDF content directly, rather than taking a screenshot of the
    // view. The latter includes Skim's dimmed selection overlay and made OCR
    // unreliable for exactly the large slide regions this feature is for.
    pageRect = NSIntersectionRect(NSInsetRect(pageRect, -3.0, -3.0), pageBounds);
    CGFloat renderScale = 2.0;
    NSInteger pixelsWide = (NSInteger)ceil(NSWidth(pageRect) * renderScale);
    NSInteger pixelsHigh = (NSInteger)ceil(NSHeight(pageRect) * renderScale);
    NSBitmapImageRep *imageRep = (page && pixelsWide > 0 && pixelsHigh > 0) ? [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:pixelsWide pixelsHigh:pixelsHigh bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bitmapFormat:0 bytesPerRow:0 bitsPerPixel:32] : nil;
    if (imageRep) {
        NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:imageRep];
        CGContextRef context = [graphicsContext CGContext];
        CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
        CGContextFillRect(context, CGRectMake(0.0, 0.0, pixelsWide, pixelsHigh));
        CGContextScaleCTM(context, renderScale, renderScale);
        CGContextTranslateCTM(context, -NSMinX(pageRect), -NSMinY(pageRect));
        [page drawWithBox:box toContext:context];
    }
    CGImageRef image = [imageRep CGImage];
    if (image == NULL) {
        [self finishOCRWithText:nil generation:generation];
        return;
    }
    CGImageRetain(image);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
        [request setRecognitionLevel:VNRequestTextRecognitionLevelAccurate];
        [request setUsesLanguageCorrection:YES];
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
        NSError *error = nil;
        BOOL success = [handler performRequests:@[request] error:&error];
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        if (success) {
            for (VNRecognizedTextObservation *observation in [request results]) {
                VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
                if ([[candidate string] length])
                    [lines addObject:[candidate string]];
            }
        }
        CGImageRelease(image);
        [self finishOCRWithText:[lines componentsJoinedByString:@" "] generation:generation];
    });
}

- (void)finishOCRWithText:(NSString *)text generation:(NSUInteger)generation {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self.aiSelectionGeneration)
            return;
        self.aiSelectionOCRInProgress = NO;
        NSString *cleanText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([cleanText length]) {
            self.aiSelectionText = cleanText;
            [self.aiContextTextView setString:cleanText];
        } else {
            self.aiSelectionText = nil;
            [self.aiContextTextView setString:@"This PDF’s text layer could not be read. OCR could not recover this selection; try selecting a larger area."];
        }
    });
}

- (IBAction)askAI:(id)sender {
    if (self.aiClient) {
        [self cancelCurrentAIRequest];
        return;
    }
    PDFSelection *selection = self.aiSelection;
    if ([selection hasCharacters] == NO && [self.aiSelectionText length] == 0 && [self.aiSelectionImageDataURL length] == 0 && self.aiSelectionOCRInProgress == NO) {
        [self updateSelectionContext:nil];
        selection = self.aiSelection;
    }
    if ([selection hasCharacters] == NO && [self.aiSelectionText length] == 0 && [self.aiSelectionImageDataURL length] == 0 && [self.aiConversation count] == 0) {
        NSBeep();
        NSString *hint = @"Select text, Option-drag for OCR, or Command-Option-drag to send an image region. After the first question, you can ask a follow-up without selecting again.";
        if ([self.aiChatModel containsText:hint] == NO)
            [self appendChatMessageFrom:SKAIAssistantName text:hint];
        [self.pinResponseButton setEnabled:NO];
        return;
    }
    if (self.aiSelectionOCRInProgress) {
        NSBeep();
        [self appendChatMessageFrom:SKAIAssistantName text:@"I’m still reading this selection with OCR. Try again in a moment."];
        return;
    }
    NSString *selectionText = self.aiSelectionText;
    NSString *question = [[self.aiQuestionField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([question length] == 0)
        question = @"Explain this";
    [self startAIRequestWithQuestion:question
                           sourceText:selectionText
                         imageDataURL:self.aiSelectionImageDataURL
                          fileDataURL:nil
                             fileName:nil
                            selection:[selection hasCharacters] ? selection : nil
                                 page:[selection hasCharacters] ? nil : self.aiSelectionPage
                             pageRect:[selection hasCharacters] ? NSZeroRect : self.aiSelectionPageRect
                       displayQuestion:question];
}

- (IBAction)askAIQuickAction:(id)sender {
    NSInteger tag = [sender tag];
    if ([self isScientificReadingProfile] == NO) {
        [self.aiQuestionField setStringValue:[AnchoraPrompts studyQuickActionPromptWithTag:tag]];
        [self askAI:sender];
        return;
    }

    if (self.aiClient) {
        [self cancelCurrentAIRequest];
        return;
    }
    NSString *question = [AnchoraPrompts scientificQuickActionPromptWithTag:tag];
    PDFSelection *selection = self.aiSelection;
    if ([selection hasCharacters] == NO && [self.aiSelectionText length] == 0 && [self.aiSelectionImageDataURL length] == 0)
        [self updateSelectionContext:nil];
    selection = self.aiSelection;
    BOOL hasDirectContext = [selection hasCharacters] || [self.aiSelectionText length] || [self.aiSelectionImageDataURL length];
    NSString *displayQuestion = [AnchoraPrompts scientificQuickActionDisplayTitleWithTag:tag];
    // Paper is always a whole-document action. The other actions use a live
    // selection when present; otherwise they remain useful by using the
    // complete paper (or the visible page for Figure).
    if (tag == 0) {
        [self startWholeDocumentRequestWithQuestion:question displayQuestion:displayQuestion];
    } else if (hasDirectContext) {
        [self.aiQuestionField setStringValue:question];
        [self askAI:sender];
    } else if (tag == 4) {
        [self analyzeCurrentPageWithQuestion:question displayQuestion:@"Analyze current page figure"];
    } else {
        [self startWholeDocumentRequestWithQuestion:question displayQuestion:displayQuestion];
    }
}

- (IBAction)toggleWebVerification:(id)sender {
    self.webVerificationEnabled = [(NSButton *)sender state] == NSControlStateValueOn;
    [(NSButton *)sender setTitle:self.webVerificationEnabled ? @"Web verify ✓" : @"Web verify"];
    [(NSButton *)sender setToolTip:self.webVerificationEnabled ? @"Web verification is on. Anchora will search for current evidence and list the sources it used." : @"Off: answer from the PDF and general knowledge. On: search the web, verify claims, and show sources."];
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
        sourcePageIndexes = self.aiRequestSourcePageIndexes ?: @[];
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
    self.aiRequestSelection = [selection hasCharacters] ? [selection copy] : nil;
    self.aiRequestPage = self.aiRequestSelection ? nil : page;
    self.aiRequestPageRect = self.aiRequestSelection ? NSZeroRect : pageRect;
    self.aiRequestImageDataURL = imageDataURL;
    self.aiRequestQuestion = displayQuestion;
    // A Paper Map is the sole full-document response rendered into the
    // navigator. All other requests remain normal chat replies.
    self.aiRequestIsPaperMap = [self isScientificReadingProfile] && [fileDataURL length] > 0 &&
        ([displayQuestion rangeOfString:@"Paper Map" options:NSCaseInsensitiveSearch].location != NSNotFound ||
         [question rangeOfString:@"Paper map" options:NSCaseInsensitiveSearch].location != NSNotFound);
    self.aiRequestSourcePageIndexes = sourcePageIndexes;
    self.aiRequestConversationUserText = [sourceText length] ? [NSString stringWithFormat:@"%@\n\nPDF context used:\n%@", displayQuestion, [sourceText substringToIndex:MIN((NSUInteger)6000, [sourceText length])]] : displayQuestion;
    [self recordAIConversationRole:@"user" text:self.aiRequestConversationUserText];
    self.aiReceivedOutput = NO;
    self.latestAIResponse = [NSMutableString string];
    self.aiRequestStatus = [fileDataURL length] ? @"Preparing the complete PDF…" : ([imageDataURL length] ? @"Preparing the image…" : @"Sending your question…");
    [self appendChatMessageFrom:@"You" text:displayQuestion];
    [self appendChatMessageFrom:SKAIAssistantName text:nil sourcePageIndexes:sourcePageIndexes];
    [self.aiQuestionField setStringValue:@""];
    [self.pinResponseButton setEnabled:NO];
    // The same control becomes Stop while a request is live.  A full-PDF
    // request can legitimately take longer than a selection, so this makes
    // the wait explicit and always escapable.
    [self.askAIButton setEnabled:YES];
    [self.askAIButton setTitle:@"Stop"];
    [self updateAIRequestStatus:[fileDataURL length] ? @"Uploading PDF to Anchora…" : ([imageDataURL length] ? @"Sending image to Anchora…" : @"Waiting for Anchora…")];

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
    if (page == nil)
        return nil;
    NSRect bounds = [page boundsForBox:box];
    CGFloat scale = 2.0;
    // Avoid producing an impractically large request for unusually large PDF pages.
    CGFloat maximumPixels = 4096.0;
    scale = MIN(scale, maximumPixels / MAX(NSWidth(bounds), NSHeight(bounds)));
    NSInteger pixelsWide = (NSInteger)ceil(NSWidth(bounds) * scale);
    NSInteger pixelsHigh = (NSInteger)ceil(NSHeight(bounds) * scale);
    if (pixelsWide <= 0 || pixelsHigh <= 0)
        return nil;
    NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:pixelsWide pixelsHigh:pixelsHigh bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bitmapFormat:0 bytesPerRow:0 bitsPerPixel:32];
    CGContextRef context = [[NSGraphicsContext graphicsContextWithBitmapImageRep:imageRep] CGContext];
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(context, CGRectMake(0.0, 0.0, pixelsWide, pixelsHigh));
    CGContextScaleCTM(context, scale, scale);
    CGContextTranslateCTM(context, -NSMinX(bounds), -NSMinY(bounds));
    [page drawWithBox:box toContext:context];
    NSData *jpegData = [imageRep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @0.9}];
    return [jpegData length] ? [@"data:image/jpeg;base64," stringByAppendingString:[jpegData base64EncodedStringWithOptions:0]] : nil;
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
    self.aiReceivedOutput = YES;
    if (self.latestAIResponse == nil)
        self.latestAIResponse = [NSMutableString string];
    [self.latestAIResponse appendString:text];
    [self.aiChatModel appendStreamedText:text];
}

- (void)finishAIRequestWithText:(NSString *)text webSources:(NSArray<NSString *> *)webSources errorMessage:(NSString *)errorMessage cancelled:(BOOL)cancelled {
    self.aiClient = nil;
    if (cancelled) {
        [self replaceStreamingPlaceholderWithText:@"Stopped. You can ask another question whenever you’re ready."];
    } else if ([errorMessage length]) {
        [self replaceStreamingPlaceholderWithText:errorMessage];
    } else {
        // Keep the complete response for Pin latest answer and memory, while
        // presenting the Paper Map itself as a compact navigator.  Do this
        // before adding web sources so the parser only sees the structured
        // paper analysis.
        if ([text length] && [self.latestAIResponse length] == 0)
            self.latestAIResponse = [text mutableCopy];
        if (self.aiRequestIsPaperMap) {
            [self presentPaperMapFromResponse:self.latestAIResponse];
            [self.aiChatModel removeStreamingMessage];
        }
        if ([webSources count]) {
            NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:[webSources count]];
            for (NSString *URLString in webSources)
                [lines addObject:[NSString stringWithFormat:@"• %@", URLString]];
            NSString *sources = [lines componentsJoinedByString:@"\n"];
            [self appendChatMessageFrom:@"Web sources" text:sources];
            [self.latestAIResponse appendFormat:@"\n\nWeb sources:\n%@", sources];
        }
        [self recordAIConversationRole:@"assistant" text:self.latestAIResponse];
        [self.aiChatModel endStreaming];
    }
    [self.pinResponseButton setEnabled:self.aiReceivedOutput && ([self.aiRequestSelection hasCharacters] || self.aiRequestPage != nil)];
    [self.askAIButton setEnabled:YES];
    [self.askAIButton setTitle:@"Send"];
    self.aiRequestStatus = nil;
    self.aiRequestIsPaperMap = NO;
}

- (void)resetAIConversationForNewDocument {
    [self.aiClient cancel];
    self.aiClient = nil;
    if (self.aiPaperMapCard)
        [AnchoraHosting updatePaperMapView:self.aiPaperMapCard model:self.aiPaperMapModel pageLabels:[self pdfPageLabels]];
    self.aiConversation = [NSMutableArray array];
    self.latestAIResponse = nil;
    self.aiRequestStatus = nil;
    self.aiRequestConversationUserText = nil;
    self.aiRequestQuestion = nil;
    self.aiRequestSourcePageIndexes = nil;
    self.aiRequestIsPaperMap = NO;
    [self clearPaperMap];
    [self.aiChatModel clear];
    [self queueWelcomeMessage];
}

- (IBAction)clearAIConversation:(id)sender {
    [self.aiClient cancel];
    self.aiClient = nil;
    self.aiConversation = [NSMutableArray array];
    self.latestAIResponse = nil;
    self.aiRequestStatus = nil;
    self.aiRequestSelection = nil;
    self.aiRequestPage = nil;
    self.aiRequestPageRect = NSZeroRect;
    self.aiRequestImageDataURL = nil;
    self.aiRequestConversationUserText = nil;
    self.aiRequestQuestion = nil;
    self.aiRequestSourcePageIndexes = nil;
    self.aiReceivedOutput = NO;
    self.aiRequestIsPaperMap = NO;
    [self clearPaperMap];
    [self.aiChatModel clear];
    [self.pinResponseButton setEnabled:NO];
    [self.askAIButton setEnabled:YES];
    [self.askAIButton setTitle:@"Send"];
}

- (IBAction)pinResponseToPDF:(id)sender {
    PDFSelection *selection = self.aiRequestSelection;
    // A PDF note holds plain text, and it has to stay readable in other PDF
    // apps too, so the answer's Markdown is flattened rather than pinned raw.
    NSString *response = [self.latestAIResponse length] ? [AnchoraMarkdown plainTextFrom:self.latestAIResponse] : nil;
    if ([response length] == 0) {
        NSBeep();
        return;
    }
    if ([selection hasCharacters])
        [mainController pinAIResponse:response title:self.aiRequestQuestion forSelection:selection];
    else if (self.aiRequestPage)
        [mainController pinAIResponse:response title:self.aiRequestQuestion nearRect:self.aiRequestPageRect onPage:self.aiRequestPage];
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
