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
#import "SKKeychain.h"
#import <Vision/Vision.h>

static NSString * const SKOpenAIKeychainService = @"Anchora.OpenAI";
static NSString * const SKLegacyOpenAIKeychainService = @"PDFBuddy.OpenAI";
static NSString * const SKOpenAIKeychainAccount = @"APIKey";
static NSString * const SKOpenAIModel = @"gpt-5-mini";
static NSString * const SKAIAssistantName = @"Anchora";

@interface SKRightSideViewController () <NSURLSessionDataDelegate>
@property (nonatomic, nullable, strong) NSTextView *aiContextTextView;
@property (nonatomic, nullable, strong) NSTextField *aiQuestionField;
@property (nonatomic, nullable, strong) NSButton *askAIButton, *pinResponseButton, *webVerificationButton;
@property (nonatomic, nullable, strong) NSScrollView *aiChatScrollView;
@property (nonatomic, nullable, strong) NSStackView *aiMessageStack;
@property (nonatomic, nullable, strong) NSTextField *aiStreamingMessageField;
@property (nonatomic, nullable, strong) NSMutableString *aiRenderedChatText;
@property (nonatomic, nullable, strong) PDFSelection *aiSelection;
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiTopConstraint;
@property (nonatomic, nullable, strong) NSURLSession *aiSession;
@property (nonatomic, nullable, strong) NSURLSessionDataTask *aiTask;
@property (nonatomic, nullable, strong) NSMutableData *aiEventData;
@property (nonatomic, nullable, strong) NSPopover *selectionActionPopover;
@property (nonatomic, nullable, strong) NSMutableString *latestAIResponse;
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
@property (nonatomic) NSUInteger aiSelectionGeneration;
@property (nonatomic) BOOL aiSelectionOCRInProgress;
@property (nonatomic) BOOL aiReceivedOutput;
@property (nonatomic) BOOL webVerificationEnabled;
@property (nonatomic, nullable, strong) NSMutableOrderedSet<NSString *> *aiWebSourceURLs;
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

- (NSTextField *)chatLabelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:string ?: @""];
    [label setFont:font];
    [label setTextColor:color];
    [label setLineBreakMode:NSLineBreakByWordWrapping];
    [label setUsesSingleLineMode:NO];
    [label setMaximumNumberOfLines:0];
    [label setSelectable:YES];
    [label setTranslatesAutoresizingMaskIntoConstraints:NO];
    return label;
}

- (void)refreshChatLayoutAndScrollToBottom:(BOOL)scrollToBottom {
    NSStackView *stack = self.aiMessageStack;
    NSScrollView *scrollView = self.aiChatScrollView;
    if (stack == nil || scrollView == nil)
        return;
    CGFloat width = MAX(1.0, NSWidth([[scrollView contentView] bounds]));
    [stack setFrameSize:NSMakeSize(width, 1.0)];
    [stack layoutSubtreeIfNeeded];
    NSSize fittingSize = [stack fittingSize];
    [stack setFrameSize:NSMakeSize(width, MAX(1.0, fittingSize.height))];
    [stack layoutSubtreeIfNeeded];
    if (scrollToBottom) {
        NSClipView *clipView = [scrollView contentView];
        CGFloat y = MAX(0.0, NSHeight([stack frame]) - NSHeight([clipView bounds]));
        [clipView scrollToPoint:NSMakePoint(0.0, y)];
        [scrollView reflectScrolledClipView:clipView];
    }
}

- (void)clearRenderedChat {
    for (NSView *messageView in [[self.aiMessageStack arrangedSubviews] copy]) {
        [self.aiMessageStack removeArrangedSubview:messageView];
        [messageView removeFromSuperview];
    }
    self.aiStreamingMessageField = nil;
    self.aiRenderedChatText = [NSMutableString string];
    [self refreshChatLayoutAndScrollToBottom:NO];
}

- (void)appendChatMessageFrom:(NSString *)sender text:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.aiMessageStack == nil)
            return;
        BOOL isUser = [sender isEqualToString:@"You"];
        NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
        [row setTranslatesAutoresizingMaskIntoConstraints:NO];
        NSVisualEffectView *bubble = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
        [bubble setMaterial:isUser ? NSVisualEffectMaterialSelection : NSVisualEffectMaterialContentBackground];
        [bubble setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
        [bubble setState:NSVisualEffectStateActive];
        [bubble setWantsLayer:YES];
        [[bubble layer] setCornerRadius:14.0];
        [[bubble layer] setMasksToBounds:YES];
        [bubble setTranslatesAutoresizingMaskIntoConstraints:NO];
        [row addSubview:bubble];

        NSColor *bodyColor = isUser ? [NSColor selectedTextColor] : [NSColor labelColor];
        NSColor *senderColor = isUser ? [[NSColor selectedTextColor] colorWithAlphaComponent:0.82] : [NSColor secondaryLabelColor];
        NSTextField *senderLabel = [self chatLabelWithString:sender font:[NSFont boldSystemFontOfSize:10.0] color:senderColor];
        NSTextField *bodyLabel = [self chatLabelWithString:text font:[NSFont systemFontOfSize:13.5] color:bodyColor];
        [bodyLabel setPreferredMaxLayoutWidth:270.0];
        [bubble addSubview:senderLabel];
        [bubble addSubview:bodyLabel];
        [NSLayoutConstraint activateConstraints:@[
            [senderLabel.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:12.0],
            [senderLabel.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-12.0],
            [senderLabel.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:8.0],
            [bodyLabel.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:12.0],
            [bodyLabel.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-12.0],
            [bodyLabel.topAnchor constraintEqualToAnchor:senderLabel.bottomAnchor constant:3.0],
            [bodyLabel.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-9.0],
            [bubble.topAnchor constraintEqualToAnchor:row.topAnchor],
            [bubble.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [bubble.widthAnchor constraintLessThanOrEqualToAnchor:row.widthAnchor multiplier:0.84],
            isUser ? [bubble.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8.0] : [bubble.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:8.0]
        ]];
        [self.aiMessageStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:self.aiMessageStack.widthAnchor].active = YES;
        if (text == nil)
            self.aiStreamingMessageField = bodyLabel;
        if ([text length])
            [self.aiRenderedChatText appendFormat:@"%@\n", text];
        [self refreshChatLayoutAndScrollToBottom:YES];
    });
}

- (void)buildAIInterface {
    NSVisualEffectView *aiView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [aiView setMaterial:NSVisualEffectMaterialSidebar];
    [aiView setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [aiView setState:NSVisualEffectStateFollowsWindowActiveState];
    [aiView setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSStackView *header = [[NSStackView alloc] initWithFrame:NSZeroRect];
    [header setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [header setAlignment:NSLayoutAttributeLeading];
    [header setSpacing:8.0];
    [header setTranslatesAutoresizingMaskIntoConstraints:NO];
    [aiView addSubview:header];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:aiView.leadingAnchor constant:16.0],
        [header.trailingAnchor constraintEqualToAnchor:aiView.trailingAnchor constant:-16.0]
    ]];
    self.aiTopConstraint = [header.topAnchor constraintEqualToAnchor:aiView.topAnchor constant:12.0];
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
    NSStackView *titleRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    [titleRow setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [titleRow setAlignment:NSLayoutAttributeTop];
    [titleRow addArrangedSubview:titleStack];
    NSView *titleSpacer = [NSView new];
    [titleSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [titleRow addArrangedSubview:titleSpacer];
    NSButton *moreButton = [NSButton buttonWithTitle:@"•••" target:self action:@selector(showAIMoreActions:)];
    [moreButton setBezelStyle:NSBezelStyleAccessoryBarAction];
    [moreButton setToolTip:@"PDF summary and API settings"];
    [titleRow addArrangedSubview:moreButton];
    [header addArrangedSubview:titleRow];

    NSVisualEffectView *contextCard = [self aiCardView];
    [aiView addSubview:contextCard];
    NSTextField *contextLabel = [NSTextField labelWithString:@"CONTEXT"];
    [contextLabel setTextColor:[NSColor secondaryLabelColor]];
    [contextLabel setFont:[NSFont boldSystemFontOfSize:10.0]];
    [contextLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [contextCard addSubview:contextLabel];
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

    NSStackView *quickActions = [[NSStackView alloc] initWithFrame:NSZeroRect];
    [quickActions setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [quickActions setAlignment:NSLayoutAttributeCenterY];
    [quickActions setDistribution:NSStackViewDistributionFillEqually];
    [quickActions setSpacing:6.0];
    [quickActions setTranslatesAutoresizingMaskIntoConstraints:NO];
    NSArray<NSString *> *quickActionTitles = @[@"Explain · EN", @"解釋 · 中文", @"Translate", @"Clinical"];
    for (NSUInteger index = 0; index < [quickActionTitles count]; index++) {
        NSButton *quickAction = [NSButton buttonWithTitle:quickActionTitles[index] target:self action:@selector(askAIQuickAction:)];
        [quickAction setTag:index];
        [quickAction setBezelStyle:NSBezelStyleAccessoryBarAction];
        [quickActions addArrangedSubview:quickAction];
    }
    [aiView addSubview:quickActions];

    NSScrollView *chatScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [chatScrollView setBorderType:NSNoBorder];
    [chatScrollView setHasVerticalScroller:YES];
    [chatScrollView setAutohidesScrollers:YES];
    [chatScrollView setDrawsBackground:NO];
    [chatScrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
    NSStackView *messageStack = [[NSStackView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1.0, 1.0)];
    [messageStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [messageStack setAlignment:NSLayoutAttributeLeading];
    [messageStack setDistribution:NSStackViewDistributionFill];
    [messageStack setSpacing:9.0];
    [messageStack setEdgeInsets:NSEdgeInsetsMake(10.0, 0.0, 10.0, 0.0)];
    [messageStack setAutoresizingMask:NSViewWidthSizable];
    [chatScrollView setDocumentView:messageStack];
    [aiView addSubview:chatScrollView];

    NSVisualEffectView *composer = [self aiCardView];
    [aiView addSubview:composer];
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
        [contextCard.leadingAnchor constraintEqualToAnchor:aiView.leadingAnchor constant:12.0],
        [contextCard.trailingAnchor constraintEqualToAnchor:aiView.trailingAnchor constant:-12.0],
        [contextCard.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10.0],
        [contextCard.heightAnchor constraintEqualToConstant:86.0],
        [chatScrollView.leadingAnchor constraintEqualToAnchor:aiView.leadingAnchor constant:8.0],
        [chatScrollView.trailingAnchor constraintEqualToAnchor:aiView.trailingAnchor constant:-8.0],
        [chatScrollView.topAnchor constraintEqualToAnchor:contextCard.bottomAnchor constant:8.0],
        [chatScrollView.bottomAnchor constraintEqualToAnchor:quickActions.topAnchor constant:-8.0],
        [chatScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:120.0],
        [quickActions.leadingAnchor constraintEqualToAnchor:aiView.leadingAnchor constant:12.0],
        [quickActions.trailingAnchor constraintEqualToAnchor:aiView.trailingAnchor constant:-12.0],
        [quickActions.bottomAnchor constraintEqualToAnchor:composer.topAnchor constant:-8.0],
        [quickActions.heightAnchor constraintEqualToConstant:26.0],
        [composer.leadingAnchor constraintEqualToAnchor:aiView.leadingAnchor constant:12.0],
        [composer.trailingAnchor constraintEqualToAnchor:aiView.trailingAnchor constant:-12.0],
        [composer.bottomAnchor constraintEqualToAnchor:aiView.bottomAnchor constant:-12.0]
    ]];

    self.aiView = aiView;
    self.aiContextTextView = contextTextView;
    self.aiQuestionField = questionField;
    self.aiChatScrollView = chatScrollView;
    self.aiMessageStack = messageStack;
    self.aiRenderedChatText = [NSMutableString string];
    self.askAIButton = askButton;
    self.pinResponseButton = pinButton;
    self.webVerificationButton = webButton;
    [self appendChatMessageFrom:SKAIAssistantName text:@"Select text, Option-drag for OCR, or Command-Option-drag to send an image region. Your conversation stays here while the PDF remains in view."];
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
    NSButton *button = (NSButton *)sender;
    [button setTag:SKHighlightNote];
    [mainController createNewNote:button];
}

- (IBAction)addTextNoteFromSelection:(id)sender {
    [self.selectionActionPopover close];
    NSButton *button = (NSButton *)sender;
    [button setTag:SKFreeTextNote];
    [mainController createNewNote:button];
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
    SKPDFView *pdfView = [mainController pdfView];
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
    PDFSelection *selection = self.aiSelection;
    if ([selection hasCharacters] == NO && [self.aiSelectionText length] == 0 && [self.aiSelectionImageDataURL length] == 0 && self.aiSelectionOCRInProgress == NO) {
        [self updateSelectionContext:nil];
        selection = self.aiSelection;
    }
    if ([selection hasCharacters] == NO && [self.aiSelectionText length] == 0 && [self.aiSelectionImageDataURL length] == 0 && [self.aiConversation count] == 0) {
        NSBeep();
        NSString *hint = @"Select text, Option-drag for OCR, or Command-Option-drag to send an image region. After the first question, you can ask a follow-up without selecting again.";
        if ([self.aiRenderedChatText containsString:hint] == NO)
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
    switch ([sender tag]) {
        case 1:
            [self.aiQuestionField setStringValue:@"用繁體中文清楚、逐步解釋這段內容，幫助我理解和複習；保留必要的英文專有名詞並在括號中標示。"];
            break;
        case 2:
            [self.aiQuestionField setStringValue:@"Translate this into Traditional Chinese. Preserve essential English technical terms in parentheses."];
            break;
        case 3:
            [self.aiQuestionField setStringValue:@"Explain the clinical relevance and practical implications of this." ];
            break;
        default:
            [self.aiQuestionField setStringValue:@"Explain this clearly in English, step by step, for study."];
            break;
    }
    [self askAI:sender];
}

- (IBAction)toggleWebVerification:(id)sender {
    self.webVerificationEnabled = [(NSButton *)sender state] == NSControlStateValueOn;
    [(NSButton *)sender setTitle:self.webVerificationEnabled ? @"Web verify ✓" : @"Web verify"];
    [(NSButton *)sender setToolTip:self.webVerificationEnabled ? @"Web verification is on. Anchora will search for current evidence and list the sources it used." : @"Off: answer from the PDF and general knowledge. On: search the web, verify claims, and show sources."];
}

- (IBAction)showAIMoreActions:(id)sender {
    NSMenu *menu = [NSMenu menu];
    [menu addItemWithTitle:@"Summarize This Page" action:@selector(summarizeCurrentPage:) target:self];
    [menu addItemWithTitle:@"Summarize This PDF" action:@selector(summarizeDocument:) target:self];
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

- (NSString *)storedOpenAIAPIKeyWithStatus:(SKPasswordStatus *)status {
    SKPasswordStatus currentStatus = SKPasswordStatusNotFound;
    NSString *key = [SKKeychain passwordForService:SKOpenAIKeychainService account:SKOpenAIKeychainAccount status:&currentStatus];
    if ([key length]) {
        if (status)
            *status = currentStatus;
        return key;
    }

    // Preserve the API key entered before the PDFBuddy -> Anchora rename.
    SKPasswordStatus legacyStatus = SKPasswordStatusNotFound;
    NSString *legacyKey = [SKKeychain passwordForService:SKLegacyOpenAIKeychainService account:SKOpenAIKeychainAccount status:&legacyStatus];
    if ([legacyKey length]) {
        [SKKeychain setPassword:legacyKey forService:SKOpenAIKeychainService account:SKOpenAIKeychainAccount label:@"Anchora OpenAI API Key" comment:@"Used only for Anchora AI requests"];
        if (status)
            *status = SKPasswordStatusFound;
        return legacyKey;
    }
    if (status)
        *status = currentStatus;
    return nil;
}

- (void)startAIRequestWithQuestion:(NSString *)question sourceText:(NSString *)sourceText imageDataURL:(NSString *)imageDataURL fileDataURL:(NSString *)fileDataURL fileName:(NSString *)fileName selection:(PDFSelection *)selection page:(PDFPage *)page pageRect:(NSRect)pageRect displayQuestion:(NSString *)displayQuestion {
    SKPasswordStatus status = SKPasswordStatusNotFound;
    NSString *apiKey = [self storedOpenAIAPIKeyWithStatus:&status];
    if ([apiKey length] == 0) {
        if ([self configureOpenAIAPIKey:nil] == NO)
            return;
        apiKey = [self storedOpenAIAPIKeyWithStatus:&status];
        if ([apiKey length] == 0)
            return;
    }

    NSString *prompt = [sourceText length] ? [NSString stringWithFormat:@"PDF context:\n%@\n\nQuestion: %@", sourceText, question] : [NSString stringWithFormat:@"Question: %@", question];
    NSMutableArray *content = [NSMutableArray arrayWithObject:@{ @"type": @"input_text", @"text": prompt }];
    if ([imageDataURL length])
        [content addObject:@{ @"type": @"input_image", @"image_url": imageDataURL, @"detail": @"high" }];
    if ([fileDataURL length])
        [content addObject:@{ @"type": @"input_file", @"filename": fileName ?: @"document.pdf", @"file_data": fileDataURL, @"detail": @"high" }];
    NSMutableArray *input = [[self conversationInputItems] mutableCopy];
    [input addObject:@{ @"role": @"user", @"content": content }];
    NSString *instructions = @"You are Anchora, a concise study assistant. Treat supplied PDF context as the primary source for questions about this document. You may also use reliable general knowledge when it helps answer the user's question. Clearly distinguish claims supported by the PDF from your additional explanation; do not invent PDF citations or claim the PDF says something it does not. Cite page labels only for claims grounded in the supplied PDF. Match the user's language when possible. Continue the current PDF conversation naturally.";
    if (self.webVerificationEnabled)
        instructions = [instructions stringByAppendingString:@" Web verification is enabled. Before answering, always use web search at least once to check relevant factual or current claims. Prefer primary and authoritative sources. Clearly distinguish PDF-grounded claims, web-verified claims, and your own explanation. Never invent a source or citation."];
    NSMutableDictionary *body = [@{
        @"model": SKOpenAIModel,
        @"stream": @YES,
        @"store": @NO,
        @"instructions": instructions,
        @"input": input
    } mutableCopy];
    if (self.webVerificationEnabled) {
        body[@"tools"] = @[@{ @"type": @"web_search", @"search_context_size": @"medium" }];
        body[@"include"] = @[@"web_search_call.action.sources"];
    }
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (bodyData == nil) {
        [self appendChatMessageFrom:SKAIAssistantName text:[NSString stringWithFormat:@"Could not prepare the AI request: %@", [jsonError localizedDescription]]];
        [self.askAIButton setEnabled:YES];
        [self.askAIButton setTitle:@"Send"];
        return;
    }
    [self.aiTask cancel];
    [self.aiSession invalidateAndCancel];
    self.aiRequestSelection = [selection hasCharacters] ? [selection copy] : nil;
    self.aiRequestPage = self.aiRequestSelection ? nil : page;
    self.aiRequestPageRect = self.aiRequestSelection ? NSZeroRect : pageRect;
    self.aiRequestImageDataURL = imageDataURL;
    self.aiRequestQuestion = displayQuestion;
    self.aiRequestConversationUserText = [sourceText length] ? [NSString stringWithFormat:@"%@\n\nPDF context used:\n%@", displayQuestion, [sourceText substringToIndex:MIN((NSUInteger)6000, [sourceText length])]] : displayQuestion;
    [self recordAIConversationRole:@"user" text:self.aiRequestConversationUserText];
    self.aiReceivedOutput = NO;
    self.aiWebSourceURLs = [NSMutableOrderedSet orderedSet];
    self.aiEventData = [NSMutableData data];
    self.latestAIResponse = [NSMutableString string];
    [self appendChatMessageFrom:@"You" text:displayQuestion];
    [self appendChatMessageFrom:SKAIAssistantName text:nil];
    [self.aiQuestionField setStringValue:@""];
    [self.pinResponseButton setEnabled:NO];
    [self.askAIButton setEnabled:NO];
    [self.askAIButton setTitle:@"Thinking…"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.openai.com/v1/responses"]];
    [request setHTTPMethod:@"POST"];
    [request setTimeoutInterval:90.0];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    [request setHTTPBody:bodyData];

    self.aiSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
    self.aiTask = [self.aiSession dataTaskWithRequest:request];
    [self.aiTask resume];
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
    [self startAIRequestWithQuestion:@"Study this complete PDF page, including diagrams, tables, figures, and layout. Summarize the key ideas, important terms, and 3 concise takeaways."
                           sourceText:@"A complete rendered image of this PDF page is attached."
                         imageDataURL:pageImageDataURL
                          fileDataURL:nil
                             fileName:nil
                            selection:nil page:page pageRect:[page boundsForBox:box]
                       displayQuestion:[NSString stringWithFormat:@"Summarize page %lu", (unsigned long)pageNumber]];
}

- (IBAction)summarizeDocument:(id)sender {
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
    [self startAIRequestWithQuestion:@"Create a study-oriented summary of this complete PDF. Use both its text and visuals. Organize it by topic, identify core concepts and high-yield details, and finish with a short review checklist. Cite page numbers for major sections."
                           sourceText:@"The complete original PDF is attached."
                         imageDataURL:nil
                          fileDataURL:fileDataURL
                             fileName:fileName
                            selection:nil page:page pageRect:[page boundsForBox:[[mainController pdfView] displayBox]]
                       displayQuestion:@"Summarize this PDF"];
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
    SKPasswordStatus status = SKPasswordStatusNotFound;
    [self storedOpenAIAPIKeyWithStatus:&status];
    if (status == SKPasswordStatusFound) {
        [SKKeychain updatePassword:key service:SKOpenAIKeychainService account:SKOpenAIKeychainAccount label:@"Anchora OpenAI API Key" comment:@"Used only for Anchora AI requests" forService:SKOpenAIKeychainService account:SKOpenAIKeychainAccount];
    } else {
        [SKKeychain setPassword:key forService:SKOpenAIKeychainService account:SKOpenAIKeychainAccount label:@"Anchora OpenAI API Key" comment:@"Used only for Anchora AI requests"];
    }
    return YES;
}

- (void)appendAIText:(NSString *)text {
    if ([text length] == 0)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.aiReceivedOutput = YES;
        if (self.latestAIResponse == nil)
            self.latestAIResponse = [NSMutableString string];
        [self.latestAIResponse appendString:text];
        NSTextField *streamingMessage = self.aiStreamingMessageField;
        if (streamingMessage) {
            [streamingMessage setStringValue:[[streamingMessage stringValue] stringByAppendingString:text]];
            [self.aiRenderedChatText appendString:text];
            [self refreshChatLayoutAndScrollToBottom:YES];
        }
    });
}

- (void)collectWebSourcesFromObject:(id)object {
    if ([object isKindOfClass:[NSDictionary class]]) {
        id sources = object[@"sources"];
        if ([sources isKindOfClass:[NSArray class]]) {
            for (id source in sources) {
                NSString *URLString = [source isKindOfClass:[NSDictionary class]] ? source[@"url"] : ([source isKindOfClass:[NSString class]] ? source : nil);
                if ([URLString isKindOfClass:[NSString class]] && [URLString length])
                    [self.aiWebSourceURLs addObject:URLString];
            }
        }
        for (id value in [(NSDictionary *)object allValues])
            [self collectWebSourcesFromObject:value];
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)object)
            [self collectWebSourcesFromObject:value];
    }
}

- (NSString *)webSourcesText {
    if ([self.aiWebSourceURLs count] == 0)
        return nil;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *URLString in self.aiWebSourceURLs)
        [lines addObject:[NSString stringWithFormat:@"• %@", URLString]];
    return [lines componentsJoinedByString:@"\n"];
}

- (void)consumeAIEvents {
    NSData *separator = [@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range;
    while ((range = [self.aiEventData rangeOfData:separator options:0 range:NSMakeRange(0, [self.aiEventData length])]).location != NSNotFound) {
        NSData *eventData = [self.aiEventData subdataWithRange:NSMakeRange(0, range.location)];
        [self.aiEventData replaceBytesInRange:NSMakeRange(0, NSMaxRange(range)) withBytes:NULL length:0];
        NSString *event = [[NSString alloc] initWithData:eventData encoding:NSUTF8StringEncoding];
        __block NSString *jsonString = nil;
        [event enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            if ([line hasPrefix:@"data: "])
                jsonString = [line substringFromIndex:6];
        }];
        if ([jsonString length] == 0 || [jsonString isEqualToString:@"[DONE]"])
            continue;
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *message = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
        if ([message isKindOfClass:[NSDictionary class]] == NO)
            continue;
        [self collectWebSourcesFromObject:message];
        NSString *type = message[@"type"];
        if ([type isEqualToString:@"response.output_text.delta"])
            [self appendAIText:message[@"delta"]];
        else if ([type isEqualToString:@"error"])
            [self appendChatMessageFrom:SKAIAssistantName text:[NSString stringWithFormat:@"OpenAI error: %@", message[@"message"] ?: @"Unknown error"]];
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (dataTask != self.aiTask)
        return;
    [self.aiEventData appendData:data];
    [self consumeAIEvents];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (task != self.aiTask)
        return;
    NSInteger statusCode = [(NSHTTPURLResponse *)[task response] statusCode];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (error && error.code != NSURLErrorCancelled)
            [self appendChatMessageFrom:SKAIAssistantName text:[NSString stringWithFormat:@"Network error: %@", [error localizedDescription]]];
        else if (self.aiReceivedOutput == NO)
            [self appendChatMessageFrom:SKAIAssistantName text:statusCode >= 400 ? [NSString stringWithFormat:@"OpenAI request failed (HTTP %ld). Check your API key, billing, and model access.", (long)statusCode] : @"No text was returned by OpenAI."];
        else {
            NSString *sources = [self webSourcesText];
            if ([sources length]) {
                [self appendChatMessageFrom:@"Web sources" text:sources];
                [self.latestAIResponse appendFormat:@"\n\nWeb sources:\n%@", sources];
            }
            [self recordAIConversationRole:@"assistant" text:self.latestAIResponse];
        }
        [self.pinResponseButton setEnabled:self.aiReceivedOutput && ([self.aiRequestSelection hasCharacters] || self.aiRequestPage != nil)];
        [self.askAIButton setEnabled:YES];
        [self.askAIButton setTitle:@"Send"];
    });
    [session finishTasksAndInvalidate];
    self.aiTask = nil;
    self.aiSession = nil;
}

- (void)resetAIConversationForNewDocument {
    [self.aiTask cancel];
    [self.aiSession invalidateAndCancel];
    self.aiTask = nil;
    self.aiSession = nil;
    self.aiConversation = [NSMutableArray array];
    self.latestAIResponse = nil;
    self.aiRequestConversationUserText = nil;
    self.aiRequestQuestion = nil;
    [self clearRenderedChat];
    [self appendChatMessageFrom:SKAIAssistantName text:@"New PDF conversation. Select text, ask a question, or use This Page / PDF Summary to start building context."];
}

- (IBAction)clearAIConversation:(id)sender {
    [self.aiTask cancel];
    [self.aiSession invalidateAndCancel];
    self.aiTask = nil;
    self.aiSession = nil;
    self.aiConversation = [NSMutableArray array];
    self.latestAIResponse = nil;
    self.aiRequestSelection = nil;
    self.aiRequestPage = nil;
    self.aiRequestPageRect = NSZeroRect;
    self.aiRequestImageDataURL = nil;
    self.aiRequestConversationUserText = nil;
    self.aiRequestQuestion = nil;
    self.aiReceivedOutput = NO;
    [self clearRenderedChat];
    [self.pinResponseButton setEnabled:NO];
    [self.askAIButton setEnabled:YES];
    [self.askAIButton setTitle:@"Send"];
}

- (IBAction)pinResponseToPDF:(id)sender {
    PDFSelection *selection = self.aiRequestSelection;
    NSString *response = self.latestAIResponse;
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
