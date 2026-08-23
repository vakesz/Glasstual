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

#import "NSStringHelper.h"
#import "IRCClientConfig.h"
#import "IRCNetworkList.h"
#import "IRCServer.h"
#import "TLOLocalization.h"
#import "TDCNetworkPickerViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, TDCNetworkPickerRowKind) {
	TDCNetworkPickerRowKindGroup = 0,
	TDCNetworkPickerRowKindNetwork,
	TDCNetworkPickerRowKindCustom
};

static NSString *const _networkCellIdentifier = @"NetworkCell";
static NSString *const _groupCellIdentifier = @"GroupCell";

#pragma mark -
#pragma mark Row Model

@interface TDCNetworkPickerRow : NSObject
@property(nonatomic, assign) TDCNetworkPickerRowKind kind;
@property(nonatomic, copy, nullable) NSString *title;
@property(nonatomic, strong, nullable) IRCNetwork *network;

+ (instancetype)groupRowWithTitle:(NSString *)title;
+ (instancetype)networkRow:(IRCNetwork *)network;
+ (instancetype)customRow;
@end

@implementation TDCNetworkPickerRow

+ (instancetype)groupRowWithTitle:(NSString *)title
{
	TDCNetworkPickerRow *row = [self new];

	row.kind = TDCNetworkPickerRowKindGroup;
	row.title = title;

	return row;
}

+ (instancetype)networkRow:(IRCNetwork *)network
{
	TDCNetworkPickerRow *row = [self new];

	row.kind = TDCNetworkPickerRowKindNetwork;
	row.network = network;
	row.title = network.networkName;

	return row;
}

+ (instancetype)customRow
{
	TDCNetworkPickerRow *row = [self new];

	row.kind = TDCNetworkPickerRowKindCustom;
	row.title = TXTLS(@"TDCOnboardingWindow[np1-cs]");

	return row;
}

@end

#pragma mark -
#pragma mark Cell View

/* Name on the first line, description on the second, and a lock on the
 trailing edge when the network prefers TLS. */
@interface TDCNetworkPickerCellView : NSTableCellView
@property(nonatomic, strong) NSTextField *descriptionField;
@property(nonatomic, strong) NSImageView *lockImageView;
@end

@implementation TDCNetworkPickerCellView

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
	NSTextField *nameField = [NSTextField labelWithString:@""];

	nameField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	nameField.lineBreakMode = NSLineBreakByTruncatingTail;
	nameField.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *descriptionField = [NSTextField labelWithString:@""];

	descriptionField.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	descriptionField.textColor = [NSColor secondaryLabelColor];
	descriptionField.lineBreakMode = NSLineBreakByTruncatingTail;
	descriptionField.translatesAutoresizingMaskIntoConstraints = NO;

	NSImageView *lockImageView =
		[NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"lock.fill"
												  accessibilityDescription:TXTLS(@"TDCOnboardingWindow[np1-lk]")]];

	lockImageView.contentTintColor = [NSColor secondaryLabelColor];
	lockImageView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithScale:NSImageSymbolScaleSmall];
	lockImageView.translatesAutoresizingMaskIntoConstraints = NO;

	[lockImageView setContentHuggingPriority:NSLayoutPriorityRequired
							  forOrientation:NSLayoutConstraintOrientationHorizontal];

	[self addSubview:nameField];
	[self addSubview:descriptionField];
	[self addSubview:lockImageView];

	[NSLayoutConstraint activateConstraints:@[
		[nameField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
		[nameField.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
		[nameField.trailingAnchor constraintLessThanOrEqualToAnchor:lockImageView.leadingAnchor constant:-8],
		[descriptionField.leadingAnchor constraintEqualToAnchor:nameField.leadingAnchor],
		[descriptionField.topAnchor constraintEqualToAnchor:nameField.bottomAnchor constant:1],
		[descriptionField.trailingAnchor constraintLessThanOrEqualToAnchor:lockImageView.leadingAnchor constant:-8],
		[descriptionField.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-4],
		[lockImageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
		[lockImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
	]];

	self.textField = nameField;
	self.descriptionField = descriptionField;
	self.lockImageView = lockImageView;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
	[super setBackgroundStyle:backgroundStyle];

	/* The description and lock keep their secondary colour when the row
	 is selected in a source list, which already draws a tinted bar. */
}

@end

#pragma mark -
#pragma mark Picker

@interface TDCNetworkPickerViewController () <NSTableViewDataSource,
											  NSTableViewDelegate,
											  NSSearchFieldDelegate,
											  NSTextFieldDelegate>
@property(nonatomic, strong, readwrite) IRCNetworkList *networkList;
@property(nonatomic, strong) NSArray<TDCNetworkPickerRow *> *rows;
@property(nonatomic, strong) NSSearchField *searchField;
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) NSTableView *tableView;
@property(nonatomic, strong) NSView *detailView;
@property(nonatomic, strong) NSTextField *detailTitleField;
@property(nonatomic, strong) NSTextField *registrationBadge;
@property(nonatomic, strong) NSTextField *serverAddressField;
@property(nonatomic, strong) NSTextField *serverPortField;
@property(nonatomic, strong) NSButton *securedCheck;
@property(nonatomic, strong) NSBox *accountBox;
@property(nonatomic, strong) NSTextField *accountNameField;
@property(nonatomic, strong) NSSecureTextField *accountPasswordField;
@property(nonatomic, strong) NSButton *saslCheck;
@property(nonatomic, strong) NSTextField *registrationNoteField;
@property(nonatomic, strong) NSButton *websiteButton;
@property(nonatomic, strong, nullable) IRCNetwork *selectedNetwork;
@property(nonatomic, assign) BOOL customServerSelected;
@property(nonatomic, assign) BOOL accountNameEdited;
@end

@implementation TDCNetworkPickerViewController

- (instancetype)init
{
	if ((self = [super initWithNibName:nil bundle:nil])) {
		self.networkList = [IRCNetworkList new];

		return self;
	}

	return nil;
}

#pragma mark -
#pragma mark View

- (void)loadView
{
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 380)];

	view.translatesAutoresizingMaskIntoConstraints = NO;

	self.view = view;

	[self buildListViews];
	[self buildDetailViews];

	[self reloadRows];

	[self updateDetailView];
}

- (void)buildListViews
{
	NSSearchField *searchField = [NSSearchField new];

	searchField.placeholderString = TXTLS(@"TDCOnboardingWindow[np1-sp]");
	searchField.delegate = self;
	searchField.sendsSearchStringImmediately = YES;
	searchField.translatesAutoresizingMaskIntoConstraints = NO;

	NSTableView *tableView = [NSTableView new];

	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"Network"];

	column.resizingMask = NSTableColumnAutoresizingMask;

	[tableView addTableColumn:column];

	tableView.headerView = nil;
	tableView.style = NSTableViewStyleSourceList;
	tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
	tableView.rowSizeStyle = NSTableViewRowSizeStyleCustom;
	tableView.rowHeight = 38;
	tableView.floatsGroupRows = YES;
	tableView.allowsEmptySelection = YES;
	tableView.allowsMultipleSelection = NO;
	tableView.usesAlternatingRowBackgroundColors = NO;
	tableView.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
	tableView.dataSource = self;
	tableView.delegate = self;
	tableView.target = self;
	tableView.doubleAction = @selector(tableViewDoubleClicked:);
	tableView.accessibilityLabel = TXTLS(@"TDCOnboardingWindow[np1-ax]");

	NSScrollView *scrollView = [NSScrollView new];

	scrollView.documentView = tableView;
	scrollView.hasVerticalScroller = YES;
	scrollView.autohidesScrollers = YES;
	scrollView.borderType = NSBezelBorder;
	scrollView.translatesAutoresizingMaskIntoConstraints = NO;

	[self.view addSubview:searchField];
	[self.view addSubview:scrollView];

	[NSLayoutConstraint activateConstraints:@[
		[searchField.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[searchField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[searchField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[scrollView.topAnchor constraintEqualToAnchor:searchField.bottomAnchor constant:8],
		[scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:120],
	]];

	self.searchField = searchField;
	self.scrollView = scrollView;
	self.tableView = tableView;
}

- (NSTextField *)makeLabel:(NSString *)title
{
	NSTextField *label = [NSTextField labelWithString:title];

	label.alignment = NSTextAlignmentRight;
	label.translatesAutoresizingMaskIntoConstraints = NO;

	return label;
}

- (void)buildDetailViews
{
	NSView *detailView = [NSView new];

	detailView.translatesAutoresizingMaskIntoConstraints = NO;

	/* Header: network name and registration badge */
	NSTextField *titleField = [NSTextField labelWithString:@""];

	titleField.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
	titleField.lineBreakMode = NSLineBreakByTruncatingTail;
	titleField.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *badge = [NSTextField labelWithString:TXTLS(@"TDCOnboardingWindow[np1-rq]")];

	badge.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightMedium];
	badge.textColor = [NSColor systemOrangeColor];
	badge.wantsLayer = YES;
	badge.layer.cornerRadius = 4;
	badge.layer.borderWidth = 1;
	badge.layer.borderColor = [NSColor systemOrangeColor].CGColor;
	badge.alignment = NSTextAlignmentCenter;
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	badge.hidden = YES;

	/* Server row */
	NSTextField *addressLabel = [self makeLabel:TXTLS(@"TDCOnboardingWindow[np1-sv]")];

	NSTextField *addressField = [NSTextField textFieldWithString:@""];

	addressField.placeholderString = TXTLS(@"TDCOnboardingWindow[np1-sh]");
	addressField.delegate = self;
	addressField.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *portLabel = [self makeLabel:TXTLS(@"TDCOnboardingWindow[np1-pt]")];

	NSTextField *portField = [NSTextField textFieldWithString:@""];

	portField.placeholderString = TXTLS(@"TDCOnboardingWindow[np1-pp]");
	portField.delegate = self;
	portField.alignment = NSTextAlignmentRight;
	portField.translatesAutoresizingMaskIntoConstraints = NO;

	NSNumberFormatter *portFormatter = [NSNumberFormatter new];

	portFormatter.numberStyle = NSNumberFormatterNoStyle;
	portFormatter.minimum = @(1);
	portFormatter.maximum = @(65535);
	portFormatter.allowsFloats = NO;
	portFormatter.usesGroupingSeparator = NO;

	portField.formatter = portFormatter;

	NSButton *securedCheck = [NSButton checkboxWithTitle:TXTLS(@"TDCOnboardingWindow[np1-tl]")
												  target:self
												  action:@selector(fieldChanged:)];

	securedCheck.translatesAutoresizingMaskIntoConstraints = NO;

	/* Account group */
	NSBox *accountBox = [NSBox new];

	accountBox.title = TXTLS(@"TDCOnboardingWindow[np1-ac]");
	accountBox.titlePosition = NSAtTop;
	accountBox.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *accountNameLabel = [self makeLabel:TXTLS(@"TDCOnboardingWindow[np1-an]")];

	NSTextField *accountNameField = [NSTextField textFieldWithString:@""];

	accountNameField.delegate = self;
	accountNameField.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *passwordLabel = [self makeLabel:TXTLS(@"TDCOnboardingWindow[np1-pw]")];

	NSSecureTextField *passwordField = [NSSecureTextField new];

	passwordField.delegate = self;
	passwordField.translatesAutoresizingMaskIntoConstraints = NO;

	NSButton *saslCheck = [NSButton checkboxWithTitle:TXTLS(@"TDCOnboardingWindow[np1-sa]")
											   target:self
											   action:@selector(fieldChanged:)];

	saslCheck.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField *noteField = [NSTextField wrappingLabelWithString:@""];

	noteField.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	noteField.textColor = [NSColor secondaryLabelColor];
	noteField.selectable = YES;
	noteField.translatesAutoresizingMaskIntoConstraints = NO;

	[noteField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
										forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSButton *websiteButton = [NSButton buttonWithTitle:@"" target:self action:@selector(openWebsite:)];

	websiteButton.bordered = NO;
	websiteButton.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	websiteButton.contentTintColor = [NSColor linkColor];
	websiteButton.translatesAutoresizingMaskIntoConstraints = NO;

	NSView *accountContent = accountBox.contentView;

	[accountContent addSubview:accountNameLabel];
	[accountContent addSubview:accountNameField];
	[accountContent addSubview:passwordLabel];
	[accountContent addSubview:passwordField];
	[accountContent addSubview:saslCheck];
	[accountContent addSubview:noteField];
	[accountContent addSubview:websiteButton];

	[NSLayoutConstraint activateConstraints:@[
		[accountNameLabel.topAnchor constraintEqualToAnchor:accountContent.topAnchor constant:8],
		[accountNameLabel.leadingAnchor constraintEqualToAnchor:accountContent.leadingAnchor constant:8],
		[accountNameLabel.widthAnchor constraintEqualToConstant:110],
		[accountNameField.leadingAnchor constraintEqualToAnchor:accountNameLabel.trailingAnchor constant:8],
		[accountNameField.trailingAnchor constraintEqualToAnchor:accountContent.trailingAnchor constant:-8],
		[accountNameField.firstBaselineAnchor constraintEqualToAnchor:accountNameLabel.firstBaselineAnchor],
		[passwordLabel.topAnchor constraintEqualToAnchor:accountNameField.bottomAnchor constant:8],
		[passwordLabel.trailingAnchor constraintEqualToAnchor:accountNameLabel.trailingAnchor],
		[passwordLabel.widthAnchor constraintEqualToAnchor:accountNameLabel.widthAnchor],
		[passwordField.leadingAnchor constraintEqualToAnchor:accountNameField.leadingAnchor],
		[passwordField.trailingAnchor constraintEqualToAnchor:accountNameField.trailingAnchor],
		[passwordField.firstBaselineAnchor constraintEqualToAnchor:passwordLabel.firstBaselineAnchor],
		[saslCheck.topAnchor constraintEqualToAnchor:passwordField.bottomAnchor constant:8],
		[saslCheck.leadingAnchor constraintEqualToAnchor:accountNameField.leadingAnchor],
		[noteField.topAnchor constraintEqualToAnchor:saslCheck.bottomAnchor constant:6],
		[noteField.leadingAnchor constraintEqualToAnchor:accountNameField.leadingAnchor],
		[noteField.trailingAnchor constraintEqualToAnchor:accountNameField.trailingAnchor],
		[websiteButton.topAnchor constraintEqualToAnchor:noteField.bottomAnchor constant:2],
		[websiteButton.leadingAnchor constraintEqualToAnchor:accountNameField.leadingAnchor],
		[websiteButton.bottomAnchor constraintEqualToAnchor:accountContent.bottomAnchor constant:-6],
	]];

	[detailView addSubview:titleField];
	[detailView addSubview:badge];
	[detailView addSubview:addressLabel];
	[detailView addSubview:addressField];
	[detailView addSubview:portLabel];
	[detailView addSubview:portField];
	[detailView addSubview:securedCheck];
	[detailView addSubview:accountBox];

	[NSLayoutConstraint activateConstraints:@[
		[titleField.topAnchor constraintEqualToAnchor:detailView.topAnchor],
		[titleField.leadingAnchor constraintEqualToAnchor:detailView.leadingAnchor],
		[badge.leadingAnchor constraintEqualToAnchor:titleField.trailingAnchor constant:8],
		[badge.centerYAnchor constraintEqualToAnchor:titleField.centerYAnchor],
		[badge.trailingAnchor constraintLessThanOrEqualToAnchor:detailView.trailingAnchor],
		[addressLabel.topAnchor constraintEqualToAnchor:titleField.bottomAnchor constant:10],
		[addressLabel.leadingAnchor constraintEqualToAnchor:detailView.leadingAnchor],
		[addressLabel.widthAnchor constraintEqualToConstant:122],
		[addressField.leadingAnchor constraintEqualToAnchor:addressLabel.trailingAnchor constant:8],
		[addressField.firstBaselineAnchor constraintEqualToAnchor:addressLabel.firstBaselineAnchor],
		[portLabel.leadingAnchor constraintEqualToAnchor:addressField.trailingAnchor constant:12],
		[portLabel.firstBaselineAnchor constraintEqualToAnchor:addressLabel.firstBaselineAnchor],
		[portField.leadingAnchor constraintEqualToAnchor:portLabel.trailingAnchor constant:8],
		[portField.widthAnchor constraintEqualToConstant:64],
		[portField.trailingAnchor constraintEqualToAnchor:detailView.trailingAnchor],
		[portField.firstBaselineAnchor constraintEqualToAnchor:addressLabel.firstBaselineAnchor],
		[securedCheck.topAnchor constraintEqualToAnchor:addressField.bottomAnchor constant:8],
		[securedCheck.leadingAnchor constraintEqualToAnchor:addressField.leadingAnchor],
		[accountBox.topAnchor constraintEqualToAnchor:securedCheck.bottomAnchor constant:8],
		[accountBox.leadingAnchor constraintEqualToAnchor:detailView.leadingAnchor],
		[accountBox.trailingAnchor constraintEqualToAnchor:detailView.trailingAnchor],
		[accountBox.bottomAnchor constraintLessThanOrEqualToAnchor:detailView.bottomAnchor],
	]];

	/* The badge needs a little padding around its text. */
	NSLayoutConstraint *badgeWidth =
		[badge.widthAnchor constraintEqualToConstant:(badge.intrinsicContentSize.width + 12)];
	NSLayoutConstraint *badgeHeight =
		[badge.heightAnchor constraintEqualToConstant:(badge.intrinsicContentSize.height + 2)];

	[NSLayoutConstraint activateConstraints:@[ badgeWidth, badgeHeight ]];

	[self.view addSubview:detailView];

	[NSLayoutConstraint activateConstraints:@[
		[detailView.topAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:12],
		[detailView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[detailView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[detailView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	self.detailView = detailView;
	self.detailTitleField = titleField;
	self.registrationBadge = badge;
	self.serverAddressField = addressField;
	self.serverPortField = portField;
	self.securedCheck = securedCheck;
	self.accountBox = accountBox;
	self.accountNameField = accountNameField;
	self.accountPasswordField = passwordField;
	self.saslCheck = saslCheck;
	self.registrationNoteField = noteField;
	self.websiteButton = websiteButton;
}

#pragma mark -
#pragma mark Rows

- (void)reloadRows
{
	NSString *query = self.searchField.stringValue.trim;

	NSMutableArray<TDCNetworkPickerRow *> *rows = [NSMutableArray array];

	if (query.length == 0) {
		[rows addObject:[TDCNetworkPickerRow groupRowWithTitle:TXTLS(@"TDCOnboardingWindow[np1-gp]")]];

		for (IRCNetwork *network in self.networkList.popularNetworks) {
			[rows addObject:[TDCNetworkPickerRow networkRow:network]];
		}

		[rows addObject:[TDCNetworkPickerRow groupRowWithTitle:TXTLS(@"TDCOnboardingWindow[np1-ga]")]];

		for (IRCNetwork *network in self.networkList.listOfNetworks) {
			[rows addObject:[TDCNetworkPickerRow networkRow:network]];
		}
	} else {
		for (IRCNetwork *network in self.networkList.listOfNetworks) {
			if ([network.networkName containsIgnoringCase:query] ||
				[network.serverAddress containsIgnoringCase:query] ||
				[network.networkDescription containsIgnoringCase:query]) {
				[rows addObject:[TDCNetworkPickerRow networkRow:network]];
			}
		}
	}

	[rows addObject:[TDCNetworkPickerRow customRow]];

	self.rows = rows;

	[self.tableView reloadData];

	[self restoreSelectionInTable];
}

/* Keeps the current selection highlighted after the rows change. */
- (void)restoreSelectionInTable
{
	NSInteger rowToSelect = -1;

	if (self.customServerSelected) {
		rowToSelect = (self.rows.count - 1);
	} else if (self.selectedNetwork) {
		IRCNetwork *selectedNetwork = self.selectedNetwork;

		NSUInteger index =
			[self.rows indexOfObjectPassingTest:^BOOL(TDCNetworkPickerRow *row, NSUInteger idx, BOOL *stop) {
				return (row.kind == TDCNetworkPickerRowKindNetwork && row.network == selectedNetwork);
			}];

		if (index != NSNotFound) {
			rowToSelect = index;
		}
	}

	if (rowToSelect < 0) {
		[self.tableView deselectAll:nil];
	} else {
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:rowToSelect] byExtendingSelection:NO];

		[self.tableView scrollRowToVisible:rowToSelect];
	}
}

#pragma mark -
#pragma mark Selection

- (BOOL)hasSelection
{
	return (self.selectedNetwork != nil || self.customServerSelected);
}

- (void)selectNetwork:(IRCNetwork *)network
{
	NSParameterAssert(network != nil);

	self.selectedNetwork = network;
	self.customServerSelected = NO;
	self.accountNameEdited = NO;

	[self populateDetailFromSelection];

	[self restoreSelectionInTable];

	[self informDelegateSelectionChanged];
}

- (void)selectServerAddress:(NSString *)serverAddress port:(uint16_t)port secured:(BOOL)secured
{
	NSParameterAssert(serverAddress != nil);

	IRCNetwork *network = [self.networkList networkWithServerAddress:serverAddress];

	if (network == nil) {
		network = [self.networkList networkNamed:serverAddress];
	}

	if (network) {
		[self selectNetwork:network];

		return;
	}

	self.selectedNetwork = nil;
	self.customServerSelected = YES;
	self.accountNameEdited = NO;

	[self populateDetailFromSelection];

	self.serverAddressField.stringValue = serverAddress;

	if (port > 0) {
		self.serverPortField.integerValue = port;
	}

	self.securedCheck.state = (secured ? NSControlStateValueOn : NSControlStateValueOff);

	[self restoreSelectionInTable];

	[self informDelegateSelectionChanged];
}

- (void)clearSelection
{
	self.selectedNetwork = nil;
	self.customServerSelected = NO;
	self.accountNameEdited = NO;

	[self populateDetailFromSelection];

	[self restoreSelectionInTable];

	[self informDelegateSelectionChanged];
}

- (void)selectRowAtIndex:(NSInteger)index
{
	if (index < 0 || (NSUInteger)index >= self.rows.count) {
		self.selectedNetwork = nil;
		self.customServerSelected = NO;
	} else {
		TDCNetworkPickerRow *row = self.rows[index];

		switch (row.kind) {
		case TDCNetworkPickerRowKindNetwork: {
			if (row.network == self.selectedNetwork) {
				return;
			}

			self.selectedNetwork = row.network;
			self.customServerSelected = NO;

			break;
		}
		case TDCNetworkPickerRowKindCustom: {
			if (self.customServerSelected) {
				return;
			}

			self.selectedNetwork = nil;
			self.customServerSelected = YES;

			break;
		}
		default: {
			return;
		}
		}
	}

	self.accountNameEdited = NO;

	[self populateDetailFromSelection];

	[self informDelegateSelectionChanged];
}

- (void)populateDetailFromSelection
{
	IRCNetwork *network = self.selectedNetwork;

	if (network) {
		self.detailTitleField.stringValue = network.networkName;
		self.serverAddressField.stringValue = network.serverAddress;
		self.serverPortField.integerValue = network.serverPort;
		self.securedCheck.state = (network.prefersSecuredConnection ? NSControlStateValueOn : NSControlStateValueOff);
		self.saslCheck.state = (network.saslSupported ? NSControlStateValueOn : NSControlStateValueOff);
		self.saslCheck.enabled = network.saslSupported;
		self.registrationNoteField.stringValue = (network.registrationNote ?: @"");
		self.registrationBadge.hidden = (network.registration != IRCNetworkRegistrationRequired);

		if (network.website.length > 0) {
			self.websiteButton.title = network.website;
			self.websiteButton.hidden = NO;
		} else {
			self.websiteButton.title = @"";
			self.websiteButton.hidden = YES;
		}
	} else {
		self.detailTitleField.stringValue = TXTLS(@"TDCOnboardingWindow[np1-cs]");
		self.serverAddressField.stringValue = @"";
		self.serverPortField.stringValue = TXTLS(@"TDCOnboardingWindow[np1-pp]");
		self.securedCheck.state = NSControlStateValueOn;
		self.saslCheck.state = NSControlStateValueOn;
		self.saslCheck.enabled = YES;
		self.registrationNoteField.stringValue = @"";
		self.registrationBadge.hidden = YES;
		self.websiteButton.title = @"";
		self.websiteButton.hidden = YES;
	}

	self.accountNameField.stringValue = (self.defaultNickname ?: @"");
	self.accountPasswordField.stringValue = @"";

	[self updateDetailView];
}

- (void)updateDetailView
{
	self.detailView.hidden = (self.hasSelection == NO);

	IRCNetwork *network = self.selectedNetwork;

	/* A custom server may have services; the group stays available. */
	BOOL showAccount = (network == nil || network.accountFieldsApply);

	self.accountBox.hidden = (showAccount == NO);
}

- (void)setDefaultNickname:(nullable NSString *)defaultNickname
{
	self->_defaultNickname = [defaultNickname copy];

	if (self.accountNameEdited == NO) {
		self.accountNameField.stringValue = (defaultNickname ?: @"");
	}
}

- (void)informDelegateSelectionChanged
{
	if ([self.delegate respondsToSelector:@selector(networkPickerSelectionDidChange:)]) {
		[self.delegate networkPickerSelectionDidChange:self];
	}
}

#pragma mark -
#pragma mark Values

- (NSString *)serverAddress
{
	return self.serverAddressField.stringValue.trim.lowercaseString;
}

- (uint16_t)serverPort
{
	NSInteger port = self.serverPortField.integerValue;

	if (port <= 0 || port > UINT16_MAX) {
		return 0;
	}

	return (uint16_t)port;
}

- (BOOL)prefersSecuredConnection
{
	return (self.securedCheck.state == NSControlStateValueOn);
}

- (NSString *)accountName
{
	if (self.accountBox.hidden) {
		return @"";
	}

	return self.accountNameField.stringValue.trim;
}

- (NSString *)accountPassword
{
	if (self.accountBox.hidden) {
		return @"";
	}

	return self.accountPasswordField.stringValue;
}

- (BOOL)usesSASL
{
	if (self.accountBox.hidden) {
		return NO;
	}

	return (self.saslCheck.state == NSControlStateValueOn && self.accountPassword.length > 0);
}

- (NSArray<NSString *> *)suggestedChannels
{
	return (self.selectedNetwork.suggestedChannels ?: @[]);
}

- (BOOL)validateWithError:(NSString *_Nullable *_Nullable)errorDescription
{
	if (self.hasSelection == NO) {
		if (errorDescription) {
			*errorDescription = TXTLS(@"TDCOnboardingWindow[np1-e1]");
		}

		return NO;
	}

	if (self.serverAddress.isValidInternetAddress == NO) {
		if (errorDescription) {
			*errorDescription = TXTLS(@"CommonErrors[yyx-l3]");
		}

		return NO;
	}

	if (self.serverPort == 0) {
		if (errorDescription) {
			*errorDescription = TXTLS(@"TDCOnboardingWindow[np1-e2]");
		}

		return NO;
	}

	return YES;
}

- (nullable IRCClientConfigMutable *)clientConfig
{
	if ([self validateWithError:NULL] == NO) {
		return nil;
	}

	IRCClientConfigMutable *config = [IRCClientConfigMutable new];

	IRCNetwork *network = self.selectedNetwork;

	if (network) {
		config.connectionName = network.networkName;
	} else {
		config.connectionName = self.serverAddress;
	}

	IRCServerMutable *server = [IRCServerMutable new];

	server.serverAddress = self.serverAddress;
	server.serverPort = self.serverPort;
	server.prefersSecuredConnection = self.prefersSecuredConnection;

	config.serverList = @[ [server copy] ];

	NSString *password = self.accountPassword;

	if (password.length > 0) {
		/* The password is handed to NickServ when it asks and to SASL when
		 the server offers it. SASL authenticates as the username, so the
		 account name is only applied as the username when SASL is wanted. */
		config.nicknamePassword = password;

		NSString *accountName = self.accountName;

		if (self.usesSASL && accountName.length > 0) {
			config.username = accountName;
		}
	}

	return config;
}

#pragma mark -
#pragma mark Actions

- (void)focusSearchField
{
	[self.view.window makeFirstResponder:self.searchField];
}

- (void)fieldChanged:(nullable id)sender
{
	[self informDelegateSelectionChanged];
}

- (void)openWebsite:(nullable id)sender
{
	NSString *website = self.selectedNetwork.website;

	if (website.length == 0) {
		return;
	}

	NSURL *url = [NSURL URLWithString:website];

	if (url) {
		[[NSWorkspace sharedWorkspace] openURL:url];
	}
}

- (void)tableViewDoubleClicked:(nullable id)sender
{
	if (self.hasSelection == NO) {
		return;
	}

	if ([self.delegate respondsToSelector:@selector(networkPickerDidConfirmSelection:)]) {
		[self.delegate networkPickerDidConfirmSelection:self];
	}
}

#pragma mark -
#pragma mark Text Field Delegate

- (void)controlTextDidChange:(NSNotification *)notification
{
	id object = notification.object;

	if (object == self.searchField) {
		[self reloadRows];

		return;
	}

	if (object == self.accountNameField) {
		self.accountNameEdited = YES;
	}

	[self informDelegateSelectionChanged];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
	if (control != self.searchField) {
		return NO;
	}

	/* Arrow keys in the search field move the list selection. */
	if (commandSelector == @selector(moveDown:)) {
		[self moveListSelectionBy:1];

		return YES;
	}

	if (commandSelector == @selector(moveUp:)) {
		[self moveListSelectionBy:-1];

		return YES;
	}

	if (commandSelector == @selector(insertNewline:)) {
		if (self.hasSelection == NO) {
			[self moveListSelectionBy:1];
		}

		return NO;
	}

	return NO;
}

- (void)moveListSelectionBy:(NSInteger)delta
{
	NSInteger row = self.tableView.selectedRow;

	NSInteger count = self.rows.count;

	for (NSInteger next = (row + delta); next >= 0 && next < count; next += delta) {
		if (self.rows[next].kind == TDCNetworkPickerRowKindGroup) {
			continue;
		}

		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:next] byExtendingSelection:NO];

		[self.tableView scrollRowToVisible:next];

		return;
	}
}

#pragma mark -
#pragma mark Table View

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.rows.count;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
	return (self.rows[row].kind == TDCNetworkPickerRowKindGroup);
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	return (self.rows[row].kind != TDCNetworkPickerRowKindGroup);
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	if (self.rows[row].kind == TDCNetworkPickerRowKindGroup) {
		return 22;
	}

	return 38;
}

- (nullable NSView *)tableView:(NSTableView *)tableView
			viewForTableColumn:(nullable NSTableColumn *)tableColumn
						   row:(NSInteger)row
{
	TDCNetworkPickerRow *rowObject = self.rows[row];

	if (rowObject.kind == TDCNetworkPickerRowKindGroup) {
		NSTableCellView *cell = [tableView makeViewWithIdentifier:_groupCellIdentifier owner:self];

		if (cell == nil) {
			cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];

			cell.identifier = _groupCellIdentifier;

			NSTextField *label = [NSTextField labelWithString:@""];

			label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightSemibold];
			label.textColor = [NSColor secondaryLabelColor];
			label.translatesAutoresizingMaskIntoConstraints = NO;

			[cell addSubview:label];

			[NSLayoutConstraint activateConstraints:@[
				[label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
				[label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
			]];

			cell.textField = label;
		}

		cell.textField.stringValue = (rowObject.title ?: @"");

		return cell;
	}

	TDCNetworkPickerCellView *cell = [tableView makeViewWithIdentifier:_networkCellIdentifier owner:self];

	if (cell == nil) {
		cell = [[TDCNetworkPickerCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 38)];

		cell.identifier = _networkCellIdentifier;
	}

	IRCNetwork *network = rowObject.network;

	if (network) {
		cell.textField.stringValue = network.networkName;
		cell.descriptionField.stringValue = network.networkDescription;
		cell.lockImageView.hidden = (network.prefersSecuredConnection == NO);
		cell.toolTip = network.serverAddress;
	} else {
		cell.textField.stringValue = (rowObject.title ?: @"");
		cell.descriptionField.stringValue = TXTLS(@"TDCOnboardingWindow[np1-cd]");
		cell.lockImageView.hidden = YES;
		cell.toolTip = nil;
	}

	return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self selectRowAtIndex:self.tableView.selectedRow];
}

@end

NS_ASSUME_NONNULL_END
