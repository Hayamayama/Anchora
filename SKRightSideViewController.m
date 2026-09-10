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
static NSString * const SKDefaultOpenAIModel = @"gpt-5-mini";
static NSString * const SKAIAssistantName = @"Anchora";
static NSString * const SKAIReadingProfileDefaultsKey = @"Anchora.AIReadingProfile";
static NSString * const SKAIResponseLanguageDefaultsKey = @"Anchora.AIResponseLanguage";
static NSString * const SKAIModelDefaultsKey = @"Anchora.AIModel";
// The earlier 2,400-token ceiling was a temporary guard while the streaming
// UI was being stabilized.  A paper map needs room for methods, results,
// figures, caveats, and page citations; its renderer is now throttled.
static const NSUInteger SKAIStandardMaximumOutputTokens = 8000;
static const NSUInteger SKAIPaperMapMaximumOutputTokens = 16000;

static NSArray<NSDictionary<NSString *, NSString *> *> *SKPaperMapSectionDefinitions(void) {
    return @[
        @{ @"title": @"Research problem and gap", @"pattern": @"Research\\s+problem\\s+and\\s+(?:knowledge\\s+)?gap" },
        @{ @"title": @"Objective", @"pattern": @"Objective" },
        @{ @"title": @"Main hypothesis / research question", @"pattern": @"Main\\s+hypothesis\\s*/\\s*research\\s+question" },
        @{ @"title": @"Study and experimental methods", @"pattern": @"Study\\s+and\\s+experimental\\s+methods" },
        @{ @"title": @"Key figures and evidence", @"pattern": @"Key\\s+figures\\s+and\\s+evidence" },
        @{ @"title": @"What the paper directly demonstrates", @"pattern": @"What\\s+the\\s+paper\\s+directly\\s+demonstrates" },
        @{ @"title": @"Authors’ interpretation", @"pattern": @"Authors?[’']?\\s*interpretation" },
        @{ @"title": @"Limitations and unanswered questions", @"pattern": @"Limitations?(?:,\\s*alternative\\s+explanations?,?\\s*and)?\\s*(?:what\\s+remains\\s+)?(?:unanswered\\s+questions?|unproven)?" },
    ];
}

typedef NS_ENUM(NSInteger, SKAIReadingProfile) {
    SKAIReadingProfileStudy = 0,
    SKAIReadingProfileScientific = 1,
};

typedef NS_ENUM(NSInteger, SKAIResponseLanguage) {
    SKAIResponseLanguageTraditionalChinese = 0,
    SKAIResponseLanguageEnglish = 1,
};

@interface SKRightSideViewController () <NSURLSessionDataDelegate, NSTextViewDelegate>
@property (nonatomic, nullable, strong) NSTextView *aiContextTextView;
@property (nonatomic, nullable, strong) NSTextField *aiQuestionField;
@property (nonatomic, nullable, strong) NSButton *askAIButton, *pinResponseButton, *webVerificationButton;
@property (nonatomic, nullable, strong) NSScrollView *aiChatScrollView;
@property (nonatomic, nullable, strong) NSStackView *aiMessageStack;
@property (nonatomic) BOOL aiRefreshingChatLayout;
@property (nonatomic) BOOL aiWelcomeMessagePending;
@property (nonatomic, nullable, strong) NSView *aiQuickActions;
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiQuickActionsHeightConstraint;
@property (nonatomic, nullable, copy) NSArray<NSLayoutConstraint *> *aiQuickActionConstraints;
@property (nonatomic, nullable, strong) NSTextField *aiTitleLabel, *aiSubtitleLabel, *aiContextLabel;
@property (nonatomic, nullable, strong) NSSegmentedControl *aiReadingProfileControl;
@property (nonatomic, nullable, strong) NSVisualEffectView *aiPaperMapCard;
@property (nonatomic, nullable, strong) NSPopUpButton *aiPaperMapSectionControl, *aiPaperMapSourceControl;
@property (nonatomic, nullable, strong) NSTextView *aiPaperMapDetailTextView;
@property (nonatomic, nullable, strong) NSButton *aiPaperMapToggleButton;
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiPaperMapHeightConstraint;
@property (nonatomic, nullable, copy) NSArray<NSDictionary<NSString *, id> *> *aiPaperMapSections;
@property (nonatomic, nullable, strong) NSTextField *aiStreamingMessageField;
@property (nonatomic, nullable, strong) NSMutableString *aiRenderedChatText;
@property (nonatomic, nullable, strong) PDFSelection *aiSelection;
@property (nonatomic, nullable, strong) NSLayoutConstraint *aiTopConstraint;
@property (nonatomic, nullable, strong) NSURLSession *aiSession;
@property (nonatomic, nullable, strong) NSURLSessionDataTask *aiTask;
@property (nonatomic, nullable, strong) NSMutableData *aiEventData;
@property (nonatomic, nullable, strong) NSPopover *selectionActionPopover;
@property (nonatomic, nullable, strong) NSMutableString *latestAIResponse;
@property (nonatomic, nullable, strong) NSMutableString *aiPendingStreamText;
@property (nonatomic) BOOL aiStreamRenderScheduled;
// A streaming turn must have a visible destination before the request starts.
// Keeping this state separately also lets us explain long PDF requests instead
// of leaving the user with an empty bubble while the model is working.
@property (nonatomic, nullable, copy) NSString *aiRequestStatus;
@property (nonatomic) BOOL aiStreamingPlaceholderVisible;
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
@property (nonatomic) SKAIReadingProfile aiReadingProfile;
@property (nonatomic) SKAIResponseLanguage aiResponseLanguage;
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
    if (stack == nil || scrollView == nil || self.aiRefreshingChatLayout)
        return;

    // During document opening the side pane is often not in a window yet, so
    // its clip view reports a zero/one-point width.  Asking an NSStackView to
    // compute fittingSize at that moment creates a circular measurement:
    // stack width -> wrapped bubble height -> stack fittingSize -> document
    // view frame -> stack width.  It can spin indefinitely and consume GBs.
    CGFloat width = floor(NSWidth([[scrollView contentView] bounds]));
    if (width < 80.0 || isfinite(width) == NO)
        return;

    self.aiRefreshingChatLayout = YES;
    CGFloat currentHeight = MAX(20.0, NSHeight([stack frame]));
    [stack setFrameSize:NSMakeSize(width, currentHeight)];
    [stack layoutSubtreeIfNeeded];

    // The first layout gives each bubble its true sidebar width.  Recompute
    // only the message labels at that width, then lay out again so wrapped
    // streamed text contributes its full intrinsic height to the row.
    for (NSView *row in [stack arrangedSubviews]) {
        for (NSView *bubble in [row subviews]) {
            for (NSView *view in [bubble subviews]) {
                if ([view isKindOfClass:[NSTextField class]] && [view tag] == 1) {
                    NSTextField *body = (NSTextField *)view;
                    CGFloat textWidth = MAX(120.0, NSWidth([bubble bounds]) - 24.0);
                    [body setPreferredMaxLayoutWidth:textWidth];
                    NSFont *font = [body font] ?: [NSFont systemFontOfSize:13.5];
                    NSRect measured = [[body stringValue] boundingRectWithSize:NSMakeSize(textWidth, CGFLOAT_MAX)
                                                                        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                                     attributes:@{NSFontAttributeName: font}];
                    // NSTextField's glyph drawing needs a little more leading
                    // than NSString's bounding rect reports, especially for
                    // mixed CJK/Latin answers.  Reserve it so the source
                    // footer starts below the final visible line.
                    CGFloat textHeight = MAX(20.0, ceil(NSHeight(measured)) + 8.0);
                    for (NSLayoutConstraint *constraint in [body constraints]) {
                        if ([[constraint identifier] isEqualToString:@"AnchoraChatBodyHeight"])
                            [constraint setConstant:textHeight];
                    }
                    [body invalidateIntrinsicContentSize];
                }
            }
        }
    }
    [stack setNeedsLayout:YES];
    [stack layoutSubtreeIfNeeded];

    // Do not call -fittingSize here.  The arranged rows already have their
    // resolved Auto Layout frames after the layout pass, so use those frames
    // to size the scroll document view without recursively measuring it.
    CGFloat contentHeight = 20.0;
    for (NSView *row in [stack arrangedSubviews])
        contentHeight = MAX(contentHeight, NSMaxY([row frame]) + 10.0);
    [stack setFrameSize:NSMakeSize(width, ceil(contentHeight))];
    if (scrollToBottom) {
        NSClipView *clipView = [scrollView contentView];
        CGFloat y = MAX(0.0, NSHeight([stack frame]) - NSHeight([clipView bounds]));
        [clipView scrollToPoint:NSMakePoint(0.0, y)];
        [scrollView reflectScrolledClipView:clipView];
    }
    self.aiRefreshingChatLayout = NO;
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

- (NSString *)sourceLabelForPageIndexes:(NSArray<NSNumber *> *)pageIndexes {
    if ([pageIndexes count] == 0)
        return nil;
    PDFDocument *document = [mainController pdfDocument];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSNumber *number in pageIndexes) {
        PDFPage *page = [document pageAtIndex:[number unsignedIntegerValue]];
        NSString *label = [page label];
        if ([label length] == 0)
            label = [NSString stringWithFormat:@"%lu", (unsigned long)[number unsignedIntegerValue] + 1];
        if ([labels containsObject:label] == NO)
            [labels addObject:label];
    }
    if ([labels count] == 0)
        return nil;
    return [NSString stringWithFormat:@"PDF source · p. %@", [labels componentsJoinedByString:@", "]];
}

- (void)openPDFSource:(id)sender {
    NSInteger pageIndex = [sender tag];
    PDFPage *page = pageIndex >= 0 ? [[mainController pdfDocument] pageAtIndex:(NSUInteger)pageIndex] : nil;
    if (page)
        [[mainController pdfView] goToPage:page];
    else
        NSBeep();
}

- (NSArray<NSNumber *> *)paperMapPageIndexesForText:(NSString *)text {
    if ([text length] == 0)
        return @[];
    NSRegularExpression *citationExpression = [NSRegularExpression regularExpressionWithPattern:@"\\[PDF\\s+p\\.\\s*([^\\]]+)\\]" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSMutableOrderedSet<NSNumber *> *indexes = [NSMutableOrderedSet orderedSet];
    PDFDocument *document = [mainController pdfDocument];
    for (NSTextCheckingResult *match in [citationExpression matchesInString:text options:0 range:NSMakeRange(0, [text length])]) {
        NSString *labels = [text substringWithRange:[match rangeAtIndex:1]];
        for (NSString *rawLabel in [labels componentsSeparatedByString:@","]) {
            NSString *label = [rawLabel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSUInteger index = NSNotFound;
            for (NSUInteger candidate = 0; candidate < [document pageCount]; candidate++) {
                if ([[[document pageAtIndex:candidate] label] isEqualToString:label]) {
                    index = candidate;
                    break;
                }
            }
            if (index == NSNotFound) {
                NSRegularExpression *rangeExpression = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)\\s*[-–]\\s*(\\d+)$" options:0 error:NULL];
                NSTextCheckingResult *rangeMatch = [rangeExpression firstMatchInString:label options:0 range:NSMakeRange(0, [label length])];
                if (rangeMatch) {
                    NSInteger firstPage = [[label substringWithRange:[rangeMatch rangeAtIndex:1]] integerValue];
                    NSInteger lastPage = [[label substringWithRange:[rangeMatch rangeAtIndex:2]] integerValue];
                    if (firstPage > 0 && lastPage >= firstPage && lastPage <= (NSInteger)[document pageCount]) {
                        for (NSInteger pageNumber = firstPage; pageNumber <= lastPage; pageNumber++)
                            [indexes addObject:@(pageNumber - 1)];
                        continue;
                    }
                }
                NSInteger numericPage = [label integerValue];
                if (numericPage > 0 && numericPage <= (NSInteger)[document pageCount])
                    index = (NSUInteger)numericPage - 1;
            }
            if (index != NSNotFound)
                [indexes addObject:@(index)];
        }
    }
    return [indexes array];
}

- (NSAttributedString *)paperMapDetailAttributedString:(NSString *)text {
    NSFont *bodyFont = [NSFont systemFontOfSize:12.5];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName: bodyFont,
        NSForegroundColorAttributeName: [NSColor labelColor]
    }];
    NSArray<NSString *> *evidenceLabels = @[@"Direct evidence", @"Author interpretation", @"Reasonable inference", @"Unproven / limitation", @"Not stated or unclear"];
    for (NSString *label in evidenceLabels) {
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"(?im)^\\s*(?:[-•]\\s*)?%@\\s*:?[ \\t]*", [NSRegularExpression escapedPatternForString:label]] options:0 error:NULL];
        for (NSTextCheckingResult *match in [expression matchesInString:[attributed string] options:0 range:NSMakeRange(0, [attributed length])]) {
            [attributed addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:12.5] range:[match range]];
            [attributed addAttribute:NSForegroundColorAttributeName value:[NSColor controlAccentColor] range:[match range]];
        }
    }
    // Paper Map quotes are a source-navigation affordance, not an external
    // URL. Keep the quote in the link payload so clicking it can locate and
    // select the original PDF text on its cited page.
    NSRegularExpression *quoteExpression = [NSRegularExpression regularExpressionWithPattern:@"(?im)^\\s*(?:[-•]\\s*)?Source quote\\s*:\\s*[“\\\"]?(.+?)[”\\\"]?\\s*\\[PDF\\s+p\\.\\s*([^\\]]+)\\]" options:0 error:NULL];
    for (NSTextCheckingResult *match in [quoteExpression matchesInString:[attributed string] options:0 range:NSMakeRange(0, [attributed length])]) {
        NSString *quote = [[attributed string] substringWithRange:[match rangeAtIndex:1]];
        quote = [quote stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        quote = [quote stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"“”\""]];
        NSArray<NSNumber *> *pageIndexes = [self paperMapPageIndexesForText:[NSString stringWithFormat:@"[PDF p. %@]", [[attributed string] substringWithRange:[match rangeAtIndex:2]]]];
        if ([quote length] == 0 || [pageIndexes count] == 0)
            continue;
        NSString *encodedQuote = [[quote dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        NSString *link = [NSString stringWithFormat:@"anchora-pdf:%lu:%@", (unsigned long)[[pageIndexes firstObject] unsignedIntegerValue], encodedQuote];
        NSRange quoteRange = [match rangeAtIndex:1];
        [attributed addAttributes:@{
            NSLinkAttributeName: link,
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
            NSForegroundColorAttributeName: [NSColor controlAccentColor]
        } range:quoteRange];
    }
    return attributed;
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

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSInteger)charIndex {
    if (textView != self.aiPaperMapDetailTextView || [link isKindOfClass:[NSString class]] == NO || [(NSString *)link hasPrefix:@"anchora-pdf:"] == NO)
        return NO;
    NSString *payload = [(NSString *)link substringFromIndex:[@"anchora-pdf:" length]];
    NSRange separator = [payload rangeOfString:@":"];
    if (separator.location == NSNotFound)
        return YES;
    NSUInteger pageIndex = [[payload substringToIndex:separator.location] integerValue];
    NSData *quoteData = [[NSData alloc] initWithBase64EncodedString:[payload substringFromIndex:NSMaxRange(separator)] options:0];
    NSString *quote = [[NSString alloc] initWithData:quoteData encoding:NSUTF8StringEncoding];
    PDFPage *page = [[mainController pdfDocument] pageAtIndex:pageIndex];
    PDFSelection *selection = [self paperMapSelectionForQuote:quote onPage:page];
    SKPDFView *pdfView = [mainController pdfView];
    if ([selection hasCharacters]) {
        [pdfView goToSelection:selection];
        [pdfView setCurrentSelection:selection animate:YES];
    } else if (page) {
        [pdfView goToPage:page];
        NSBeep();
    }
    return YES;
}

- (void)removeStreamingPaperMapChatMessage {
    NSTextField *message = self.aiStreamingMessageField;
    NSView *bubble = [message superview];
    NSView *row = [bubble superview];
    if (row && [[self.aiMessageStack arrangedSubviews] containsObject:row]) {
        [self.aiMessageStack removeArrangedSubview:row];
        [row removeFromSuperview];
    }
    self.aiStreamingMessageField = nil;
    self.aiStreamingPlaceholderVisible = NO;
    [self refreshChatLayoutAndScrollToBottom:NO];
}

- (void)showPaperMapSectionAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[self.aiPaperMapSections count])
        return;
    NSDictionary<NSString *, id> *section = [self.aiPaperMapSections objectAtIndex:(NSUInteger)index];
    [self.aiPaperMapSectionControl selectItemAtIndex:index];
    [[self.aiPaperMapDetailTextView textStorage] setAttributedString:[self paperMapDetailAttributedString:section[@"text"]]];
    NSScrollView *detailScrollView = [self.aiPaperMapDetailTextView enclosingScrollView];
    [[detailScrollView contentView] scrollToPoint:NSZeroPoint];
    [detailScrollView reflectScrolledClipView:[detailScrollView contentView]];

    [self.aiPaperMapSourceControl removeAllItems];
    NSArray<NSNumber *> *pageIndexes = section[@"pageIndexes"];
    if ([pageIndexes count] == 0) {
        [self.aiPaperMapSourceControl addItemWithTitle:@"No cited PDF page in this section"];
        [self.aiPaperMapSourceControl setEnabled:NO];
    } else {
        [self.aiPaperMapSourceControl setEnabled:YES];
        [self.aiPaperMapSourceControl addItemWithTitle:@"Jump to supporting PDF page…"];
        for (NSNumber *pageIndex in pageIndexes) {
            NSString *label = [[[mainController pdfDocument] pageAtIndex:[pageIndex unsignedIntegerValue]] label];
            if ([label length] == 0)
                label = [NSString stringWithFormat:@"%lu", (unsigned long)[pageIndex unsignedIntegerValue] + 1];
            [self.aiPaperMapSourceControl addItemWithTitle:[NSString stringWithFormat:@"↗ PDF p. %@", label]];
            [[self.aiPaperMapSourceControl lastItem] setTag:[pageIndex integerValue]];
        }
    }
}

- (IBAction)selectPaperMapSection:(id)sender {
    [self showPaperMapSectionAtIndex:[(NSPopUpButton *)sender indexOfSelectedItem]];
}

- (IBAction)openPaperMapSource:(id)sender {
    NSMenuItem *item = [(NSPopUpButton *)sender selectedItem];
    if ([item tag] >= 0 && [[item title] hasPrefix:@"↗ PDF p."])
        [self openPDFSource:item];
}

- (IBAction)togglePaperMap:(id)sender {
    if ([self.aiPaperMapSections count] == 0) {
        NSBeep();
        return;
    }
    BOOL show = [self.aiPaperMapCard isHidden] || self.aiPaperMapHeightConstraint.constant <= 0.0;
    [self.aiPaperMapCard setHidden:NO];
    self.aiPaperMapHeightConstraint.priority = show ? NSLayoutPriorityDefaultHigh : NSLayoutPriorityRequired;
    self.aiPaperMapHeightConstraint.constant = show ? 248.0 : 0.0;
    [self.aiPaperMapToggleButton setTitle:show ? @"Hide" : @"Show Paper Map"];
    if (show == NO)
        dispatch_async(dispatch_get_main_queue(), ^{ [self.aiPaperMapCard setHidden:YES]; });
}

- (void)clearPaperMap {
    self.aiPaperMapSections = nil;
    [self.aiPaperMapDetailTextView setString:@""];
    [self.aiPaperMapSectionControl removeAllItems];
    [self.aiPaperMapSourceControl removeAllItems];
    self.aiPaperMapHeightConstraint.priority = NSLayoutPriorityRequired;
    self.aiPaperMapHeightConstraint.constant = 0.0;
    [self.aiPaperMapToggleButton setTitle:@"Show Paper Map"];
    [self.aiPaperMapCard setHidden:YES];
}

- (void)presentPaperMapFromResponse:(NSString *)response {
    if ([response length] == 0)
        return;
    NSMutableArray<NSDictionary<NSString *, id> *> *sections = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *matches = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *definition in SKPaperMapSectionDefinitions()) {
        NSString *expressionPattern = [NSString stringWithFormat:@"(?im)^\\s*(?:#{1,6}\\s*)?(?:\\d+\\s*[.)]\\s*)?%@(?:\\s*\\([^\\n]*\\))?\\s*:?[ \\t]*$", definition[@"pattern"]];
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:expressionPattern options:0 error:NULL];
        NSTextCheckingResult *match = [expression firstMatchInString:response options:0 range:NSMakeRange(0, [response length])];
        if (match)
            [matches addObject:@{ @"definition": definition, @"range": [NSValue valueWithRange:[match range]] }];
    }
    [matches sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *left, NSDictionary<NSString *, id> *right) {
        NSUInteger leftLocation = [left[@"range"] rangeValue].location;
        NSUInteger rightLocation = [right[@"range"] rangeValue].location;
        if (leftLocation < rightLocation)
            return NSOrderedAscending;
        if (leftLocation > rightLocation)
            return NSOrderedDescending;
        return NSOrderedSame;
    }];
    for (NSUInteger index = 0; index < [matches count]; index++) {
        NSRange headingRange = [matches[index][@"range"] rangeValue];
        NSUInteger start = NSMaxRange(headingRange);
        NSUInteger end = index + 1 < [matches count] ? [matches[index + 1][@"range"] rangeValue].location : [response length];
        NSString *text = [[response substringWithRange:NSMakeRange(start, end - start)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([text length] == 0)
            text = @"Not stated or unclear in the supplied paper.";
        NSDictionary<NSString *, NSString *> *definition = matches[index][@"definition"];
        [sections addObject:@{
            @"title": definition[@"title"],
            @"text": text,
            @"pageIndexes": [self paperMapPageIndexesForText:text]
        }];
    }
    if ([sections count] == 0) {
        [sections addObject:@{
            @"title": @"Paper map response",
            @"text": response,
            @"pageIndexes": [self paperMapPageIndexesForText:response]
        }];
    }
    self.aiPaperMapSections = sections;
    [self.aiPaperMapSectionControl removeAllItems];
    for (NSDictionary<NSString *, id> *section in sections)
        [self.aiPaperMapSectionControl addItemWithTitle:section[@"title"]];
    [self.aiPaperMapCard setHidden:NO];
    self.aiPaperMapHeightConstraint.priority = NSLayoutPriorityDefaultHigh;
    self.aiPaperMapHeightConstraint.constant = 248.0;
    [self.aiPaperMapToggleButton setTitle:@"Hide"];
    [self showPaperMapSectionAtIndex:0];
}

- (void)appendChatMessageFrom:(NSString *)sender text:(NSString *)text sourcePageIndexes:(NSArray<NSNumber *> *)sourcePageIndexes {
    void (^appendMessage)(void) = ^{
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
        NSString *initialText = text;
        if (initialText == nil)
            initialText = self.aiRequestStatus ?: @"Preparing request…";
        NSTextField *bodyLabel = [self chatLabelWithString:initialText font:[NSFont systemFontOfSize:13.5] color:bodyColor];
        [bodyLabel setTag:1];
        NSLayoutConstraint *bodyHeightConstraint = [bodyLabel.heightAnchor constraintEqualToConstant:20.0];
        [bodyHeightConstraint setIdentifier:@"AnchoraChatBodyHeight"];
        // Assistant answers are meant to be read as a document alongside the
        // PDF, so let their bubble use the available pane width.  User turns
        // remain intentionally compact and right-aligned.
        // NSTextField needs a finite measurement width while the surrounding
        // NSStackView computes its fitting height.  720pt still gives long
        // Anchora answers substantially more room than the former 270pt cap,
        // while avoiding an unbounded layout calculation as a PDF opens.
        [bodyLabel setPreferredMaxLayoutWidth:isUser ? 360.0 : 720.0];
        [bubble addSubview:senderLabel];
        [bubble addSubview:bodyLabel];
        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
            [senderLabel.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:12.0],
            [senderLabel.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-12.0],
            [senderLabel.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:8.0],
            [bodyLabel.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:12.0],
            [bodyLabel.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-12.0],
            [bodyLabel.topAnchor constraintEqualToAnchor:senderLabel.bottomAnchor constant:3.0],
            bodyHeightConstraint,
            [bubble.topAnchor constraintEqualToAnchor:row.topAnchor],
            [bubble.bottomAnchor constraintEqualToAnchor:row.bottomAnchor]
        ]];
        if (isUser) {
            [constraints addObjectsFromArray:@[
                [bubble.widthAnchor constraintLessThanOrEqualToAnchor:row.widthAnchor multiplier:0.78],
                [bubble.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8.0]
            ]];
        } else {
            // These paired anchors make the response bubble expand and shrink
            // with the live sidebar width while preserving readable margins.
            [constraints addObjectsFromArray:@[
                [bubble.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:8.0],
                [bubble.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8.0]
            ]];
        }
        NSString *sourceLabel = isUser ? nil : [self sourceLabelForPageIndexes:sourcePageIndexes];
        if ([sourceLabel length]) {
            NSString *pageLink = [sourceLabel stringByReplacingOccurrencesOfString:@"PDF source · " withString:@"↗ p. "];
            NSButton *sourceButton = [NSButton buttonWithTitle:pageLink target:self action:@selector(openPDFSource:)];
            [sourceButton setBordered:NO];
            [sourceButton setBezelStyle:NSBezelStyleShadowlessSquare];
            [sourceButton setFont:[NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium]];
            [sourceButton setAttributedTitle:[[NSAttributedString alloc] initWithString:pageLink attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: [[NSColor secondaryLabelColor] colorWithAlphaComponent:0.9]
            }]];
            [sourceButton setToolTip:@"Jump to the PDF page used for this answer"];
            [sourceButton setTag:[[sourcePageIndexes firstObject] integerValue]];
            [sourceButton setTranslatesAutoresizingMaskIntoConstraints:NO];
            [bubble addSubview:sourceButton];
            [constraints addObjectsFromArray:@[
                [sourceButton.leadingAnchor constraintEqualToAnchor:bodyLabel.leadingAnchor],
                [sourceButton.topAnchor constraintEqualToAnchor:bodyLabel.bottomAnchor constant:8.0],
                [sourceButton.heightAnchor constraintEqualToConstant:16.0],
                [sourceButton.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-8.0]
            ]];
        } else {
            [constraints addObject:[bodyLabel.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-9.0]];
        }
        [NSLayoutConstraint activateConstraints:constraints];
        [self.aiMessageStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:self.aiMessageStack.widthAnchor].active = YES;
        if (text == nil) {
            self.aiStreamingMessageField = bodyLabel;
            self.aiStreamingPlaceholderVisible = YES;
        }
        if ([text length])
            [self.aiRenderedChatText appendFormat:@"%@\n", text];
        [self refreshChatLayoutAndScrollToBottom:YES];
    };
    // Requests are initiated on the main thread.  Creating the streaming
    // destination synchronously here prevents an SSE delta from winning the
    // race and being dropped into an as-yet nonexistent bubble.
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
        if (self.aiStreamingPlaceholderVisible && self.aiStreamingMessageField) {
            [self.aiStreamingMessageField setStringValue:status ?: @""];
            [self refreshChatLayoutAndScrollToBottom:YES];
        }
    };
    if ([NSThread isMainThread])
        updateStatus();
    else
        dispatch_async(dispatch_get_main_queue(), updateStatus);
}

- (void)replaceStreamingPlaceholderWithText:(NSString *)text {
    if (self.aiStreamingPlaceholderVisible && self.aiStreamingMessageField) {
        [self.aiStreamingMessageField setStringValue:text ?: @""];
        self.aiStreamingPlaceholderVisible = NO;
        [self refreshChatLayoutAndScrollToBottom:YES];
    } else if ([text length]) {
        [self appendChatMessageFrom:SKAIAssistantName text:text sourcePageIndexes:self.aiRequestSourcePageIndexes];
    }
}

- (void)cancelCurrentAIRequest {
    NSURLSessionDataTask *task = self.aiTask;
    if (task == nil)
        return;
    [task cancel];
    [self.aiSession invalidateAndCancel];
    self.aiTask = nil;
    self.aiSession = nil;
    self.aiPendingStreamText = [NSMutableString string];
    self.aiStreamRenderScheduled = NO;
    [self replaceStreamingPlaceholderWithText:@"Stopped. You can ask another question whenever you’re ready."];
    [self.askAIButton setEnabled:YES];
    [self.askAIButton setTitle:@"Send"];
}

- (BOOL)isScientificReadingProfile {
    return self.aiReadingProfile == SKAIReadingProfileScientific;
}

- (BOOL)usesTraditionalChineseResponses {
    return self.aiResponseLanguage == SKAIResponseLanguageTraditionalChinese;
}

- (NSString *)responseLanguageInstruction {
    if ([self usesTraditionalChineseResponses])
        return @" Respond entirely in Traditional Chinese, while retaining essential English technical terms in parentheses when that improves precision. This applies even when the source material or question is in English.";
    return @" Respond entirely in clear English. Preserve original technical terms when useful.";
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)availableAIModels {
    // Keep this list deliberately small.  These are curated Responses/vision
    // choices rather than every model an API key might list.  Availability is
    // still determined by the user's own API project.
    return @[
        @{ @"id": @"gpt-5.6-luna", @"title": @"GPT-5.6 Luna — Everyday study" },
        @{ @"id": @"gpt-5.6-terra", @"title": @"GPT-5.6 Terra — Recommended" },
        @{ @"id": @"gpt-5.6-sol", @"title": @"GPT-5.6 Sol — Deep paper analysis" },
        @{ @"id": @"gpt-5-mini", @"title": @"GPT-5 mini — Legacy economy" },
    ];
}

- (NSString *)selectedAIModel {
    NSString *savedModel = [[NSUserDefaults standardUserDefaults] stringForKey:SKAIModelDefaultsKey];
    for (NSDictionary<NSString *, NSString *> *choice in [self availableAIModels]) {
        if ([[choice objectForKey:@"id"] isEqualToString:savedModel])
            return savedModel;
    }
    return SKDefaultOpenAIModel;
}

- (IBAction)changeAIModel:(id)sender {
    NSString *model = [(NSMenuItem *)sender representedObject];
    if ([model length] == 0 || [model isEqualToString:[self selectedAIModel]])
        return;
    [[NSUserDefaults standardUserDefaults] setObject:model forKey:SKAIModelDefaultsKey];
    [self appendChatMessageFrom:SKAIAssistantName text:[NSString stringWithFormat:@"Model changed to %@. It will be used for your next request.", model]];
}

- (NSString *)welcomeMessageForCurrentReadingProfile {
    return [self isScientificReadingProfile] ? @"Scientific Reading is ready. Select paper text, use Command-Option-drag on a figure, or choose Build Paper Map (PDF) from •••. I will separate direct evidence, author interpretation, and what remains unproven." : @"Select text, Option-drag for OCR, or Command-Option-drag to send an image region. Your conversation stays here while the PDF remains in view.";
}

- (void)appendPendingWelcomeMessageIfPossible {
    if (self.aiWelcomeMessagePending == NO || self.aiMessageStack == nil || self.aiChatScrollView.window == nil)
        return;
    if (NSWidth([[self.aiChatScrollView contentView] bounds]) < 80.0)
        return;
    self.aiWelcomeMessagePending = NO;
    [self appendChatMessageFrom:SKAIAssistantName text:[self welcomeMessageForCurrentReadingProfile]];
}

- (void)queueWelcomeMessage {
    self.aiWelcomeMessagePending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self appendPendingWelcomeMessageIfPossible];
    });
}

- (IBAction)changeAIResponseLanguage:(id)sender {
    self.aiResponseLanguage = [sender tag] == SKAIResponseLanguageEnglish ? SKAIResponseLanguageEnglish : SKAIResponseLanguageTraditionalChinese;
    [[NSUserDefaults standardUserDefaults] setInteger:self.aiResponseLanguage forKey:SKAIResponseLanguageDefaultsKey];
}

- (NSButton *)quickActionButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    // Do not use +buttonWithTitle:target:action: here.  On macOS 26 that
    // convenience factory calls -sizeToFit while the right-side controller is
    // still loading.  With Scientific mode selected, AppKit enters its
    // SwiftUI/AttributeGraph sizing bridge and can allocate indefinitely
    // before the PDF window finishes opening.  A concrete initial frame lets
    // the enclosing stack take over sizing after the view is installed.
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 26.0)];
    [button setTitle:title];
    [button setTarget:self];
    [button setAction:@selector(askAIQuickAction:)];
    [button setTag:tag];
    [button setBezelStyle:NSBezelStyleAccessoryBarAction];
    [button setToolTip:title];
    [button setTranslatesAutoresizingMaskIntoConstraints:NO];
    return button;
}

- (void)rebuildAIQuickActions {
    NSView *quickActions = self.aiQuickActions;
    if (quickActions == nil)
        return;
    [NSLayoutConstraint deactivateConstraints:self.aiQuickActionConstraints];
    self.aiQuickActionConstraints = nil;
    for (NSView *view in [[quickActions subviews] copy])
        [view removeFromSuperview];

    NSArray<NSString *> *titles = [self isScientificReadingProfile] ? @[@"Paper", @"Question", @"Hypothesis", @"Methods", @"Figure", @"Evidence"] : @[@"Explain", @"Translate", @"Clinical"];
    NSMutableArray<NSButton *> *buttons = [NSMutableArray arrayWithCapacity:[titles count]];
    for (NSUInteger index = 0; index < [titles count]; index++) {
        NSButton *button = [self quickActionButtonWithTitle:titles[index] tag:index];
        if ([self isScientificReadingProfile] && index == 5)
            [button setToolTip:@"Build an evidence chain: direct result, author interpretation, inference, and what remains unproven."];
        [quickActions addSubview:button];
        [buttons addObject:button];
    }

    // NSStackView's addArrangedSubview: is the allocation loop seen in the
    // live process sample. Direct constraints retain responsive equal-width
    // controls without entering that AppKit implementation during startup.
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    for (NSUInteger index = 0; index < [buttons count]; index++) {
        NSButton *button = buttons[index];
        [constraints addObjectsFromArray:@[
            [button.topAnchor constraintEqualToAnchor:quickActions.topAnchor],
            [button.bottomAnchor constraintEqualToAnchor:quickActions.bottomAnchor]
        ]];
        if (index == 0) {
            [constraints addObject:[button.leadingAnchor constraintEqualToAnchor:quickActions.leadingAnchor]];
        } else {
            NSButton *previous = buttons[index - 1];
            [constraints addObject:[button.leadingAnchor constraintEqualToAnchor:previous.trailingAnchor constant:4.0]];
            [constraints addObject:[button.widthAnchor constraintEqualToAnchor:buttons.firstObject.widthAnchor]];
        }
        if (index == [buttons count] - 1)
            [constraints addObject:[button.trailingAnchor constraintEqualToAnchor:quickActions.trailingAnchor]];
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
    self.aiReadingProfile = selectedSegment == 1 ? SKAIReadingProfileScientific : SKAIReadingProfileStudy;
    [[NSUserDefaults standardUserDefaults] setInteger:self.aiReadingProfile forKey:SKAIReadingProfileDefaultsKey];
    [self updateAIReadingProfileInterface];
}

- (void)buildAIInterface {
    NSInteger savedProfile = [[NSUserDefaults standardUserDefaults] integerForKey:SKAIReadingProfileDefaultsKey];
    self.aiReadingProfile = savedProfile == SKAIReadingProfileScientific ? SKAIReadingProfileScientific : SKAIReadingProfileStudy;
    NSInteger savedLanguage = [[NSUserDefaults standardUserDefaults] integerForKey:SKAIResponseLanguageDefaultsKey];
    self.aiResponseLanguage = savedLanguage == SKAIResponseLanguageEnglish ? SKAIResponseLanguageEnglish : SKAIResponseLanguageTraditionalChinese;
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
    [aiView addSubview:contextCard];
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
    // area.  It deliberately does not live inside the chat's NSStackView:
    // large scientific answers must never feed back into chat sizing while a
    // PDF is opening or a response is streaming.
    NSVisualEffectView *paperMapCard = [self aiCardView];
    [paperMapCard setHidden:YES];
    [aiView addSubview:paperMapCard];
    NSTextField *mapLabel = [NSTextField labelWithString:@"PAPER MAP"];
    [mapLabel setFont:[NSFont boldSystemFontOfSize:10.0]];
    [mapLabel setTextColor:[NSColor secondaryLabelColor]];
    [mapLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [paperMapCard addSubview:mapLabel];
    NSTextField *mapLegend = [NSTextField labelWithString:@"Click a Source quote to highlight it in the PDF"];
    [mapLegend setFont:[NSFont systemFontOfSize:10.0]];
    [mapLegend setTextColor:[NSColor secondaryLabelColor]];
    [mapLegend setLineBreakMode:NSLineBreakByTruncatingTail];
    [mapLegend setToolTip:@"Source quotes jump to, and select, their matching PDF text. Evidence labels separate direct results, author interpretation, inference, and what remains unproven."];
    [mapLegend setTranslatesAutoresizingMaskIntoConstraints:NO];
    [paperMapCard addSubview:mapLegend];
    NSButton *mapToggleButton = [NSButton buttonWithTitle:@"Show Paper Map" target:self action:@selector(togglePaperMap:)];
    [mapToggleButton setBezelStyle:NSBezelStyleAccessoryBarAction];
    [mapToggleButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [paperMapCard addSubview:mapToggleButton];
    NSPopUpButton *sectionControl = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [sectionControl setTarget:self];
    [sectionControl setAction:@selector(selectPaperMapSection:)];
    [sectionControl setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]];
    [sectionControl setTranslatesAutoresizingMaskIntoConstraints:NO];
    [paperMapCard addSubview:sectionControl];
    NSPopUpButton *sourceControl = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [sourceControl setTarget:self];
    [sourceControl setAction:@selector(openPaperMapSource:)];
    [sourceControl setFont:[NSFont systemFontOfSize:10.5]];
    [sourceControl setTranslatesAutoresizingMaskIntoConstraints:NO];
    [paperMapCard addSubview:sourceControl];
    NSTextView *mapDetailTextView = nil;
    NSScrollView *mapDetailScrollView = [self scrollViewWithTextView:&mapDetailTextView];
    [mapDetailTextView setFont:[NSFont systemFontOfSize:12.5]];
    [mapDetailTextView setTextColor:[NSColor labelColor]];
    [mapDetailTextView setTextContainerInset:NSMakeSize(6.0, 5.0)];
    [mapDetailTextView setDelegate:self];
    [mapDetailTextView setLinkTextAttributes:@{
        NSForegroundColorAttributeName: [NSColor controlAccentColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
    }];
    [paperMapCard addSubview:mapDetailScrollView];
    [NSLayoutConstraint activateConstraints:@[
        [mapLabel.leadingAnchor constraintEqualToAnchor:paperMapCard.leadingAnchor constant:10.0],
        [mapLabel.topAnchor constraintEqualToAnchor:paperMapCard.topAnchor constant:8.0],
        [mapLegend.leadingAnchor constraintEqualToAnchor:mapLabel.trailingAnchor constant:8.0],
        [mapLegend.centerYAnchor constraintEqualToAnchor:mapLabel.centerYAnchor],
        [mapLegend.trailingAnchor constraintLessThanOrEqualToAnchor:mapToggleButton.leadingAnchor constant:-6.0],
        [mapToggleButton.trailingAnchor constraintEqualToAnchor:paperMapCard.trailingAnchor constant:-8.0],
        [mapToggleButton.centerYAnchor constraintEqualToAnchor:mapLabel.centerYAnchor],
        [sectionControl.leadingAnchor constraintEqualToAnchor:paperMapCard.leadingAnchor constant:8.0],
        [sectionControl.trailingAnchor constraintEqualToAnchor:paperMapCard.trailingAnchor constant:-8.0],
        [sectionControl.topAnchor constraintEqualToAnchor:mapLabel.bottomAnchor constant:5.0],
        [sourceControl.leadingAnchor constraintEqualToAnchor:sectionControl.leadingAnchor],
        [sourceControl.topAnchor constraintEqualToAnchor:sectionControl.bottomAnchor constant:3.0],
        [mapDetailScrollView.leadingAnchor constraintEqualToAnchor:paperMapCard.leadingAnchor constant:4.0],
        [mapDetailScrollView.trailingAnchor constraintEqualToAnchor:paperMapCard.trailingAnchor constant:-4.0],
        [mapDetailScrollView.topAnchor constraintEqualToAnchor:sourceControl.bottomAnchor constant:3.0],
        [mapDetailScrollView.bottomAnchor constraintEqualToAnchor:paperMapCard.bottomAnchor constant:-5.0]
    ]];

    NSView *quickActions = [[NSView alloc] initWithFrame:NSZeroRect];
    [quickActions setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSScrollView *chatScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [chatScrollView setBorderType:NSNoBorder];
    [chatScrollView setHasVerticalScroller:YES];
    [chatScrollView setAutohidesScrollers:YES];
    [chatScrollView setDrawsBackground:NO];
    [chatScrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
    // Keep the empty document view at the stack's own 20pt minimum.  A 1pt
    // frame produces an autoresizing height constraint that conflicts with a
    // wrapped chat bubble while the sidebar is being installed.
    NSStackView *messageStack = [[NSStackView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1.0, 20.0)];
    [messageStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [messageStack setAlignment:NSLayoutAttributeLeading];
    [messageStack setDistribution:NSStackViewDistributionFill];
    [messageStack setSpacing:9.0];
    [messageStack setEdgeInsets:NSEdgeInsetsMake(10.0, 0.0, 10.0, 0.0)];
    [messageStack setAutoresizingMask:NSViewWidthSizable];
    [chatScrollView setDocumentView:messageStack];
    [aiView addSubview:chatScrollView];

    // Keep the action bar above the transparent chat scroll view in the view
    // hierarchy.  Constraints keep the views separated visually, but z-order
    // also determines which view receives mouse clicks during a live reflow.
    [aiView addSubview:quickActions positioned:NSWindowAbove relativeTo:chatScrollView];

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
        [paperMapCard.leadingAnchor constraintEqualToAnchor:contextCard.leadingAnchor],
        [paperMapCard.trailingAnchor constraintEqualToAnchor:contextCard.trailingAnchor],
        [paperMapCard.topAnchor constraintEqualToAnchor:contextCard.bottomAnchor constant:8.0],
        [chatScrollView.leadingAnchor constraintEqualToAnchor:aiView.leadingAnchor constant:8.0],
        [chatScrollView.trailingAnchor constraintEqualToAnchor:aiView.trailingAnchor constant:-8.0],
        [chatScrollView.topAnchor constraintEqualToAnchor:paperMapCard.bottomAnchor constant:8.0],
        [chatScrollView.bottomAnchor constraintEqualToAnchor:quickActions.topAnchor constant:-8.0],
        [chatScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:120.0],
        [quickActions.leadingAnchor constraintEqualToAnchor:aiView.leadingAnchor constant:12.0],
        [quickActions.trailingAnchor constraintEqualToAnchor:aiView.trailingAnchor constant:-12.0],
        [quickActions.bottomAnchor constraintEqualToAnchor:composer.topAnchor constant:-8.0],
        [composer.leadingAnchor constraintEqualToAnchor:aiView.leadingAnchor constant:12.0],
        [composer.trailingAnchor constraintEqualToAnchor:aiView.trailingAnchor constant:-12.0],
        [composer.bottomAnchor constraintEqualToAnchor:aiView.bottomAnchor constant:-12.0]
    ]];

    self.aiView = aiView;
    self.aiContextTextView = contextTextView;
    self.aiPaperMapCard = paperMapCard;
    self.aiPaperMapSectionControl = sectionControl;
    self.aiPaperMapSourceControl = sourceControl;
    self.aiPaperMapDetailTextView = mapDetailTextView;
    self.aiPaperMapToggleButton = mapToggleButton;
    self.aiPaperMapHeightConstraint = [paperMapCard.heightAnchor constraintEqualToConstant:0.0];
    // A hidden map must be exactly zero-height: NSView.hidden does not remove
    // Auto Layout constraints. The visible state lowers this priority so it
    // yields gracefully in a very short sidebar.
    self.aiPaperMapHeightConstraint.priority = NSLayoutPriorityRequired;
    self.aiPaperMapHeightConstraint.active = YES;
    self.aiQuestionField = questionField;
    self.aiChatScrollView = chatScrollView;
    self.aiMessageStack = messageStack;
    self.aiQuickActions = quickActions;
    self.aiQuickActionsHeightConstraint = [quickActions.heightAnchor constraintEqualToConstant:26.0];
    self.aiQuickActionsHeightConstraint.active = YES;
    self.aiRenderedChatText = [NSMutableString string];
    self.askAIButton = askButton;
    self.pinResponseButton = pinButton;
    self.webVerificationButton = webButton;
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
    if (self.aiTask) {
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
    if ([self isScientificReadingProfile]) {
        NSString *question = nil;
        switch ([sender tag]) {
            case 0:
                question = @"Build a complete Paper map. Return exactly these Markdown H2 headings in this exact English spelling: ## Research problem and gap; ## Objective; ## Main hypothesis / research question; ## Study and experimental methods; ## Key figures and evidence; ## What the paper directly demonstrates; ## Authors’ interpretation; ## Limitations and unanswered questions. Under each applicable heading, explicitly label Direct evidence:, Author interpretation:, Reasonable inference:, and Unproven / limitation:. For every Direct evidence item, include a separate line in the exact form Source quote: “a short verbatim quote from the PDF” [PDF p. X]. The quote must be 8–28 words copied exactly from the cited page, so it can be selected in the PDF. Cite each PDF-grounded claim and say ‘not stated or unclear’ rather than guessing.";
                break;
            case 1:
                question = @"What research problem is this paper studying? State the clinical/scientific gap, the authors’ objective, and the precise research question. Distinguish explicit statements from your inference.";
                break;
            case 2:
                question = @"Identify the main hypothesis or hypotheses. State the predicted relationship/effect, what result would support it, and whether the hypothesis is explicitly stated or inferred from the study design.";
                break;
            case 3:
                question = @"Explain the research methods and experimental methods: design, participants/samples, groups or controls, intervention/manipulation, measured outcomes, timing, and analysis. Flag missing details rather than inventing them.";
                break;
            case 4:
                question = @"Interpret this figure rigorously. Explain the x-axis and y-axis, units, groups/conditions, controls, symbols/error bars/statistical annotations, the observed pattern, the authors’ claim, and what this figure alone can and cannot establish. If an axis or label is not legible, say so.";
                break;
            default:
                question = @"What does this evidence demonstrate? Separate: direct result, authors’ interpretation, what is a reasonable inference, and what remains unproven. Do not turn association into causation without an appropriate design.";
                break;
        }
        if (self.aiTask) {
            [self cancelCurrentAIRequest];
            return;
        }
        PDFSelection *selection = self.aiSelection;
        if ([selection hasCharacters] == NO && [self.aiSelectionText length] == 0 && [self.aiSelectionImageDataURL length] == 0)
            [self updateSelectionContext:nil];
        selection = self.aiSelection;
        BOOL hasDirectContext = [selection hasCharacters] || [self.aiSelectionText length] || [self.aiSelectionImageDataURL length];
        // Paper is always a whole-document action. The other actions use a
        // live selection when present; otherwise they remain useful by using
        // the complete paper (or the visible page for Figure).
        if ([sender tag] == 0) {
            [self startWholeDocumentRequestWithQuestion:question displayQuestion:@"Build Paper Map"];
            return;
        }
        if (hasDirectContext) {
            [self.aiQuestionField setStringValue:question];
            [self askAI:sender];
            return;
        }
        if ([sender tag] == 4) {
            [self analyzeCurrentPageWithQuestion:question displayQuestion:@"Analyze current page figure"];
            return;
        }
        NSArray<NSString *> *titles = @[@"", @"Research Question", @"Main Hypothesis", @"Methods", @"Figure", @"Evidence Chain"];
        [self startWholeDocumentRequestWithQuestion:question displayQuestion:titles[[sender tag]]];
        return;
    }
    switch ([sender tag]) {
        case 1:
            [self.aiQuestionField setStringValue:@"Translate this into the configured response language. Preserve technical terms where helpful; if the source is already in that language, provide a clear language-native paraphrase instead."];
            break;
        case 2:
            [self.aiQuestionField setStringValue:@"Explain the clinical relevance and practical implications of this." ];
            break;
        default:
            [self.aiQuestionField setStringValue:@"Explain this clearly, step by step, for study."];
            break;
    }
    [self askAI:sender];
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
    [chineseItem setTag:SKAIResponseLanguageTraditionalChinese];
    [chineseItem setState:[self usesTraditionalChineseResponses] ? NSControlStateValueOn : NSControlStateValueOff];
    [languageMenu addItem:chineseItem];
    NSMenuItem *englishItem = [[NSMenuItem alloc] initWithTitle:@"English" action:@selector(changeAIResponseLanguage:) keyEquivalent:@""];
    [englishItem setTarget:self];
    [englishItem setTag:SKAIResponseLanguageEnglish];
    [englishItem setState:[self usesTraditionalChineseResponses] ? NSControlStateValueOff : NSControlStateValueOn];
    [languageMenu addItem:englishItem];
    NSMenuItem *languageItem = [[NSMenuItem alloc] initWithTitle:@"Response language" action:nil keyEquivalent:@""];
    [languageItem setSubmenu:languageMenu];
    [menu addItem:languageItem];
    NSMenu *modelMenu = [[NSMenu alloc] initWithTitle:@"AI model"];
    NSString *selectedModel = [self selectedAIModel];
    for (NSDictionary<NSString *, NSString *> *choice in [self availableAIModels]) {
        NSString *model = [choice objectForKey:@"id"];
        NSMenuItem *modelItem = [[NSMenuItem alloc] initWithTitle:[choice objectForKey:@"title"] action:@selector(changeAIModel:) keyEquivalent:@""];
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
    NSString *label = [self sourceLabelForPageIndexes:pageIndexes];
    return [label length] ? [label stringByReplacingOccurrencesOfString:@"PDF source · " withString:@""] : @"unknown page";
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

    NSArray<NSNumber *> *sourcePageIndexes = [self sourcePageIndexesForSelection:selection fallbackPage:page];
    // Follow-up questions intentionally work without a new selection. Keep a
    // traceable source in that case rather than making the answer look uncited.
    if ([sourcePageIndexes count] == 0)
        sourcePageIndexes = self.aiRequestSourcePageIndexes ?: @[];
    NSString *sourceDescription = [self requestSourceDescriptionForPageIndexes:sourcePageIndexes];
    NSString *prompt = [sourceText length] ? [NSString stringWithFormat:@"PDF source page(s): %@\nPDF context:\n%@\n\nQuestion: %@", sourceDescription, sourceText, question] : [NSString stringWithFormat:@"Question: %@", question];
    NSMutableArray *content = [NSMutableArray arrayWithObject:@{ @"type": @"input_text", @"text": prompt }];
    if ([imageDataURL length])
        [content addObject:@{ @"type": @"input_image", @"image_url": imageDataURL, @"detail": @"high" }];
    if ([fileDataURL length])
        [content addObject:@{ @"type": @"input_file", @"filename": fileName ?: @"document.pdf", @"file_data": fileDataURL, @"detail": @"high" }];
    NSMutableArray *input = [[self conversationInputItems] mutableCopy];
    [input addObject:@{ @"role": @"user", @"content": content }];
    NSString *instructions = nil;
    if ([self isScientificReadingProfile]) {
        instructions = @"You are Anchora Scientific, a rigorous paper-reading assistant. Treat supplied PDF context as the primary source and help the user reconstruct the paper's argument: research problem, gap, objective, hypothesis, methods, figures, evidence, conclusions, and limitations. For each conclusion, distinguish exactly four levels when relevant: (1) direct result in the supplied material, (2) the authors' interpretation, (3) a reasonable inference, and (4) what remains unproven. Never turn correlation into causation, an observed result into a mechanism, or an authors' claim into established fact without sufficient design and evidence. When interpreting a figure, explicitly cover x-axis, y-axis, units, groups/controls, uncertainty or statistics, observed pattern, author claim, and limits of that figure. Say ‘not stated or unclear’ whenever the supplied material does not support an answer. Do not invent PDF citations or claim the PDF says something it does not. For every paragraph that relies on supplied PDF context, end the paragraph with an inline citation in the exact form [PDF p. X], using only supplied source page labels. Do not attach a PDF citation to general knowledge. Use a thorough, evidence-first structure; do not omit requested sections merely to be brief.";
    } else {
        instructions = @"You are Anchora, a concise study assistant. Treat supplied PDF context as the primary source for questions about this document. You may also use reliable general knowledge when it helps answer the user's question. Clearly distinguish claims supported by the PDF from your additional explanation; do not invent PDF citations or claim the PDF says something it does not. For every paragraph that relies on supplied PDF context, end the paragraph with an inline citation in the exact form [PDF p. X], using only the supplied source page labels. Do not attach a PDF citation to general knowledge. Continue the current PDF conversation naturally.";
    }
    instructions = [instructions stringByAppendingString:[self responseLanguageInstruction]];
    if (self.webVerificationEnabled)
        instructions = [instructions stringByAppendingString:@" Web verification is enabled. Before answering, always use web search at least once to check relevant factual or current claims. Prefer primary and authoritative sources. Clearly distinguish PDF-grounded claims, web-verified claims, and your own explanation. Never invent a source or citation."];
    NSUInteger outputTokenBudget = ([fileDataURL length] && [self isScientificReadingProfile]) ? SKAIPaperMapMaximumOutputTokens : SKAIStandardMaximumOutputTokens;
    NSMutableDictionary *body = @{
        @"model": [self selectedAIModel],
        @"stream": @YES,
        @"store": @NO,
        @"max_output_tokens": @(outputTokenBudget),
        @"instructions": instructions,
        @"input": input
    }.mutableCopy;
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
    // A Paper Map is the sole full-document response rendered into the
    // navigator. All other requests remain normal chat replies.
    self.aiRequestIsPaperMap = [self isScientificReadingProfile] && [fileDataURL length] > 0 &&
        ([displayQuestion rangeOfString:@"Paper Map" options:NSCaseInsensitiveSearch].location != NSNotFound ||
         [question rangeOfString:@"Paper map" options:NSCaseInsensitiveSearch].location != NSNotFound);
    self.aiRequestSourcePageIndexes = sourcePageIndexes;
    self.aiRequestConversationUserText = [sourceText length] ? [NSString stringWithFormat:@"%@\n\nPDF context used:\n%@", displayQuestion, [sourceText substringToIndex:MIN((NSUInteger)6000, [sourceText length])]] : displayQuestion;
    [self recordAIConversationRole:@"user" text:self.aiRequestConversationUserText];
    self.aiReceivedOutput = NO;
    self.aiWebSourceURLs = [NSMutableOrderedSet orderedSet];
    self.aiEventData = [NSMutableData data];
    self.latestAIResponse = [NSMutableString string];
    self.aiPendingStreamText = [NSMutableString string];
    self.aiStreamRenderScheduled = NO;
    self.aiStreamingPlaceholderVisible = YES;
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
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.openai.com/v1/responses"]];
    [request setHTTPMethod:@"POST"];
    // A full-paper map can legitimately take longer than a selected sentence.
    // It remains cancellable through the Stop button in the composer.
    [request setTimeoutInterval:[fileDataURL length] ? 300.0 : 120.0];
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
    NSString *question = [self isScientificReadingProfile] ? @"Analyze this complete paper page, including its visual structure. Identify any research claim, methods, result, figure/table evidence, and limitations visible on the page. For every figure, explain axes, groups, and what it can establish." : @"Study this complete PDF page, including diagrams, tables, figures, and layout. Summarize the key ideas, important terms, and 3 concise takeaways.";
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
    NSString *question = [self isScientificReadingProfile] ? @"Build a complete Paper map for this paper. Return exactly these Markdown H2 headings, in this exact English spelling even if the response language is Chinese: ## Research problem and gap; ## Objective; ## Main hypothesis / research question; ## Study and experimental methods; ## Key figures and evidence; ## What the paper directly demonstrates; ## Authors’ interpretation; ## Limitations and unanswered questions. Under each applicable heading, explicitly label evidence as Direct evidence:, Author interpretation:, Reasonable inference:, and Unproven / limitation:. For every Direct evidence item, include a separate line in the exact form Source quote: “a short verbatim quote from the PDF” [PDF p. X]. The quote must be 8–28 words copied exactly from the cited page, so it can be selected in the PDF. Use the PDF text and visuals, cite the relevant page for every PDF-grounded claim, and say ‘not stated or unclear’ rather than guessing." : @"Create a study-oriented summary of this complete PDF. Use both its text and visuals. Organize it by topic, identify core concepts and high-yield details, and finish with a short review checklist. Cite page numbers for major sections.";
    [self startWholeDocumentRequestWithQuestion:question displayQuestion:[self isScientificReadingProfile] ? @"Build a Paper map for this PDF" : @"Summarize this PDF"];
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
        if (self.aiPendingStreamText == nil)
            self.aiPendingStreamText = [NSMutableString string];
        [self.aiPendingStreamText appendString:text];
        [self.aiRenderedChatText appendString:text];
        if (self.aiStreamRenderScheduled)
            return;
        self.aiStreamRenderScheduled = YES;
        // Paper Map responses arrive in many small deltas. Rendering the
        // entire NSTextField for every delta produces O(n²) CoreText work.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self flushPendingAIStreamText];
        });
    });
}

- (void)flushPendingAIStreamText {
    self.aiStreamRenderScheduled = NO;
    if ([self.aiPendingStreamText length] == 0)
        return;
    NSTextField *streamingMessage = self.aiStreamingMessageField;
    if (streamingMessage) {
        if (self.aiStreamingPlaceholderVisible) {
            [streamingMessage setStringValue:self.aiPendingStreamText];
            self.aiStreamingPlaceholderVisible = NO;
        } else {
            [streamingMessage setStringValue:[[streamingMessage stringValue] stringByAppendingString:self.aiPendingStreamText]];
        }
        // Multiline NSTextField does not reliably invalidate its intrinsic
        // height after a streamed -setStringValue: on macOS 26.  Without
        // this, the source chip lays out but the answer's body remains at the
        // old one-line/zero-line height — exactly the empty-bubble symptom.
        NSView *bubble = [streamingMessage superview];
        CGFloat textWidth = MAX(120.0, NSWidth([bubble bounds]) - 24.0);
        [streamingMessage setPreferredMaxLayoutWidth:textWidth];
        [streamingMessage invalidateIntrinsicContentSize];
        [streamingMessage setNeedsLayout:YES];
        [bubble setNeedsLayout:YES];
        [[bubble superview] setNeedsLayout:YES];
        [self.aiMessageStack setNeedsLayout:YES];
    }
    [self.aiPendingStreamText setString:@""];
    [self refreshChatLayoutAndScrollToBottom:YES];
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

- (NSString *)outputTextFromCompletedResponse:(NSDictionary *)response {
    NSArray *output = [response[@"output"] isKindOfClass:[NSArray class]] ? response[@"output"] : nil;
    if ([output count] == 0)
        return nil;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSDictionary *item in output) {
        NSArray *content = [item[@"content"] isKindOfClass:[NSArray class]] ? item[@"content"] : nil;
        for (NSDictionary *contentItem in content) {
            if ([contentItem[@"type"] isEqualToString:@"output_text"] && [contentItem[@"text"] isKindOfClass:[NSString class]] && [contentItem[@"text"] length])
                [parts addObject:contentItem[@"text"]];
        }
    }
    return [parts count] ? [parts componentsJoinedByString:@"\n"] : nil;
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
            [self updateAIRequestStatus:[NSString stringWithFormat:@"OpenAI error: %@", message[@"message"] ?: @"Unknown error"]];
        else if ([type isEqualToString:@"response.completed"]) {
            // Most Responses stream text deltas.  Some valid completions only
            // include their text in the terminal response, however; accepting
            // it here prevents a successful request from looking blank.
            NSString *finalText = [self outputTextFromCompletedResponse:message[@"response"]];
            if ([finalText length] && [self.latestAIResponse length] == 0)
                [self appendAIText:finalText];
        } else if ([type isEqualToString:@"response.failed"]) {
            NSDictionary *response = [message[@"response"] isKindOfClass:[NSDictionary class]] ? message[@"response"] : nil;
            NSDictionary *failure = [response[@"error"] isKindOfClass:[NSDictionary class]] ? response[@"error"] : nil;
            [self updateAIRequestStatus:[NSString stringWithFormat:@"OpenAI error: %@", failure[@"message"] ?: @"The request failed."]];
        }
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (dataTask != self.aiTask)
        return;
    [self.aiEventData appendData:data];
    [self consumeAIEvents];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    if (dataTask == self.aiTask)
        [self updateAIRequestStatus:@"Anchora is reading the document…"];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (task != self.aiTask)
        return;
    NSInteger statusCode = [(NSHTTPURLResponse *)[task response] statusCode];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self flushPendingAIStreamText];
        if (error && error.code != NSURLErrorCancelled)
            [self replaceStreamingPlaceholderWithText:[NSString stringWithFormat:@"Network error: %@", [error localizedDescription]]];
        else if (error.code == NSURLErrorCancelled)
            [self replaceStreamingPlaceholderWithText:@"Stopped."];
        else if (self.aiReceivedOutput == NO)
            [self replaceStreamingPlaceholderWithText:statusCode >= 400 ? [NSString stringWithFormat:@"OpenAI request failed (HTTP %ld). Check your API key, billing, and model access.", (long)statusCode] : @"No text was returned by OpenAI."];
        else {
            // Keep the complete response for Pin latest answer and memory,
            // while presenting the Paper Map itself as a compact navigator.
            // Do this before adding web sources so the parser only sees the
            // structured paper analysis.
            if (self.aiRequestIsPaperMap) {
                [self presentPaperMapFromResponse:self.latestAIResponse];
                [self removeStreamingPaperMapChatMessage];
            }
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
        self.aiRequestStatus = nil;
        self.aiRequestIsPaperMap = NO;
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
    self.aiPendingStreamText = nil;
    self.aiStreamRenderScheduled = NO;
    self.aiRequestStatus = nil;
    self.aiStreamingPlaceholderVisible = NO;
    self.aiRequestConversationUserText = nil;
    self.aiRequestQuestion = nil;
    self.aiRequestSourcePageIndexes = nil;
    self.aiRequestIsPaperMap = NO;
    [self clearPaperMap];
    [self clearRenderedChat];
    [self queueWelcomeMessage];
}

- (IBAction)clearAIConversation:(id)sender {
    [self.aiTask cancel];
    [self.aiSession invalidateAndCancel];
    self.aiTask = nil;
    self.aiSession = nil;
    self.aiConversation = [NSMutableArray array];
    self.latestAIResponse = nil;
    self.aiPendingStreamText = nil;
    self.aiStreamRenderScheduled = NO;
    self.aiRequestStatus = nil;
    self.aiStreamingPlaceholderVisible = NO;
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
        // The pane now has a real width; finish deferred chat sizing here.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendPendingWelcomeMessageIfPossible];
            [self refreshChatLayoutAndScrollToBottom:NO];
        });
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
