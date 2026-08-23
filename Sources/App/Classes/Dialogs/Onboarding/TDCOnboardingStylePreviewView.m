/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

#import "TLOLocalization.h"
#import "TDCOnboardingSteps.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface TDCOnboardingStylePreviewView ()
@property(nonatomic, strong) NSView *canvas;
@property(nonatomic, strong) NSStackView *messageStack;
@property(nonatomic, strong) NSTextField *titleField;
@property(nonatomic, strong) NSTextField *descriptionField;
@property(nonatomic, strong) NSImageView *checkmarkView;
@end

@implementation TDCOnboardingStylePreviewView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	self->_styleName = @"";
	self->_styleTitle = @"";
	self->_styleDescription = @"";
	self->_messageFontSize = 13.0;

	self.wantsLayer = YES;

	NSView *canvas = [NSView new];

	canvas.wantsLayer = YES;
	canvas.layer.cornerRadius = 10;
	canvas.layer.borderWidth = 1;
	canvas.layer.masksToBounds = YES;
	canvas.translatesAutoresizingMaskIntoConstraints = NO;

	NSStackView *messageStack = [NSStackView new];

	messageStack.orientation = NSUserInterfaceLayoutOrientationVertical;
	messageStack.alignment = NSLayoutAttributeWidth;
	messageStack.spacing = 6;
	messageStack.translatesAutoresizingMaskIntoConstraints = NO;

	[canvas addSubview:messageStack];

	NSTextField *titleField = [NSTextField labelWithString:@""];

	titleField.font = [NSFont systemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightSemibold];
	titleField.alignment = NSTextAlignmentCenter;
	titleField.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *descriptionField = [NSTextField labelWithString:@""];

	descriptionField.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	descriptionField.textColor = [NSColor secondaryLabelColor];
	descriptionField.alignment = NSTextAlignmentCenter;
	descriptionField.translatesAutoresizingMaskIntoConstraints = NO;

	NSImageView *checkmarkView = [NSImageView
		imageViewWithImage:[NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:nil]];

	checkmarkView.contentTintColor = [NSColor controlAccentColor];
	checkmarkView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:18
																						weight:NSFontWeightRegular];
	checkmarkView.translatesAutoresizingMaskIntoConstraints = NO;

	[self addSubview:canvas];
	[self addSubview:titleField];
	[self addSubview:descriptionField];
	[self addSubview:checkmarkView];

	[NSLayoutConstraint activateConstraints:@[
		[canvas.topAnchor constraintEqualToAnchor:self.topAnchor],
		[canvas.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[canvas.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
		[canvas.heightAnchor constraintEqualToConstant:170],

		[messageStack.topAnchor constraintEqualToAnchor:canvas.topAnchor constant:14],
		[messageStack.leadingAnchor constraintEqualToAnchor:canvas.leadingAnchor constant:14],
		[messageStack.trailingAnchor constraintEqualToAnchor:canvas.trailingAnchor constant:-14],

		[titleField.topAnchor constraintEqualToAnchor:canvas.bottomAnchor constant:10],
		[titleField.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[descriptionField.topAnchor constraintEqualToAnchor:titleField.bottomAnchor constant:2],
		[descriptionField.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[descriptionField.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

		[checkmarkView.topAnchor constraintEqualToAnchor:canvas.topAnchor constant:8],
		[checkmarkView.trailingAnchor constraintEqualToAnchor:canvas.trailingAnchor constant:-8],
	]];

	self.canvas = canvas;
	self.messageStack = messageStack;
	self.titleField = titleField;
	self.descriptionField = descriptionField;
	self.checkmarkView = checkmarkView;

	[self updateSelectionAppearance];
}

#pragma mark -
#pragma mark Accessibility

- (BOOL)isAccessibilityElement
{
	return YES;
}

- (nullable NSString *)accessibilityLabel
{
	return self.styleTitle;
}

- (nullable NSAccessibilityRole)accessibilityRole
{
	return NSAccessibilityRadioButtonRole;
}

- (nullable id)accessibilityValue
{
	return @(self.selected);
}

- (BOOL)accessibilityPerformPress
{
	[self select];

	return YES;
}

#pragma mark -
#pragma mark Properties

- (void)setStyleTitle:(NSString *)styleTitle
{
	self->_styleTitle = [styleTitle copy];

	self.titleField.stringValue = styleTitle;
}

- (void)setStyleDescription:(NSString *)styleDescription
{
	self->_styleDescription = [styleDescription copy];

	self.descriptionField.stringValue = styleDescription;
}

- (void)setStyleName:(NSString *)styleName
{
	self->_styleName = [styleName copy];

	[self rebuildMessages];
}

- (void)setMessageFontSize:(CGFloat)messageFontSize
{
	self->_messageFontSize = messageFontSize;

	[self rebuildMessages];
}

- (void)setSelected:(BOOL)selected
{
	self->_selected = selected;

	[self updateSelectionAppearance];
}

- (void)updateSelectionAppearance
{
	self.checkmarkView.hidden = (self.selected == NO);

	[self updateLayerColors];
}

- (void)viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];

	[self updateLayerColors];
}

- (void)updateLayerColors
{
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
		self.canvas.layer.backgroundColor = [NSColor textBackgroundColor].CGColor;

		if (self.selected) {
			self.canvas.layer.borderColor = [NSColor controlAccentColor].CGColor;
			self.canvas.layer.borderWidth = 2;
		} else {
			self.canvas.layer.borderColor = [NSColor separatorColor].CGColor;
			self.canvas.layer.borderWidth = 1;
		}

		for (NSView *row in self.messageStack.arrangedSubviews) {
			for (NSView *bubble in row.subviews) {
				if (bubble.identifier == nil) {
					continue;
				}

				BOOL outgoing = [bubble.identifier isEqualToString:@"outgoing"];

				bubble.layer.backgroundColor =
					(outgoing ? [NSColor controlAccentColor] : [NSColor unemphasizedSelectedContentBackgroundColor])
						.CGColor;
			}
		}
	}];
}

#pragma mark -
#pragma mark Mockup

- (NSArray<NSArray<NSString *> *> *)sampleMessages
{
	return @[
		@[ TXTLS(@"TDCOnboardingWindow[lf1-n1]"), TXTLS(@"TDCOnboardingWindow[lf1-m1]") ],
		@[ TXTLS(@"TDCOnboardingWindow[lf1-n2]"), TXTLS(@"TDCOnboardingWindow[lf1-m2]") ],
		@[ TXTLS(@"TDCOnboardingWindow[lf1-n3]"), TXTLS(@"TDCOnboardingWindow[lf1-m3]") ],
	];
}

- (void)rebuildMessages
{
	NSStackView *stack = self.messageStack;

	if (stack == nil) {
		return;
	}

	for (NSView *view in [stack.arrangedSubviews copy]) {
		[stack removeArrangedSubview:view];

		[view removeFromSuperview];
	}

	CGFloat fontSize = self.messageFontSize;

	NSArray *messages = [self sampleMessages];

	BOOL bubbles = [self.styleName isEqualToString:@"Bubbles"];

	[messages enumerateObjectsUsingBlock:^(NSArray<NSString *> *message, NSUInteger index, BOOL *stop) {
		BOOL outgoing = (index == (messages.count - 1));

		NSView *row =
			(bubbles ? [self bubbleRowForNickname:message[0] text:message[1] outgoing:outgoing fontSize:fontSize]
					 : [self lineRowForNickname:message[0] text:message[1] outgoing:outgoing fontSize:fontSize]);

		[stack addArrangedSubview:row];
	}];

	[self updateLayerColors];
}

- (NSView *)bubbleRowForNickname:(NSString *)nickname
							text:(NSString *)text
						outgoing:(BOOL)outgoing
						fontSize:(CGFloat)fontSize
{
	NSView *row = [NSView new];

	row.translatesAutoresizingMaskIntoConstraints = NO;

	NSView *bubble = [NSView new];

	bubble.wantsLayer = YES;
	bubble.layer.cornerRadius = 12;
	bubble.identifier = (outgoing ? @"outgoing" : @"incoming");
	bubble.translatesAutoresizingMaskIntoConstraints = NO;

	[row addSubview:bubble];

	NSTextField *textField = [NSTextField wrappingLabelWithString:text];

	textField.font = [NSFont systemFontOfSize:fontSize];
	textField.textColor = (outgoing ? [NSColor whiteColor] : [NSColor labelColor]);
	textField.translatesAutoresizingMaskIntoConstraints = NO;

	[bubble addSubview:textField];

	NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];

	[constraints addObjectsFromArray:@[
		[bubble.topAnchor constraintEqualToAnchor:row.topAnchor],
		[bubble.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
		[bubble.widthAnchor constraintLessThanOrEqualToAnchor:row.widthAnchor multiplier:0.8],
		[textField.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:10],
		[textField.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-10],
		[textField.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-6],
	]];

	if (outgoing) {
		[constraints addObject:[bubble.trailingAnchor constraintEqualToAnchor:row.trailingAnchor]];
		[constraints addObject:[textField.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:6]];
	} else {
		[constraints addObject:[bubble.leadingAnchor constraintEqualToAnchor:row.leadingAnchor]];

		NSTextField *nickField = [NSTextField labelWithString:nickname];

		nickField.font = [NSFont systemFontOfSize:(fontSize - 2) weight:NSFontWeightSemibold];
		nickField.textColor = [NSColor secondaryLabelColor];
		nickField.translatesAutoresizingMaskIntoConstraints = NO;

		[bubble addSubview:nickField];

		[constraints addObjectsFromArray:@[
			[nickField.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:5],
			[nickField.leadingAnchor constraintEqualToAnchor:textField.leadingAnchor],
			[textField.topAnchor constraintEqualToAnchor:nickField.bottomAnchor constant:1],
		]];
	}

	[NSLayoutConstraint activateConstraints:constraints];

	return row;
}

- (NSView *)lineRowForNickname:(NSString *)nickname
						  text:(NSString *)text
					  outgoing:(BOOL)outgoing
					  fontSize:(CGFloat)fontSize
{
	NSView *row = [NSView new];

	row.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *timeField = [NSTextField labelWithString:@"09:41"];

	timeField.font = [NSFont monospacedDigitSystemFontOfSize:(fontSize - 2) weight:NSFontWeightRegular];
	timeField.textColor = [NSColor tertiaryLabelColor];
	timeField.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *nickField = [NSTextField labelWithString:[NSString stringWithFormat:@"<%@>", nickname]];

	nickField.font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold];
	nickField.textColor = (outgoing ? [NSColor controlAccentColor] : [NSColor labelColor]);
	nickField.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *textField = [NSTextField wrappingLabelWithString:text];

	textField.font = [NSFont systemFontOfSize:fontSize];
	textField.translatesAutoresizingMaskIntoConstraints = NO;

	[row addSubview:timeField];
	[row addSubview:nickField];
	[row addSubview:textField];

	[NSLayoutConstraint activateConstraints:@[
		[timeField.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
		[timeField.firstBaselineAnchor constraintEqualToAnchor:textField.firstBaselineAnchor],
		[nickField.leadingAnchor constraintEqualToAnchor:timeField.trailingAnchor constant:8],
		[nickField.firstBaselineAnchor constraintEqualToAnchor:textField.firstBaselineAnchor],
		[textField.leadingAnchor constraintEqualToAnchor:nickField.trailingAnchor constant:6],
		[textField.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor],
		[textField.topAnchor constraintEqualToAnchor:row.topAnchor],
		[textField.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
	]];

	return row;
}

#pragma mark -
#pragma mark Selection

- (void)select
{
	if (self.target && self.action) {
		[NSApp sendAction:self.action to:self.target from:self];
	}
}

- (void)mouseDown:(NSEvent *)event
{
	[self select];
}

@end

NS_ASSUME_NONNULL_END
