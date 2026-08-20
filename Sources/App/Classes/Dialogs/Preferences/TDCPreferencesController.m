/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

#import "NSViewHelper.h"
#import "TXMasterController.h"
#import "TXMenuController.h"
#import "TPCPathInfoPrivate.h"
#import "TPCPreferencesLocalPrivate.h"
#import "TPCPreferencesReload.h"
#import "TPCPreferencesUserDefaults.h"
#import "TPCThemeControllerPrivate.h"
#import "THOPluginManagerPrivate.h"
#import "IRC.h"
#import "IRCClientConfig.h"
#import "IRCClient.h"
#import "IRCConnectionConfig.h"
#import "IRCWorld.h"
#import "TLOEncryptionManagerPrivate.h"
#import "TLOLocalization.h"
#import "TLOpenLink.h"
#import "TVCMainWindowPrivate.h"
#import "TVCLogControllerInlineMediaServicePrivate.H"
#import "TVCNotificationConfigurationViewControllerPrivate.h"
#import "TDCAlert.h"
#import "TDCFileTransferDialogPrivate.h"
#import "TDCPreferencesNotificationConfigurationPrivate.h"
#import "TDCPreferencesUserStyleSheetPrivate.h"
#import "TDCPreferencesControllerPrivate.h"

#if GLASSTUAL_BUILT_WITH_SPARKLE_ENABLED == 1
#import <Sparkle/Sparkle.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface TXColorUnarchiveFromDataTransformer : NSSecureUnarchiveFromDataTransformer
@end

@implementation TXColorUnarchiveFromDataTransformer

+ (void)load
{
	[NSValueTransformer setValueTransformer:[self new] forName:@"TXColorUnarchiveFromData"];
}

+ (Class)transformedValueClass
{
	return [NSColor class];
}

+ (BOOL)allowsReverseTransformation
{
	return YES;
}

+ (NSArray<Class> *)allowedTopLevelClasses
{
	return [[super allowedTopLevelClasses] arrayByAddingObject:[NSColor class]];
}

- (nullable id)transformedValue:(nullable id)value
{
	if ([value isKindOfClass:[NSColor class]]) {
		return value;
	}

	if ([value isKindOfClass:[NSData class]] == NO) {
		return nil;
	}

	return [NSKeyedUnarchiver legacyCompatUnarchivedObjectOfClass:[NSColor class] fromData:value];
}

- (nullable id)reverseTransformedValue:(nullable id)value
{
	if ([value isKindOfClass:[NSColor class]] == NO) {
		return nil;
	}

	return [NSKeyedArchiver archivedDataWithRootObject:value requiringSecureCoding:YES error:NULL];
}

@end

#define _scrollbackSaveLinesMin 100
#define _scrollbackSaveLinesMax 50000
#define _scrollbackVisibleLinesMin 100
#define _scrollbackVisibleLinesMax 15000
#define _inlineMediaWidthMax 2000
#define _inlineMediaWidthMin 40
#define _inlineMediaHeightMax 6000
#define _inlineMediaHeightMin 0

#define _fileTransferPortRangeMin 1024
#define _fileTransferPortRangeMax TXMaximumTCPPort

#define _unsignedIntegerString(_value_) [NSString stringWithUnsignedInteger:_value_]

#define _sidebarMinimumWidth 200.0
#define _sidebarMaximumWidth 260.0
#define _sidebarPreferredWidth 215.0

#define _paneContentInset 20.0

#define _windowMinimumWidth 980.0
#define _windowMinimumHeight 600.0

#define _selectedPaneDefaultsKey @"TDCPreferencesController -> Selected Pane"

static NSToolbarItemIdentifier const _toolbarItemBack = @"TDCPreferencesControllerBack";
static NSToolbarItemIdentifier const _toolbarItemForward = @"TDCPreferencesControllerForward";

static NSUserInterfaceItemIdentifier const _sidebarPaneCellIdentifier = @"TDCPreferencesControllerPaneCell";
static NSUserInterfaceItemIdentifier const _sidebarGroupCellIdentifier = @"TDCPreferencesControllerGroupCell";

#pragma mark -
#pragma mark Sidebar Model

/* One row of the settings sidebar: either a pane or a group header
 that owns a list of panes. */
@interface TDCPreferencesSidebarItem : NSObject
@property(nonatomic, copy, nullable) NSString *identifier;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy, nullable) NSString *symbolName;
@property(nonatomic, copy, nullable) NSArray<TDCPreferencesSidebarItem *> *children;
@property(readonly) BOOL isGroup;
@end

@implementation TDCPreferencesSidebarItem

- (BOOL)isGroup
{
	return (self.children != nil);
}

@end

/* Document view of the pane scroll view. Flipped so that the pane
 sits at the top of the scroll view rather than the bottom. */
@interface TDCPreferencesPaneContainerView : NSView
@end

@implementation TDCPreferencesPaneContainerView

- (BOOL)isFlipped
{
	return YES;
}

@end

@interface TDCPreferencesController () <NSOutlineViewDataSource,
										NSOutlineViewDelegate,
										NSToolbarDelegate,
										NSToolbarItemValidation>
@property(nonatomic, strong) IBOutlet NSArrayController *excludeKeywordsArrayController;
@property(nonatomic, strong) IBOutlet NSArrayController *highlightKeywordsArrayController;
@property(nonatomic, strong) IBOutlet NSArrayController *installedScriptsController;
@property(nonatomic, weak) IBOutlet NSButton *addExcludeKeywordButton;
@property(nonatomic, weak) IBOutlet NSButton *highlightNicknameButton;
@property(nonatomic, weak) IBOutlet NSPopUpButton *themeSelectionButton;
@property(nonatomic, weak) IBOutlet NSPopUpButton *transcriptFolderButton;
@property(nonatomic, weak) IBOutlet NSPopUpButton *fileTransferDownloadDestinationButton;
@property(nonatomic, weak) IBOutlet NSTableView *excludeKeywordsTable;
@property(nonatomic, weak) IBOutlet NSTableView *installedScriptsTable;
@property(nonatomic, weak) IBOutlet NSTableView *highlightKeywordsTable;
@property(nonatomic, weak) IBOutlet NSTextField *fileTransferManuallyEnteredIPAddressTextField;
@property(nonatomic, assign) BOOL fontPanelIsOwned;
@property(nonatomic, assign, nullable) SEL previousFontManagerAction;
@property(nonatomic, strong) IBOutlet NSView *contentViewGeneral;
@property(nonatomic, strong) IBOutlet NSView *contentViewHighlights;
@property(nonatomic, strong) IBOutlet NSView *contentViewNotifications;
@property(nonatomic, strong) IBOutlet NSView *contentViewBehavior;
@property(nonatomic, strong) IBOutlet NSView *contentViewControls;
@property(nonatomic, strong) IBOutlet NSView *contentViewInterface;
@property(nonatomic, strong) IBOutlet NSView *contentViewStyle;
@property(nonatomic, strong) IBOutlet NSView *contentViewInstalledAddons;
@property(nonatomic, strong) IBOutlet NSView *contentViewChannelManagement;
@property(nonatomic, strong) IBOutlet NSView *contentViewCommandScope;
@property(nonatomic, strong) IBOutlet NSView *contentViewCompatibility;
@property(nonatomic, strong) IBOutlet NSView *contentViewFloodControl;
@property(nonatomic, strong) IBOutlet NSView *contentViewIncomingData;
@property(nonatomic, strong) IBOutlet NSView *contentViewFileTransfers;
@property(nonatomic, strong) IBOutlet NSView *contentViewInlineMedia;
@property(nonatomic, strong) IBOutlet NSView *contentViewLogLocation;
@property(nonatomic, strong) IBOutlet NSView *contentViewDefaultIdentity;
@property(nonatomic, strong) IBOutlet NSView *contentViewDefaultIRCopMessages;

#if GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION == 1
@property(nonatomic, strong) IBOutlet NSView *contentViewOffRecordMessaging;
#endif

@property(nonatomic, strong) IBOutlet NSView *contentViewHiddenPreferences;
@property(nonatomic, weak) IBOutlet NSButton *checkForUpdatesDontCheck;
@property(nonatomic, weak) IBOutlet NSButton *checkForUpdatesAutomaticallyCheck;
@property(nonatomic, weak) IBOutlet NSButton *checkForUpdatesAutomaticallyDownload;
@property(nonatomic, weak) IBOutlet NSButton *forwardNoticeToServerConsoleButton;
@property(nonatomic, weak) IBOutlet NSButton *forwardNoticeToSelectedChannelButton;
@property(nonatomic, weak) IBOutlet NSButton *forwardNoticeToQueryButton;
@property(nonatomic, weak) IBOutlet NSButton *inlineMediaEnabledButton;
@property(nonatomic, weak) IBOutlet NSStackView *contentViewGeneralStackView;
@property(nonatomic, weak) IBOutlet NSView *contentViewGeneralCheckForUpdatesView;
@property(nonatomic, weak) IBOutlet NSView *contentViewGeneralShareDataView;
@property(nonatomic, strong) NSSplitViewController *splitViewController;
@property(nonatomic, strong) NSOutlineView *sidebarOutlineView;
@property(nonatomic, strong) NSScrollView *paneScrollView;
@property(nonatomic, strong) TDCPreferencesPaneContainerView *paneContainerView;
@property(nonatomic, strong, nullable) NSView *presentedPaneView;
@property(nonatomic, copy) NSArray<TDCPreferencesSidebarItem *> *sidebarItems;
@property(nonatomic, copy) NSArray<TDCPreferencesSidebarItem *> *sidebarPaneItems;
@property(nonatomic, copy, nullable) NSString *selectedPaneIdentifier;
@property(nonatomic, strong) NSMutableArray<NSString *> *paneHistory;
@property(nonatomic, assign) NSUInteger paneHistoryIndex;
@property(nonatomic, assign) BOOL navigatingPaneHistory;
@property(nonatomic, assign) BOOL updatingSidebarSelection;
@property(nonatomic, assign) BOOL reloadingTheme;
@property(nonatomic, assign) BOOL reloadingThemeBySelection;
@property(nonatomic, weak) IBOutlet NSView *notificationControllerHostView;
@property(nonatomic, strong) IBOutlet TVCNotificationConfigurationViewController *notificationController;
@property(nonatomic, strong, nullable) TDCPreferencesUserStyleSheet *userStyleSheet;

- (IBAction)onAddExcludeKeyword:(nullable id)sender;
- (IBAction)onAddHighlightKeyword:(nullable id)sender; // changed
- (IBAction)onChangedAppearance:(nullable id)sender;
- (IBAction)onChangedCheckForUpdates:(nullable id)sender;
- (IBAction)onChangedCheckForBetaUpdates:(nullable id)sender;
- (IBAction)onChangedChannelViewArrangement:(nullable id)sender;
- (IBAction)onChangedDisableNicknameColorHashing:(nullable id)sender;
- (IBAction)onChangedForwardNoticeTo:(nullable id)sender;
- (IBAction)onChangedHighlightLogging:(nullable id)sender;
- (IBAction)onChangedHighlightType:(nullable id)sender;
- (IBAction)onChangedInlineMediaOption:(nullable id)sender;
- (IBAction)onChangedInputHistoryScheme:(nullable id)sender;
- (IBAction)onChangedMainInputTextViewFontSize:(nullable id)sender; // changed
- (IBAction)onChangedScrollbackSaveLimit:(nullable id)sender;
- (IBAction)onChangedScrollbackVisibleLimit:(nullable id)sender;
- (IBAction)onChangedServerListUnreadBadgeColor:(nullable id)sender;
- (IBAction)onChangedTheme:(nullable id)sender;
- (IBAction)onChangedThemeSelection:(nullable id)sender; // changed
- (IBAction)onChangedTranscriptFolder:(nullable id)sender;
- (IBAction)onChangedUserListModeColor:(nullable id)sender;
- (IBAction)onChangedUserListModeSortOrder:(nullable id)sender;
- (IBAction)onFileTransferDownloadDestinationFolderChanged:(nullable id)sender;
- (IBAction)onFileTransferIPAddressDetectionMethodChanged:(nullable id)sender;
- (IBAction)onModifyUserStyleSheetRules:(nullable id)sender;
- (IBAction)onOpenPathToScripts:(nullable id)sender;
- (IBAction)onOpenPathToTheme:(nullable id)sender; // changed
- (IBAction)onResetServerListUnreadBadgeColorsToDefault:(nullable id)sender;
- (IBAction)onResetUserListModeColorsToDefaults:(nullable id)sender;
- (IBAction)onSelectNewFont:(nullable id)sender;

#if GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION == 1
- (IBAction)offRecordMessagingPolicyChanged:(nullable id)sender;
- (IBAction)offRecordMessagingOpenOfficialWebsite:(nullable id)sender;
#endif
@end

@implementation TDCPreferencesController

- (instancetype)init
{
	if ((self = [super init])) {
		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	[RZMainBundle() loadNibNamed:@"TDCPreferences" owner:self topLevelObjects:nil];
}

- (void)awakeFromNib
{
	[super awakeFromNib];

	NSMutableArray *notifications = [NSMutableArray array];

	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeAddressBookMatch]];
	[notifications addObject:@" "];
	[notifications addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeConnect]];
	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeDisconnect]];
	[notifications addObject:@" "];
	[notifications addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeHighlight]];
	[notifications addObject:@" "];
	[notifications addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeInvite]];
	[notifications addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeKick]];
	[notifications addObject:@" "];
	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeChannelMessage]];
	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeChannelNotice]];
	[notifications addObject:@" "];
	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeNewPrivateMessage]];
	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypePrivateMessage]];
	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypePrivateNotice]];
	[notifications addObject:@" "];
	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeUserJoined]];
	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeUserParted]];
	[notifications
		addObject:[TDCPreferencesNotificationConfiguration objectWithEventType:TXNotificationTypeUserDisconnected]];
	[notifications addObject:@" "];
	[notifications addObject:[TDCPreferencesNotificationConfiguration
								 objectWithEventType:TXNotificationTypeFileTransferReceiveRequested]];
	[notifications addObject:@" "];
	[notifications addObject:[TDCPreferencesNotificationConfiguration
								 objectWithEventType:TXNotificationTypeFileTransferSendSuccessful]];
	[notifications addObject:[TDCPreferencesNotificationConfiguration
								 objectWithEventType:TXNotificationTypeFileTransferReceiveSuccessful]];
	[notifications addObject:@" "];
	[notifications addObject:[TDCPreferencesNotificationConfiguration
								 objectWithEventType:TXNotificationTypeFileTransferSendFailed]];
	[notifications addObject:[TDCPreferencesNotificationConfiguration
								 objectWithEventType:TXNotificationTypeFileTransferReceiveFailed]];

	self.notificationController.notifications = notifications;

	[self.notificationController attachToView:self.notificationControllerHostView];

	[self updateCheckForUpdatesMatrix];
	[self updateFileTransferDownloadDestinationFolder];
	[self updateForwardNoticeToMatrix];
	[self updateInlineMediaEnabled];
	[self updateThemeSelection];
	[self updateTranscriptFolder];

	[self onChangedHighlightType:nil];

	[self onFileTransferIPAddressDetectionMethodChanged:nil];

	self.installedScriptsTable.sortDescriptors =
		@[ [NSSortDescriptor sortDescriptorWithKey:@"string"
										 ascending:YES
										  selector:@selector(caseInsensitiveCompare:)] ];

	[RZNotificationCenter() addObserver:self
							   selector:@selector(onThemeListDidChange:)
								   name:TPCThemeControllerThemeListDidChangeNotification
								 object:nil];

	[RZNotificationCenter() addObserver:self
							   selector:@selector(onThemeWillReload:)
								   name:TVCMainWindowWillReloadThemeNotification
								 object:nil];

	[RZNotificationCenter() addObserver:self
							   selector:@selector(onThemeReloadComplete:)
								   name:TVCMainWindowDidReloadThemeNotification
								 object:nil];

#if GLASSTUAL_BUILT_WITH_SPARKLE_ENABLED == 0
	/* Hide preferences for updates when support is not enabled. */
	[self.contentViewGeneralStackView setVisibilityPriority:NSStackViewVisibilityPriorityNotVisible
													forView:self.contentViewGeneralCheckForUpdatesView];
#endif

	[self.contentViewGeneral layoutSubtreeIfNeeded];

	[self installAccessibilityLabels];

	[self installSettingsShell];

	[self restoreWindowFrame];
}

#pragma mark -
#pragma mark Utilities

- (void)show
{
	[self show:TDCPreferencesControllerSelectionDefault];
}

- (void)show:(TDCPreferencesControllerSelection)selection
{
	NSString *identifier = @"general";

	switch (selection) {
	case TDCPreferencesControllerSelectionNotifications: {
		identifier = @"notifications";
		break;
	}
	case TDCPreferencesControllerSelectionStyle: {
		identifier = @"style";
		break;
	}
	case TDCPreferencesControllerSelectionHiddenPreferences: {
		identifier = @"hidden";
		break;
	}
	default: {
		break;
	}
	}

	if (selection == TDCPreferencesControllerSelectionDefault) {
		NSString *rememberedIdentifier = [RZUserDefaults() objectForKey:_selectedPaneDefaultsKey];

		if ([rememberedIdentifier isKindOfClass:[NSString class]] &&
			[self viewForSettingsPaneIdentifier:rememberedIdentifier]) {
			identifier = rememberedIdentifier;
		}
	}

	[self selectPaneWithIdentifier:identifier];

	[super show];
}

#pragma mark -
#pragma mark Settings Panes

/* Group identifiers used to build the sidebar's sections. */
#define _settingsGroupMain @"main"
#define _settingsGroupAddons @"addons"
#define _settingsGroupAdvanced @"advanced"

/* One table drives the sidebar and the pane lookup. Keeping them in a
 single place is deliberate: when they were separate switch statements
 the Compatibility pane silently fell out of the sidebar while remaining
 reachable everywhere else. */
typedef struct {
	__unsafe_unretained NSString *identifier;
	__unsafe_unretained NSString *symbolName;
	__unsafe_unretained NSString *contentViewKey;
	__unsafe_unretained NSString *group;
} TDCPreferencesSettingsPane;

static const TDCPreferencesSettingsPane _settingsPanes[] = {
	{@"general", @"gearshape", @"contentViewGeneral", _settingsGroupMain},
	{@"behavior", @"slider.horizontal.3", @"contentViewBehavior", _settingsGroupMain},
	{@"notifications", @"bell", @"contentViewNotifications", _settingsGroupMain},
	{@"highlights", @"text.magnifyingglass", @"contentViewHighlights", _settingsGroupMain},
	{@"interface", @"macwindow", @"contentViewInterface", _settingsGroupMain},
	{@"style", @"paintbrush", @"contentViewStyle", _settingsGroupMain},
	{@"controls", @"keyboard", @"contentViewControls", _settingsGroupMain},

	{@"addons", @"puzzlepiece.extension", @"contentViewInstalledAddons", _settingsGroupAddons},

	{@"channelManagement", @"person.2", @"contentViewChannelManagement", _settingsGroupAdvanced},
	{@"commandScope", @"terminal", @"contentViewCommandScope", _settingsGroupAdvanced},
	{@"compatibility", @"wrench.and.screwdriver", @"contentViewCompatibility", _settingsGroupAdvanced},
	{@"floodControl", @"timer", @"contentViewFloodControl", _settingsGroupAdvanced},
	{@"incomingData", @"arrow.down.circle", @"contentViewIncomingData", _settingsGroupAdvanced},
	{@"fileTransfers", @"arrow.down.app", @"contentViewFileTransfers", _settingsGroupAdvanced},
	{@"inlineMedia", @"photo", @"contentViewInlineMedia", _settingsGroupAdvanced},
	{@"logLocation", @"folder", @"contentViewLogLocation", _settingsGroupAdvanced},
	{@"defaultIdentity", @"person.crop.circle", @"contentViewDefaultIdentity", _settingsGroupAdvanced},
	{@"defaultIRCopMessages", @"shield", @"contentViewDefaultIRCopMessages", _settingsGroupAdvanced},
#if GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION == 1
	{@"offRecordMessaging", @"lock.fill", @"contentViewOffRecordMessaging", _settingsGroupAdvanced},
#endif
	{@"hidden", @"eye.slash", @"contentViewHiddenPreferences", _settingsGroupAdvanced},
};

static const NSUInteger _settingsPaneCount = (sizeof(_settingsPanes) / sizeof(TDCPreferencesSettingsPane));

static NSString *TDCPreferencesSettingsPluginIdentifier(NSUInteger index)
{
	return [NSString stringWithFormat:@"plugin-%lu", (unsigned long)index];
}

static const TDCPreferencesSettingsPane *_Nullable TDCPreferencesSettingsPaneForIdentifier(NSString *identifier)
{
	for (NSUInteger i = 0; i < _settingsPaneCount; i++) {
		if ([_settingsPanes[i].identifier isEqualToString:identifier]) {
			return &_settingsPanes[i];
		}
	}

	return NULL;
}

- (NSDictionary<NSString *, NSString *> *)settingsCatalogItemWithID:(NSString *)identifier
															  title:(NSString *)title
															 symbol:(NSString *)symbol
															  group:(NSString *)group
{
	return @{@"id" : identifier, @"title" : title, @"symbol" : symbol, @"group" : group};
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)settingsSidebarCatalog
{
	NSMutableArray<NSDictionary<NSString *, NSString *> *> *items =
		[NSMutableArray arrayWithCapacity:_settingsPaneCount];

	for (NSUInteger i = 0; i < _settingsPaneCount; i++) {
		const TDCPreferencesSettingsPane *pane = &_settingsPanes[i];

		[items addObject:[self settingsCatalogItemWithID:pane->identifier
												   title:TXTLS(([NSString
															 stringWithFormat:@"TDCPreferencesController[sb-%@]",
																			  pane->identifier]))
												  symbol:pane->symbolName
												   group:pane->group]];

		/* Plug-in panes are listed directly beneath the add-ons pane they belong to. */
		if ([pane->group isEqualToString:_settingsGroupAddons] == NO) {
			continue;
		}

		[sharedPluginManager().pluginsWithPreferencePanes
			enumerateObjectsUsingBlock:^(THOPluginItem *plugin, NSUInteger index, BOOL *stop) {
				NSString *title = plugin.pluginPreferencesPaneMenuItemTitle;

				if (title.length == 0) {
					title = TXTLS(@"TDCPreferencesController[sb-plugin]");
				}

				[items addObject:[self settingsCatalogItemWithID:TDCPreferencesSettingsPluginIdentifier(index)
														   title:title
														  symbol:@"puzzlepiece.extension"
														   group:_settingsGroupAddons]];
			}];
	}

	return [items copy];
}

- (nullable NSView *)viewForSettingsPaneIdentifier:(NSString *)identifier
{
	NSParameterAssert(identifier != nil);

	if ([identifier hasPrefix:@"plugin-"]) {
		NSInteger pluginIndex = [[identifier substringFromIndex:7] integerValue];

		NSArray *plugins = sharedPluginManager().pluginsWithPreferencePanes;

		if (pluginIndex < 0 || pluginIndex >= (NSInteger)plugins.count) {
			return nil;
		}

		return [plugins[(NSUInteger)pluginIndex] pluginPreferencesPaneView];
	}

	const TDCPreferencesSettingsPane *pane = TDCPreferencesSettingsPaneForIdentifier(identifier);

	if (pane == NULL) {
		return nil;
	}

	return [self valueForKey:pane->contentViewKey];
}

- (nullable TDCPreferencesSidebarItem *)sidebarItemForIdentifier:(NSString *)identifier
{
	for (TDCPreferencesSidebarItem *item in self.sidebarPaneItems) {
		if ([item.identifier isEqualToString:identifier]) {
			return item;
		}
	}

	return nil;
}

#pragma mark -
#pragma mark Settings Shell

/* The window is a split view: a source list of panes on the left and
 the selected pane, wrapped in a scroll view, on the right. The toolbar
 carries only back/forward so that the title bar picks up the unified
 toolbar treatment, the same as System Settings. */
- (void)installSettingsShell
{
	NSWindow *window = self.window;

	window.styleMask = (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
						NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView);
	window.toolbarStyle = NSWindowToolbarStyleUnified;
	window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleAutomatic;
	window.titlebarAppearsTransparent = NO;
	window.minSize = NSMakeSize(_windowMinimumWidth, _windowMinimumHeight);
	window.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);

	[self buildSidebarItems];

	self.paneHistory = [NSMutableArray array];
	self.paneHistoryIndex = 0;

	NSSplitViewController *splitViewController = [NSSplitViewController new];
	splitViewController.splitView.dividerStyle = NSSplitViewDividerStyleThin;

	/* Build the detail pane first: the sidebar's outline view posts a
	 selection change while it is being populated, and presenting a pane
	 needs the container view to exist. */
	NSViewController *detailViewController = [self makeDetailViewController];

	NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:[self makeSidebarViewController]];
	sidebarItem.canCollapse = NO;
	sidebarItem.minimumThickness = _sidebarMinimumWidth;
	sidebarItem.maximumThickness = _sidebarMaximumWidth;
	sidebarItem.preferredThicknessFraction = (_sidebarPreferredWidth / _windowMinimumWidth);
	[splitViewController addSplitViewItem:sidebarItem];

	NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:detailViewController];
	detailItem.minimumThickness = (_windowMinimumWidth - _sidebarMaximumWidth);
	[splitViewController addSplitViewItem:detailItem];

	self.splitViewController = splitViewController;

	window.contentViewController = splitViewController;

	NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"TDCPreferencesControllerToolbar"];
	toolbar.delegate = self;
	toolbar.allowsUserCustomization = NO;
	toolbar.autosavesConfiguration = NO;
	toolbar.displayMode = NSToolbarDisplayModeIconOnly;

	window.toolbar = toolbar;
}

- (void)buildSidebarItems
{
	NSMutableArray<TDCPreferencesSidebarItem *> *rootItems = [NSMutableArray array];
	NSMutableArray<TDCPreferencesSidebarItem *> *paneItems = [NSMutableArray array];
	NSMutableArray<TDCPreferencesSidebarItem *> *addonItems = [NSMutableArray array];
	NSMutableArray<TDCPreferencesSidebarItem *> *advancedItems = [NSMutableArray array];

	for (NSDictionary<NSString *, NSString *> *entry in self.settingsSidebarCatalog) {
		TDCPreferencesSidebarItem *item = [TDCPreferencesSidebarItem new];
		item.identifier = entry[@"id"];
		item.title = entry[@"title"];
		item.symbolName = entry[@"symbol"];

		[paneItems addObject:item];

		NSString *group = entry[@"group"];

		if ([group isEqualToString:_settingsGroupAddons]) {
			[addonItems addObject:item];
		} else if ([group isEqualToString:_settingsGroupAdvanced]) {
			[advancedItems addObject:item];
		} else {
			[rootItems addObject:item];
		}
	}

	if (addonItems.count > 0) {
		TDCPreferencesSidebarItem *group = [TDCPreferencesSidebarItem new];
		group.title = TXTLS(@"TDCPreferencesController[sb-gr-ad]");
		group.children = addonItems;

		[rootItems addObject:group];
	}

	if (advancedItems.count > 0) {
		TDCPreferencesSidebarItem *group = [TDCPreferencesSidebarItem new];
		group.title = TXTLS(@"TDCPreferencesController[sb-gr-av]");
		group.children = advancedItems;

		[rootItems addObject:group];
	}

	self.sidebarItems = rootItems;
	self.sidebarPaneItems = paneItems;
}

- (NSViewController *)makeSidebarViewController
{
	NSOutlineView *outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
	outlineView.style = NSTableViewStyleSourceList;
	outlineView.headerView = nil;
	outlineView.floatsGroupRows = NO;
	outlineView.indentationPerLevel = 0.0;
	outlineView.rowSizeStyle = NSTableViewRowSizeStyleDefault;
	outlineView.allowsEmptySelection = NO;
	outlineView.allowsMultipleSelection = NO;
	outlineView.autoresizesOutlineColumn = NO;
	outlineView.focusRingType = NSFocusRingTypeNone;
	outlineView.accessibilityLabel = TXTLS(@"TDCPreferencesController[sb-tt]");

	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"pane"];
	column.resizingMask = NSTableColumnAutoresizingMask;
	[outlineView addTableColumn:column];
	outlineView.outlineTableColumn = column;

	outlineView.dataSource = self;
	outlineView.delegate = self;

	self.sidebarOutlineView = outlineView;

	NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	scrollView.documentView = outlineView;
	scrollView.hasVerticalScroller = YES;
	scrollView.hasHorizontalScroller = NO;
	scrollView.autohidesScrollers = YES;
	scrollView.drawsBackground = NO;
	scrollView.automaticallyAdjustsContentInsets = YES;

	NSTextField *versionLabel = [NSTextField labelWithString:[self versionFooterString]];
	versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
	versionLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	versionLabel.textColor = [NSColor tertiaryLabelColor];
	versionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[versionLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
										   forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSVisualEffectView *sidebarView =
		[[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0.0, 0.0, _sidebarPreferredWidth, _windowMinimumHeight)];
	sidebarView.material = NSVisualEffectMaterialSidebar;
	sidebarView.blendingMode = NSVisualEffectBlendingModeBehindWindow;

	[sidebarView addSubview:scrollView];
	[sidebarView addSubview:versionLabel];

	[NSLayoutConstraint activateConstraints:@[
		[scrollView.topAnchor constraintEqualToAnchor:sidebarView.topAnchor],
		[scrollView.leadingAnchor constraintEqualToAnchor:sidebarView.leadingAnchor],
		[scrollView.trailingAnchor constraintEqualToAnchor:sidebarView.trailingAnchor],
		[versionLabel.topAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:8.0],
		[versionLabel.leadingAnchor constraintEqualToAnchor:sidebarView.leadingAnchor constant:18.0],
		[versionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:sidebarView.trailingAnchor constant:-18.0],
		[versionLabel.bottomAnchor constraintEqualToAnchor:sidebarView.bottomAnchor constant:-10.0],
	]];

	NSViewController *viewController = [NSViewController new];
	viewController.view = sidebarView;

	[outlineView reloadData];
	[outlineView expandItem:nil expandChildren:YES];

	return viewController;
}

- (NSString *)versionFooterString
{
	NSDictionary *info = RZMainBundle().infoDictionary;

	NSString *version = info[@"CFBundleShortVersionString"];
	NSString *build = info[@"CFBundleVersion"];

	return TXTLS(@"TDCPreferencesController[sb-vers]", (version ?: @""), (build ?: @""));
}

- (NSViewController *)makeDetailViewController
{
	TDCPreferencesPaneContainerView *containerView = [[TDCPreferencesPaneContainerView alloc] initWithFrame:NSZeroRect];
	containerView.translatesAutoresizingMaskIntoConstraints = NO;

	self.paneContainerView = containerView;

	NSScrollView *scrollView = [[NSScrollView alloc]
		initWithFrame:NSMakeRect(0.0, 0.0, (_windowMinimumWidth - _sidebarPreferredWidth), _windowMinimumHeight)];
	scrollView.documentView = containerView;
	scrollView.hasVerticalScroller = YES;
	scrollView.hasHorizontalScroller = NO;
	scrollView.autohidesScrollers = YES;
	scrollView.drawsBackground = NO;
	scrollView.automaticallyAdjustsContentInsets = YES;

	self.paneScrollView = scrollView;

	NSClipView *clipView = scrollView.contentView;

	/* The document view always fills the visible area and grows when a
	 pane needs more room, so narrow windows scroll rather than clip. */
	NSLayoutConstraint *widthConstraint = [containerView.widthAnchor constraintEqualToAnchor:clipView.widthAnchor];
	widthConstraint.priority = NSLayoutPriorityDefaultHigh;

	NSLayoutConstraint *heightConstraint = [containerView.heightAnchor constraintEqualToAnchor:clipView.heightAnchor];
	heightConstraint.priority = NSLayoutPriorityDefaultHigh;

	[NSLayoutConstraint activateConstraints:@[
		[containerView.leadingAnchor constraintEqualToAnchor:clipView.leadingAnchor],
		[containerView.topAnchor constraintEqualToAnchor:clipView.topAnchor],
		[containerView.widthAnchor constraintGreaterThanOrEqualToAnchor:clipView.widthAnchor],
		[containerView.heightAnchor constraintGreaterThanOrEqualToAnchor:clipView.heightAnchor],
		widthConstraint,
		heightConstraint,
	]];

	NSViewController *viewController = [NSViewController new];
	viewController.view = scrollView;

	return viewController;
}

- (void)presentPaneView:(NSView *)paneView
{
	if (self.presentedPaneView == paneView) {
		return;
	}

	[self.presentedPaneView removeFromSuperview];

	self.presentedPaneView = paneView;

	TDCPreferencesPaneContainerView *containerView = self.paneContainerView;

	if (containerView == nil) {
		self.presentedPaneView = nil;

		return;
	}

	paneView.translatesAutoresizingMaskIntoConstraints = NO;

	[containerView addSubview:paneView];

	/* Panes are laid out at a fixed width in the nib. Centre them in the
	 available space, like System Settings does, and let the container grow
	 vertically so tall panes scroll. */
	[NSLayoutConstraint activateConstraints:@[
		[paneView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:_paneContentInset],
		[paneView.centerXAnchor constraintEqualToAnchor:containerView.centerXAnchor],
		[paneView.leadingAnchor constraintGreaterThanOrEqualToAnchor:containerView.leadingAnchor
															constant:_paneContentInset],
		[containerView.bottomAnchor constraintGreaterThanOrEqualToAnchor:paneView.bottomAnchor
																constant:_paneContentInset],
	]];

	[containerView layoutSubtreeIfNeeded];

	[self scrollPresentedPaneToTop];
}

- (void)scrollPresentedPaneToTop
{
	NSScrollView *scrollView = self.paneScrollView;
	NSClipView *clipView = scrollView.contentView;

	/* The content sits under the title bar (full size content view), so
	 the top of the document is at -inset, not at zero. */
	NSPoint topPoint = NSMakePoint(0.0, -clipView.contentInsets.top);

	[clipView scrollToPoint:[clipView constrainBoundsRect:(NSRect){topPoint, clipView.bounds.size}].origin];
	[scrollView reflectScrolledClipView:clipView];
}

#pragma mark -
#pragma mark Pane Selection

- (void)selectPaneWithIdentifier:(NSString *)identifier
{
	NSParameterAssert(identifier != nil);

	TDCPreferencesSidebarItem *item = [self sidebarItemForIdentifier:identifier];

	NSView *paneView = [self viewForSettingsPaneIdentifier:identifier];

	if (item == nil || paneView == nil) {
		return;
	}

	if ([self.selectedPaneIdentifier isEqualToString:identifier]) {
		[self syncSidebarSelectionToItem:item];

		return;
	}

	self.selectedPaneIdentifier = identifier;

	[self presentPaneView:paneView];

	self.window.title = item.title;

	[self syncSidebarSelectionToItem:item];

	[self recordPaneInHistory:identifier];

	[RZUserDefaults() setObject:identifier forKey:_selectedPaneDefaultsKey];
}

- (void)syncSidebarSelectionToItem:(TDCPreferencesSidebarItem *)item
{
	NSOutlineView *outlineView = self.sidebarOutlineView;

	NSInteger row = [outlineView rowForItem:item];

	if (row < 0 || outlineView.selectedRow == row) {
		return;
	}

	self.updatingSidebarSelection = YES;

	[outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	[outlineView scrollRowToVisible:row];

	self.updatingSidebarSelection = NO;
}

#pragma mark -
#pragma mark Pane History

- (void)recordPaneInHistory:(NSString *)identifier
{
	if (self.navigatingPaneHistory) {
		return;
	}

	NSMutableArray<NSString *> *history = self.paneHistory;

	/* Selecting a new pane discards anything that was ahead of us. */
	if (history.count > 0 && (self.paneHistoryIndex + 1) < history.count) {
		[history
			removeObjectsInRange:NSMakeRange((self.paneHistoryIndex + 1), (history.count - self.paneHistoryIndex - 1))];
	}

	[history addObject:identifier];

	self.paneHistoryIndex = (history.count - 1);

	[self.window.toolbar validateVisibleItems];
}

- (BOOL)canNavigateBack
{
	return (self.paneHistoryIndex > 0);
}

- (BOOL)canNavigateForward
{
	return ((self.paneHistoryIndex + 1) < self.paneHistory.count);
}

- (void)navigateToHistoryIndex:(NSUInteger)index
{
	if (index >= self.paneHistory.count) {
		return;
	}

	self.paneHistoryIndex = index;

	self.navigatingPaneHistory = YES;

	[self selectPaneWithIdentifier:self.paneHistory[index]];

	self.navigatingPaneHistory = NO;

	[self.window.toolbar validateVisibleItems];
}

- (void)navigateBack:(nullable id)sender
{
	if ([self canNavigateBack]) {
		[self navigateToHistoryIndex:(self.paneHistoryIndex - 1)];
	}
}

- (void)navigateForward:(nullable id)sender
{
	if ([self canNavigateForward]) {
		[self navigateToHistoryIndex:(self.paneHistoryIndex + 1)];
	}
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
	if ([item.itemIdentifier isEqualToString:_toolbarItemBack]) {
		return [self canNavigateBack];
	}

	if ([item.itemIdentifier isEqualToString:_toolbarItemForward]) {
		return [self canNavigateForward];
	}

	return YES;
}

#pragma mark -
#pragma mark NSToolbar Delegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return @[
		NSToolbarSidebarTrackingSeparatorItemIdentifier,
		_toolbarItemBack,
		_toolbarItemForward,
		NSToolbarFlexibleSpaceItemIdentifier
	];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return @[ NSToolbarSidebarTrackingSeparatorItemIdentifier, _toolbarItemBack, _toolbarItemForward ];
}

- (nullable NSToolbarItem *)toolbar:(NSToolbar *)toolbar
			  itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
		  willBeInsertedIntoToolbar:(BOOL)flag
{
	NSString *symbolName = nil;
	NSString *label = nil;
	SEL action = NULL;

	if ([itemIdentifier isEqualToString:_toolbarItemBack]) {
		symbolName = @"chevron.left";
		label = TXTLS(@"TDCPreferencesController[tb-back]");
		action = @selector(navigateBack:);
	} else if ([itemIdentifier isEqualToString:_toolbarItemForward]) {
		symbolName = @"chevron.right";
		label = TXTLS(@"TDCPreferencesController[tb-forward]");
		action = @selector(navigateForward:);
	} else {
		return nil;
	}

	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
	item.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:label];
	item.label = label;
	item.paletteLabel = label;
	item.toolTip = label;
	item.bordered = YES;
	item.navigational = YES;
	item.target = self;
	item.action = action;

	return item;
}

#pragma mark -
#pragma mark NSOutlineView Data Source & Delegate

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item
{
	if (item == nil) {
		return (NSInteger)self.sidebarItems.count;
	}

	return (NSInteger)((TDCPreferencesSidebarItem *)item).children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item
{
	if (item == nil) {
		return self.sidebarItems[(NSUInteger)index];
	}

	return ((TDCPreferencesSidebarItem *)item).children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return ((TDCPreferencesSidebarItem *)item).isGroup;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
	return ((TDCPreferencesSidebarItem *)item).isGroup;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	return (((TDCPreferencesSidebarItem *)item).isGroup == NO);
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item
{
	return NO;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item
{
	return NO;
}

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView
			  viewForTableColumn:(nullable NSTableColumn *)tableColumn
							item:(id)item
{
	TDCPreferencesSidebarItem *sidebarItem = item;

	NSUserInterfaceItemIdentifier cellIdentifier =
		(sidebarItem.isGroup ? _sidebarGroupCellIdentifier : _sidebarPaneCellIdentifier);

	NSTableCellView *cellView = [outlineView makeViewWithIdentifier:cellIdentifier owner:self];

	if (cellView == nil) {
		cellView = [self makeSidebarCellViewWithIdentifier:cellIdentifier imageView:(sidebarItem.isGroup == NO)];
	}

	cellView.textField.stringValue = sidebarItem.title;

	if (sidebarItem.isGroup == NO) {
		cellView.imageView.image = [NSImage imageWithSystemSymbolName:sidebarItem.symbolName
											 accessibilityDescription:sidebarItem.title];
	}

	cellView.accessibilityLabel = sidebarItem.title;

	return cellView;
}

- (NSTableCellView *)makeSidebarCellViewWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
											 imageView:(BOOL)hasImageView
{
	NSTableCellView *cellView = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
	cellView.identifier = identifier;

	NSTextField *textField = [NSTextField labelWithString:@""];
	textField.translatesAutoresizingMaskIntoConstraints = NO;
	textField.lineBreakMode = NSLineBreakByTruncatingTail;
	[cellView addSubview:textField];
	cellView.textField = textField;

	[NSLayoutConstraint activateConstraints:@[
		[textField.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor],
		[textField.trailingAnchor constraintLessThanOrEqualToAnchor:cellView.trailingAnchor constant:-4.0],
	]];

	if (hasImageView == NO) {
		[textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor].active = YES;

		return cellView;
	}

	NSImageView *imageView = [NSImageView imageViewWithImage:[NSImage new]];
	imageView.translatesAutoresizingMaskIntoConstraints = NO;
	imageView.imageScaling = NSImageScaleProportionallyDown;
	imageView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:15.0
																					weight:NSFontWeightRegular];
	[cellView addSubview:imageView];
	cellView.imageView = imageView;

	[NSLayoutConstraint activateConstraints:@[
		[imageView.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:2.0],
		[imageView.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor],
		[imageView.widthAnchor constraintEqualToConstant:22.0],
		[imageView.heightAnchor constraintEqualToConstant:22.0],
		[textField.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:6.0],
	]];

	return cellView;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	if (self.updatingSidebarSelection) {
		return;
	}

	NSOutlineView *outlineView = self.sidebarOutlineView;

	TDCPreferencesSidebarItem *item = [outlineView itemAtRow:outlineView.selectedRow];

	if (item == nil || item.isGroup || item.identifier == nil) {
		return;
	}

	[self selectPaneWithIdentifier:item.identifier];
}

#pragma mark -
#pragma mark Accessibility

- (void)installAccessibilityLabels
{
	self.themeSelectionButton.toolTip = TXTLS(@"TDCPreferencesController[ax-theme]");
	self.themeSelectionButton.accessibilityLabel = TXTLS(@"TDCPreferencesController[ax-theme]");

	self.transcriptFolderButton.toolTip = TXTLS(@"TDCPreferencesController[ax-transcript-folder]");
	self.transcriptFolderButton.accessibilityLabel = TXTLS(@"TDCPreferencesController[ax-transcript-folder]");

	self.fileTransferDownloadDestinationButton.toolTip = TXTLS(@"TDCPreferencesController[ax-download-folder]");
	self.fileTransferDownloadDestinationButton.accessibilityLabel =
		TXTLS(@"TDCPreferencesController[ax-download-folder]");
}

#pragma mark -
#pragma mark Window Frame

- (void)restoreWindowFrame
{
	NSWindow *window = self.window;

	[window saveSizeAsDefault];

	[window restoreWindowStateForClass:self.class];

	NSSize frameSize = window.frame.size;

	if (frameSize.width < _windowMinimumWidth || frameSize.height < _windowMinimumHeight) {
		[window setContentSize:NSMakeSize(1020.0, 700.0)];
		[window center];
	}
}

- (void)saveWindowFrame
{
	NSWindow *window = self.window;

	[window restoreDefaultSizeAndDisplay:NO];

	[window saveWindowStateForClass:self.class];
}

#pragma mark -
#pragma mark KVC Properties

- (NSArray<NSDictionary *> *)installedScripts
{
	NSMutableArray *scriptsInstalled = [NSMutableArray array];

	[scriptsInstalled addObjectsFromArray:sharedPluginManager().supportedAppleScriptCommands];
	[scriptsInstalled addObjectsFromArray:sharedPluginManager().supportedUserInputCommands];

	return scriptsInstalled.stringArrayControllerObjects;
}

- (NSString *)scrollbackSaveLimit
{
	return _unsignedIntegerString([TPCPreferences scrollbackSaveLimit]);
}

- (void)setScrollbackSaveLimit:(NSString *)value
{
	[TPCPreferences setScrollbackSaveLimit:value.integerValue];
}

- (NSString *)scrollbackVisibleLimit
{
	return _unsignedIntegerString([TPCPreferences scrollbackVisibleLimit]);
}

- (void)setScrollbackVisibleLimit:(NSString *)value
{
	[TPCPreferences setScrollbackVisibleLimit:value.integerValue];
}

- (NSString *)completionSuffix
{
	return [TPCPreferences tabCompletionSuffix];
}

- (void)setCompletionSuffix:(NSString *)value
{
	[TPCPreferences setTabCompletionSuffix:value];
}

- (NSString *)inlineMediaMaxWidth
{
	return _unsignedIntegerString([TPCPreferences inlineMediaMaxWidth]);
}

- (NSString *)inlineMediaMaxHeight
{
	return _unsignedIntegerString([TPCPreferences inlineMediaMaxHeight]);
}

- (void)setInlineMediaMaxWidth:(NSString *)value
{
	[TPCPreferences setInlineMediaMaxWidth:value.integerValue];
}

- (void)setInlineMediaMaxHeight:(NSString *)value
{
	[TPCPreferences setInlineMediaMaxHeight:value.integerValue];
}

- (NSString *)themeChannelViewFontName
{
	NSFont *currentFont = [TPCPreferences themeChannelViewFont];

	return currentFont.displayName;
}

- (CGFloat)themeChannelViewFontSize
{
	return [TPCPreferences themeChannelViewFontSize];
}

- (void)setThemeChannelViewFontName:(NSString *)value
{
	return;
}

- (void)setThemeChannelViewFontSize:(CGFloat)value
{
	return;
}

- (NSString *)fileTransferPortRangeStart
{
	return _unsignedIntegerString([TPCPreferences fileTransferPortRangeStart]);
}

- (NSString *)fileTransferPortRangeEnd
{
	return _unsignedIntegerString([TPCPreferences fileTransferPortRangeEnd]);
}

- (void)setFileTransferPortRangeStart:(NSString *)value
{
	[TPCPreferences setFileTransferPortRangeStart:value.integerValue];
}

- (void)setFileTransferPortRangeEnd:(NSString *)value
{
	[TPCPreferences setFileTransferPortRangeEnd:value.integerValue];
}

#if GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION == 1
- (void)setTextEncryptionIsOpportunistic:(BOOL)textEncryptionIsOpportunistic
{
	[TPCPreferences setTextEncryptionIsOpportunistic:textEncryptionIsOpportunistic];
}

- (BOOL)textEncryptionIsOpportunistic
{
	if ([TPCPreferences textEncryptionIsEnabled] == NO) {
		return NO;
	}

	if ([TPCPreferences textEncryptionIsRequired]) {
		return YES;
	}

	return [TPCPreferences textEncryptionIsOpportunistic];
}

- (BOOL)textEncryptionIsOpportunisticPreferenceEnabled
{
	return ([TPCPreferences textEncryptionIsEnabled] && [TPCPreferences textEncryptionIsRequired] == NO);
}

- (void)setTextEncryptionIsRequired:(BOOL)textEncryptionIsRequired
{
	[TPCPreferences setTextEncryptionIsRequired:textEncryptionIsRequired];

	[self willChangeValueForKey:@"textEncryptionIsOpportunistic"];
	[self didChangeValueForKey:@"textEncryptionIsOpportunistic"];
}

- (BOOL)textEncryptionIsRequired
{
	if ([TPCPreferences textEncryptionIsEnabled] == NO) {
		return NO;
	}

	return [TPCPreferences textEncryptionIsRequired];
}

- (BOOL)textEncryptionIsRequiredPreferenceEnabled
{
	return [TPCPreferences textEncryptionIsEnabled];
}

- (void)setTextEncryptionIsEnabled:(BOOL)textEncryptionIsEnabled
{
	[TPCPreferences setTextEncryptionIsEnabled:textEncryptionIsEnabled];

	[self willChangeValueForKey:@"textEncryptionIsOpportunistic"];
	[self willChangeValueForKey:@"textEncryptionIsOpportunisticPreferenceEnabled"];
	[self willChangeValueForKey:@"textEncryptionIsRequired"];
	[self willChangeValueForKey:@"textEncryptionIsRequiredPreferenceEnabled"];

	[self didChangeValueForKey:@"textEncryptionIsOpportunistic"];
	[self didChangeValueForKey:@"textEncryptionIsOpportunisticPreferenceEnabled"];
	[self didChangeValueForKey:@"textEncryptionIsRequired"];
	[self didChangeValueForKey:@"textEncryptionIsRequiredPreferenceEnabled"];
}

- (BOOL)textEncryptionIsEnabled
{
	return [TPCPreferences textEncryptionIsEnabled];
}
#else
- (void)setTextEncryptionIsOpportunistic:(BOOL)textEncryptionIsOpportunistic
{
}

- (BOOL)textEncryptionIsOpportunistic
{
}

- (BOOL)textEncryptionIsOpportunisticPreferenceEnabled
{
}

- (void)setTextEncryptionIsRequired:(BOOL)textEncryptionIsRequired
{
}

- (BOOL)textEncryptionIsRequired
{
}

- (BOOL)textEncryptionIsRequiredPreferenceEnabled
{
}

- (void)setTextEncryptionIsEnabled:(BOOL)textEncryptionIsEnabled
{
}

- (BOOL)textEncryptionIsEnabled
{
}
#endif

- (BOOL)highlightCurrentNickname
{
	if ([TPCPreferences highlightMatchingMethod] == TXNicknameHighlightMatchTypeRegularExpression) {
		return NO;
	}

	return [TPCPreferences highlightCurrentNickname];
}

- (void)setHighlightCurrentNickname:(BOOL)value
{
	[TPCPreferences setHighlightCurrentNickname:value];
}

- (BOOL)appNapEnabled
{
	return [TPCPreferences appNapEnabled];
}

- (void)setAppNapEnabled:(BOOL)appNapEnabled
{
	[TPCPreferences setAppNapEnabled:appNapEnabled];
}

- (BOOL)onlySpeakEventsForSelection
{
	return [TPCPreferences onlySpeakEventsForSelection];
}

- (void)setOnlySpeakEventsForSelection:(BOOL)onlySpeakEventsForSelection
{
	[TPCPreferences setOnlySpeakEventsForSelection:onlySpeakEventsForSelection];

	[self willChangeValueForKey:@"channelMessageSpeakChannelName"];
	[self didChangeValueForKey:@"channelMessageSpeakChannelName"];
}

- (BOOL)channelMessageSpeakChannelName
{
	if ([TPCPreferences onlySpeakEventsForSelection]) {
		return NO;
	}

	return [TPCPreferences channelMessageSpeakChannelName];
}

- (void)setChannelMessageSpeakChannelName:(BOOL)channelMessageSpeakChannelName
{
	[TPCPreferences setChannelMessageSpeakChannelName:channelMessageSpeakChannelName];
}

- (BOOL)channelMessageSpeakNickname
{
	return [TPCPreferences channelMessageSpeakNickname];
}

- (void)setChannelMessageSpeakNickname:(BOOL)channelMessageSpeakNickname
{
	[TPCPreferences setChannelMessageSpeakNickname:channelMessageSpeakNickname];
}

- (NSColor *)serverListUnreadCountBadgeHighlightColor
{
	NSColor *value = [RZUserDefaults() colorForKey:@"Server List Unread Message Count Badge Colors -> Highlight"];

	if (value == nil) {
		value = [NSColor clearColor];
	}

	return value;
}

- (void)setServerListUnreadCountBadgeHighlightColor:(NSColor *)serverListUnreadCountBadgeHighlightColor
{
	NSColor *newValue = serverListUnreadCountBadgeHighlightColor;

	if ([newValue isEqual:[NSColor clearColor]]) {
		newValue = nil;
	}

	[RZUserDefaults() setColor:newValue forKey:@"Server List Unread Message Count Badge Colors -> Highlight"];
}

- (NSColor *)userListNoModeColor
{
	NSColor *value = [RZUserDefaults() colorForKey:@"User List Mode Badge Colors -> no mode"];

	if (value == nil) {
		value = [NSColor clearColor];
	}

	return value;
}

- (void)setUserListNoModeColor:(NSColor *)userListNoModeColor
{
	NSColor *newValue = userListNoModeColor;

	if ([newValue isEqual:[NSColor clearColor]]) {
		newValue = nil;
	}

	[RZUserDefaults() setColor:newValue forKey:@"User List Mode Badge Colors -> no mode"];
}

- (BOOL)logTranscript
{
	return [TPCPreferences logToDisk];
}

- (void)setLogTranscript:(BOOL)logTranscript
{
	[TPCPreferences setLogToDisk:logTranscript];
}

- (BOOL)inlineMediaLimitToBasics
{
	return [TPCPreferences inlineMediaLimitToBasics];
}

- (void)setInlineMediaLimitToBasics:(BOOL)inlineMediaLimitToBasics
{
	[TPCPreferences setInlineMediaLimitToBasics:inlineMediaLimitToBasics];

	[self willChangeValueForKey:@"inlineMediaLimitBasicsToFiles"];
	[self didChangeValueForKey:@"inlineMediaLimitBasicsToFiles"];
}

- (BOOL)inlineMediaLimitBasicsToFiles
{
	/* Show value as enabled when basics is disabled */
	if ([TPCPreferences inlineMediaLimitToBasics] == NO) {
		return NO; // UI negates bool so return NO for YES
	}

	return [TPCPreferences inlineMediaLimitBasicsToFiles];
}

- (void)setInlineMediaLimitBasicsToFiles:(BOOL)inlineMediaLimitBasicsToFiles
{
	[TPCPreferences setInlineMediaLimitBasicsToFiles:inlineMediaLimitBasicsToFiles];
}

- (BOOL)validateValue:(inout id *)value forKey:(NSString *)key error:(out NSError **)outError
{
	if ([key isEqualToString:@"scrollbackSaveLimit"]) {
		NSInteger valueInteger = [*value integerValue];

		if (valueInteger < _scrollbackSaveLinesMin) {
			*value = _unsignedIntegerString(_scrollbackSaveLinesMin);
		} else if (valueInteger > _scrollbackSaveLinesMax) {
			*value = _unsignedIntegerString(_scrollbackSaveLinesMax);
		}
	} else if ([key isEqualToString:@"scrollbackVisibleLimit"]) {
		NSInteger valueInteger = [*value integerValue];

		if (valueInteger < _scrollbackVisibleLinesMin && valueInteger != 0) {
			*value = _unsignedIntegerString(_scrollbackVisibleLinesMin);
		} else if (valueInteger > _scrollbackVisibleLinesMax) {
			*value = _unsignedIntegerString(_scrollbackVisibleLinesMax);
		}
	} else if ([key isEqualToString:@"inlineMediaMaxWidth"]) {
		NSInteger valueInteger = [*value integerValue];

		if (valueInteger < _inlineMediaWidthMin) {
			*value = _unsignedIntegerString(_inlineMediaWidthMin);
		} else if (_inlineMediaWidthMax < valueInteger) {
			*value = _unsignedIntegerString(_inlineMediaWidthMax);
		}
	} else if ([key isEqualToString:@"inlineMediaMaxHeight"]) {
		NSInteger valueInteger = [*value integerValue];

		if (valueInteger < _inlineMediaHeightMin) {
			*value = _unsignedIntegerString(_inlineMediaHeightMin);
		} else if (_inlineMediaHeightMax < valueInteger) {
			*value = _unsignedIntegerString(_inlineMediaHeightMax);
		}
	} else if ([key isEqualToString:@"fileTransferPortRangeStart"]) {
		NSInteger valueInteger = [*value integerValue];

		NSUInteger valueRangeEnd = [TPCPreferences fileTransferPortRangeEnd];

		if (valueInteger < _fileTransferPortRangeMin) {
			*value = _unsignedIntegerString(_fileTransferPortRangeMin);
		} else if (_fileTransferPortRangeMax < valueInteger) {
			*value = _unsignedIntegerString(_fileTransferPortRangeMax);
		}

		valueInteger = [*value integerValue];

		if (valueInteger > (NSInteger)valueRangeEnd) {
			*value = _unsignedIntegerString(valueRangeEnd);
		}
	} else if ([key isEqualToString:@"fileTransferPortRangeEnd"]) {
		NSInteger valueInteger = [*value integerValue];

		NSUInteger valueRangeStart = [TPCPreferences fileTransferPortRangeStart];

		if (valueInteger < _fileTransferPortRangeMin) {
			*value = _unsignedIntegerString(_fileTransferPortRangeMin);
		} else if (_fileTransferPortRangeMax < valueInteger) {
			*value = _unsignedIntegerString(_fileTransferPortRangeMax);
		}

		valueInteger = [*value integerValue];

		if (valueInteger < (NSInteger)valueRangeStart) {
			*value = _unsignedIntegerString(valueRangeStart);
		}
	}

	return YES;
}

#pragma mark -
#pragma mark File Transfer Destination Folder Popup

- (void)updateFileTransferDownloadDestinationFolder
{
	TDCFileTransferDialog *transferController = [TXSharedApplication sharedFileTransferDialog];

	NSURL *path = transferController.downloadDestinationURL;

	NSMenuItem *item = [self.fileTransferDownloadDestinationButton itemAtIndex:0];

	if (path == nil) {
		item.image = nil;

		item.title = TXTLS(@"TDCPreferencesController[721-ie]");
	} else {
		NSImage *icon = [RZWorkspace() iconForFile:path.path];

		item.image = icon;

		icon.size = NSMakeSize(16, 16);

		item.title = path.lastPathComponent;
	}
}

- (void)onFileTransferDownloadDestinationFolderChanged:(nullable id)sender
{
	TDCFileTransferDialog *transferController = [TXSharedApplication sharedFileTransferDialog];

	if (self.fileTransferDownloadDestinationButton.selectedTag == 2) {
		[self chooseFolderWithButton:self.fileTransferDownloadDestinationButton
					 completionBlock:^(NSData *bookmark) {
						 [transferController setDownloadDestinationURL:bookmark];

						 [self updateFileTransferDownloadDestinationFolder];
					 }];
	} else if (self.fileTransferDownloadDestinationButton.selectedTag == 3) {
		[self.fileTransferDownloadDestinationButton selectItemAtIndex:0];

		[transferController setDownloadDestinationURL:nil];

		[self updateFileTransferDownloadDestinationFolder];
	}
}

#pragma mark -
#pragma mark Folder Selection

/* Presents a folder chooser as a sheet. The popup button is reset to
 its first item once the panel closes. The completion block is only
 invoked when the user picked a folder and a security scoped bookmark
 could be created for it. */
- (void)chooseFolderWithButton:(NSPopUpButton *)popupButton completionBlock:(void (^)(NSData *bookmark))completionBlock
{
	NSParameterAssert(popupButton != nil);
	NSParameterAssert(completionBlock != nil);

	NSOpenPanel *d = [NSOpenPanel openPanel];

	d.allowsMultipleSelection = NO;
	d.canChooseDirectories = YES;
	d.canChooseFiles = NO;
	d.canCreateDirectories = YES;
	d.resolvesAliases = YES;

	d.prompt = TXTLS(@"Prompts[xne-79]");

	[d beginSheetModalForWindow:self.window
			  completionHandler:^(NSInteger returnCode) {
				  [popupButton selectItemAtIndex:0];

				  if (returnCode != NSModalResponseOK) {
					  return;
				  }

				  NSURL *path = d.URLs[0];

				  NSError *bookmarkError = nil;

				  NSData *bookmark = [path bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
									includingResourceValuesForKeys:nil
													 relativeToURL:nil
															 error:&bookmarkError];

				  if (bookmark == nil) {
					  LogToConsoleError("Error creating bookmark for URL ('%{public}@'): %{public}@",
										path.standardizedTildePath,
										bookmarkError.localizedDescription);

					  return;
				  }

				  completionBlock(bookmark);
			  }];
}

#pragma mark -
#pragma mark Transcript Folder Popup

- (void)updateTranscriptFolder
{
	NSURL *path = [TPCPathInfo transcriptFolderURL];

	NSMenuItem *item = [self.transcriptFolderButton itemAtIndex:0];

	if (path == nil) {
		item.image = nil;

		item.title = TXTLS(@"TDCPreferencesController[70s-c6]");
	} else {
		NSImage *icon = [RZWorkspace() iconForFile:path.path];

		item.image = icon;

		icon.size = NSMakeSize(16, 16);

		item.title = path.lastPathComponent;
	}
}

- (void)onChangedTranscriptFolder:(nullable id)sender
{
	if (self.transcriptFolderButton.selectedTag == 2) {
		[self chooseFolderWithButton:self.transcriptFolderButton
					 completionBlock:^(NSData *bookmark) {
						 [self setTranscriptFolderURL:bookmark];
					 }];
	} else if (self.transcriptFolderButton.selectedTag == 3) {
		[self.transcriptFolderButton selectItemAtIndex:0];

		[self setTranscriptFolderURL:nil];
	}
}

- (void)setTranscriptFolderURL:(nullable NSData *)transcriptFolderURL
{
	[TPCPathInfo setTranscriptFolderURL:transcriptFolderURL];

	[TPCPreferences performReloadAction:TPCPreferencesReloadActionLogTranscripts];

	[self updateTranscriptFolder];
}

#pragma mark -
#pragma mark Theme

- (void)updateThemeSelection
{
	[self.themeSelectionButton removeAllItems];

	NSMenuItem *nativeItem = [[NSMenuItem alloc] initWithTitle:TXTLS(@"TDCPreferencesController[native-style]")
														action:nil
												 keyEquivalent:@""];
	nativeItem.tag = 100;
	[self.themeSelectionButton.menu addItem:nativeItem];
	[self.themeSelectionButton selectItemWithTag:100];
	self.themeSelectionButton.enabled = NO;
}

- (void)onChangedThemeSelection:(nullable id)sender
{
	NSMenuItem *selectedItem = self.themeSelectionButton.selectedItem;

	NSDictionary *context = selectedItem.representedObject;

	NSString *newThemeName = context[@"themeName"];

	TPCThemeStorageLocation newStorageLocation = [context unsignedIntegerForKey:@"storageLocation"];

	NSString *newTheme = [TPCThemeController buildFilename:newThemeName forStorageLocation:newStorageLocation];

	NSString *currentTheme = [TPCPreferences themeName];

	if ([currentTheme isEqualToString:newTheme]) {
		return;
	}

	[TPCPreferences setThemeName:newTheme];

	self.reloadingThemeBySelection = YES;

	[self onChangedTheme:nil];
}

- (void)onChangedThemeSelectionReloadComplete:(NSNotification *)notification
{
	NSMutableString *forcedValuesMutable = [NSMutableString string];

	if ([TPCPreferences themeNicknameFormatPreferenceUserConfigurable] == NO) {
		[forcedValuesMutable appendString:TXTLS(@"TDCPreferencesController[77t-de]")];

		[forcedValuesMutable appendString:@"\n"];
	}

	if ([TPCPreferences themeTimestampFormatPreferenceUserConfigurable] == NO) {
		[forcedValuesMutable appendString:TXTLS(@"TDCPreferencesController[ddh-hr]")];

		[forcedValuesMutable appendString:@"\n"];
	}

	if ([TPCPreferences themeChannelViewFontPreferenceUserConfigurable] == NO) {
		[forcedValuesMutable appendString:TXTLS(@"TDCPreferencesController[we8-i8]")];

		[forcedValuesMutable appendString:@"\n"];
	}

	NSString *forcedValues = forcedValuesMutable.trim;

	if (forcedValues.length == 0) {
		return;
	}

	NSString *currentTheme = [TPCPreferences themeName];

	NSString *themeName = [TPCThemeController extractThemeName:currentTheme];

	[TDCAlert alertSheetWithWindow:[NSApp keyWindow]
							  body:TXTLS(@"TDCPreferencesController[q4o-2f]", themeName, forcedValues)
							 title:TXTLS(@"TDCPreferencesController[uc0-z7]")
					 defaultButton:TXTLS(@"Prompts[c7s-dq]")
				   alternateButton:nil
					   otherButton:nil
					suppressionKey:@"theme_override_info"
				   suppressionText:nil
				   completionBlock:nil];
}

- (void)onSelectNewFont:(nullable id)sender
{
	NSFont *currentFont = [TPCPreferences themeChannelViewFont];

	[RZFontManager() setSelectedFont:currentFont isMultiple:NO];

	[RZFontManager() orderFrontFontPanel:self];

	/* The font manager is shared. Remember its previous action so it
	 can be restored when this window closes. */
	if (self.fontPanelIsOwned == NO) {
		self.previousFontManagerAction = RZFontManager().action;

		self.fontPanelIsOwned = YES;
	}

	RZFontManager().action = @selector(onChangedChannelViewFont:);
}

- (void)releaseFontPanel
{
	if (self.fontPanelIsOwned == NO) {
		return;
	}

	self.fontPanelIsOwned = NO;

	RZFontManager().action = self.previousFontManagerAction;

	self.previousFontManagerAction = NULL;

	if ([NSFontPanel sharedFontPanelExists]) {
		[[NSFontPanel sharedFontPanel] orderOut:self];
	}
}

- (void)onChangedChannelViewFont:(NSFontManager *)sender
{
	NSFont *currentFont = [TPCPreferences themeChannelViewFont];

	NSFont *newFont = [sender convertFont:currentFont];

	[self willChangeValueForKey:@"themeChannelViewFontName"];
	[self willChangeValueForKey:@"themeChannelViewFontSize"];

	[TPCPreferences setThemeChannelViewFontName:newFont.fontName];
	[TPCPreferences setThemeChannelViewFontSize:newFont.pointSize];

	[self didChangeValueForKey:@"themeChannelViewFontName"];
	[self didChangeValueForKey:@"themeChannelViewFontSize"];

	[self onChangedTheme:nil];
}

#pragma mark -
#pragma mark User Style Sheet Rules

- (void)onModifyUserStyleSheetRules:(nullable id)sender
{
	TDCPreferencesUserStyleSheet *sheet = [[TDCPreferencesUserStyleSheet alloc] initWithWindow:self.window];

	sheet.delegate = (id)self;

	[sheet start];

	self.userStyleSheet = sheet;
}

- (void)userStyleSheetRulesChanged:(TDCPreferencesUserStyleSheet *)sender
{
	[self onChangedTheme:nil];
}

- (void)userStyleSheetWillClose:(TDCPreferencesUserStyleSheet *)sender
{
	self.userStyleSheet = nil;
}

#pragma mark -
#pragma mark Forward Notice To

- (void)updateForwardNoticeToMatrix
{
	TXNoticeSendLocation location = [TPCPreferences locationToSendNotices];

	self.forwardNoticeToServerConsoleButton.state = (location == TXNoticeSendLocationServerConsole);
	self.forwardNoticeToSelectedChannelButton.state = (location == TXNoticeSendLocationSelectedChannel);
	self.forwardNoticeToQueryButton.state = (location == TXNoticeSendLocationQuery);
}

- (void)onChangedForwardNoticeTo:(nullable id)sender
{
	[TPCPreferences setLocationToSendNotices:[sender tag]];
}

#pragma mark -
#pragma mark Updates

- (void)updateCheckForUpdatesMatrix
{
#if GLASSTUAL_BUILT_WITH_SPARKLE_ENABLED == 1
	SPUUpdater *updater = masterController().updateController.updater;

	self.checkForUpdatesAutomaticallyDownload.state = updater.automaticallyDownloadsUpdates;
	self.checkForUpdatesAutomaticallyCheck.state = updater.automaticallyChecksForUpdates;
	self.checkForUpdatesDontCheck.state =
		(updater.automaticallyDownloadsUpdates == NO && updater.automaticallyChecksForUpdates == NO);
#endif
}

- (void)onChangedCheckForUpdates:(nullable id)sender
{
#if GLASSTUAL_BUILT_WITH_SPARKLE_ENABLED == 1
	SPUUpdater *updater = masterController().updateController.updater;

	updater.automaticallyChecksForUpdates = (self.checkForUpdatesAutomaticallyCheck.state == NSControlStateValueOn);
	updater.automaticallyDownloadsUpdates = (self.checkForUpdatesAutomaticallyDownload.state == NSControlStateValueOn);
#endif
}

- (void)onChangedCheckForBetaUpdates:(nullable id)sender
{
#if GLASSTUAL_BUILT_WITH_SPARKLE_ENABLED == 1
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionSparkleFrameworkFeedURL];

	if ([TPCPreferences receiveBetaUpdates]) {
		[menuController() checkForUpdates:nil];
	}
#endif
}

#pragma mark -
#pragma mark Actions

- (void)onChangedDisableNicknameColorHashing:(nullable id)sender
{
	[self onChangedTheme:nil];
}

#if GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION == 1
- (void)offRecordMessagingPolicyChanged:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionEncryptionPolicy];
}

- (void)offRecordMessagingOpenOfficialWebsite:(nullable id)sender
{
	[TLOpenLink openWithString:@"https://otr.cypherpunks.ca/"];
}
#endif

- (void)onChangedHighlightType:(nullable id)sender
{
	[self willChangeValueForKey:@"highlightCurrentNickname"];
	[self didChangeValueForKey:@"highlightCurrentNickname"];

	if ([TPCPreferences highlightMatchingMethod] == TXNicknameHighlightMatchTypeRegularExpression) {
		self.highlightNicknameButton.enabled = NO;
	} else {
		self.highlightNicknameButton.enabled = YES;
	}
}

- (void)editTableView:(NSTableView *)tableView
{
	NSInteger rowSelection = (tableView.numberOfRows - 1);

	[tableView scrollRowToVisible:rowSelection];

	[tableView editColumn:0 row:rowSelection withEvent:nil select:YES];
}

- (void)onAddHighlightKeyword:(nullable id)sender
{
	[self.highlightKeywordsArrayController add:nil];

	XRPerformBlockAsynchronouslyOnMainQueue(^{
		[self editTableView:self.highlightKeywordsTable];
	});
}

- (void)onAddExcludeKeyword:(nullable id)sender
{
	[self.excludeKeywordsArrayController add:nil];

	XRPerformBlockAsynchronouslyOnMainQueue(^{
		[self editTableView:self.excludeKeywordsTable];
	});
}

+ (void)openProxySettingsInSystemPreferences
{
	AEDesc aeDesc = {typeNull, NULL};

	OSStatus aeDescStatus = AECreateDesc('ptru', "Proxies", 7, &aeDesc);

	if (aeDescStatus != noErr) {
		LogToConsoleError("aeDescStatus returned value other than noErr: %{public}i", aeDescStatus);

		return;
	}

	NSURL *prefPaneURL = [NSURL fileURLWithPath:@"/System/Library/PreferencePanes/Network.prefPane"];

	LSLaunchURLSpec launchSpec = {0};

	launchSpec.appURL = NULL;
	launchSpec.asyncRefCon = NULL;
	launchSpec.itemURLs = (__bridge CFArrayRef) @[ prefPaneURL ];
	launchSpec.launchFlags = (kLSLaunchAsync | kLSLaunchDontAddToRecents);
	launchSpec.passThruParams = &aeDesc;

	(void)LSOpenFromURLSpec(&launchSpec, NULL);
}

- (void)updateInlineMediaEnabled
{
	if ([TPCPreferences showInlineMedia]) {
		self.inlineMediaEnabledButton.state = NSControlStateValueOn;
	} else {
		self.inlineMediaEnabledButton.state = NSControlStateValueOff;
	}
}

- (void)onChangedInlineMediaOption:(nullable id)sender
{
	if (self.inlineMediaEnabledButton.state == NSControlStateValueOff) {
		[TPCPreferences setShowInlineMedia:NO];

		[self onChangedTheme:nil];

		return;
	}

	[TVCLogControllerInlineMediaService askPermissionToEnableInlineMediaWithCompletionBlock:^(BOOL granted) {
		if (granted) {
			[TPCPreferences setShowInlineMedia:YES];

			[self onChangedTheme:nil];
		} else {
			self.inlineMediaEnabledButton.state = NSControlStateValueOff;
		}
	}];
}

- (void)onResetUserListModeColorsToDefaults:(nullable id)sender
{
	[RZUserDefaults() setObject:nil forKey:@"User List Mode Badge Colors -> +y"];
	[RZUserDefaults() setObject:nil forKey:@"User List Mode Badge Colors -> +q"];
	[RZUserDefaults() setObject:nil forKey:@"User List Mode Badge Colors -> +a"];
	[RZUserDefaults() setObject:nil forKey:@"User List Mode Badge Colors -> +o"];
	[RZUserDefaults() setObject:nil forKey:@"User List Mode Badge Colors -> +h"];
	[RZUserDefaults() setObject:nil forKey:@"User List Mode Badge Colors -> +v"];
	[RZUserDefaults() setObject:nil forKey:@"User List Mode Badge Colors -> no mode"];

	[self onChangedUserListModeColor:nil];
}

- (void)onResetServerListUnreadBadgeColorsToDefault:(nullable id)sender
{
	[self willChangeValueForKey:@"serverListUnreadCountBadgeHighlightColor"];

	[RZUserDefaults() setObject:nil forKey:@"Server List Unread Message Count Badge Colors -> Highlight"];

	[self didChangeValueForKey:@"serverListUnreadCountBadgeHighlightColor"];

	[self onChangedServerListUnreadBadgeColor:sender];
}

- (void)onChangedInputHistoryScheme:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionInputHistoryScope];
}

- (void)onChangedAppearance:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionAppearance];
}

- (void)onChangedTheme:(nullable id)sender
{
	[TPCPreferences performReloadAction:(TPCPreferencesReloadActionStyle | TPCPreferencesReloadActionTextDirection)];
}

- (void)onThemeWillReload:(NSNotification *)notification
{
	self.reloadingTheme = YES;
}

- (void)onThemeReloadComplete:(NSNotification *)notification
{
	self.reloadingTheme = NO;

	if (self.reloadingThemeBySelection) {
		self.reloadingThemeBySelection = NO;

		[self onChangedThemeSelectionReloadComplete:notification];
	}
}

- (void)onChangedChannelViewArrangement:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionChannelViewArrangement];
}

- (void)onChangedUserListModeColor:(nullable id)sender
{
	static NSDictionary<NSNumber *, NSString *> *preferenceMap = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		preferenceMap = @{
			@(10) : @"User List Mode Badge Colors -> +y",
			@(9) : @"User List Mode Badge Colors -> +q",
			@(8) : @"User List Mode Badge Colors -> +a",
			@(7) : @"User List Mode Badge Colors -> +o",
			@(6) : @"User List Mode Badge Colors -> +h",
			@(5) : @"User List Mode Badge Colors -> +v",
			@(4) : @"User List Mode Badge Colors -> no mode"
		};
	});

	NSString *preferenceKey = preferenceMap[@([sender tag])];

	/* -onResetUserListModeColorsToDefaults: passes nil sender */
	if (preferenceKey == nil) {
		[TPCPreferences performReloadAction:(TPCPreferencesReloadActionMemberListUserBadges |
											 TPCPreferencesReloadActionMemberList)];
	} else {
		[TPCPreferences performReloadAction:TPCPreferencesReloadActionMemberListUserBadges forKey:preferenceKey];
	}
}

- (void)onChangedMainInputTextViewFontSize:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionTextFieldFontSize];
}

- (void)onFileTransferIPAddressDetectionMethodChanged:(nullable id)sender
{
	TXFileTransferIPAddressMethodDetection detectionMethod = [TPCPreferences fileTransferIPAddressDetectionMethod];

	self.fileTransferManuallyEnteredIPAddressTextField.enabled =
		(detectionMethod == TXFileTransferIPAddressMethodManual);
}

- (void)onChangedHighlightLogging:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionHighlightLogging];
}

- (void)onChangedUserListModeSortOrder:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionMemberListSortOrder];
}

- (void)onChangedServerListUnreadBadgeColor:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionServerListUnreadBadges];
}

- (void)onChangedScrollbackSaveLimit:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionScrollbackSaveLimit];
}

- (void)onChangedScrollbackVisibleLimit:(nullable id)sender
{
	[TPCPreferences performReloadAction:TPCPreferencesReloadActionScrollbackVisibleLimit];
}

- (void)onOpenPathToScripts:(nullable id)sender
{
	[RZWorkspace() openURL:[TPCPathInfo groupContainerApplicationSupportURL]];
}

- (void)openPathToThemesCallback:(TDCAlertResponse)returnCode withOriginalAlert:(NSAlert *)originalAlert
{
	NSParameterAssert(originalAlert != nil);

	if (returnCode == TDCAlertResponseDefault) {
		[self openPathToTheme];
	}

	if (returnCode == TDCAlertResponseAlternate) {
		[self onModifyUserStyleSheetRules:nil];
	}

	if (returnCode == TDCAlertResponseOther) {
		[originalAlert.window orderOut:nil];

		[themeController() copyActiveThemeToDestinationLocation:TPCThemeStorageLocationCustom
												   reloadOnCopy:YES
													 openOnCopy:YES];
	}
}

- (void)onOpenPathToTheme:(nullable id)sender
{
	if (themeController().bundledTheme) {
		[TDCAlert alertSheetWithWindow:NSApp.keyWindow
								  body:TXTLS(@"TDCPreferencesController[ojj-ap]")
								 title:TXTLS(@"TDCPreferencesController[5jv-aw]")
						 defaultButton:TXTLS(@"TDCPreferencesController[6ws-av]")
					   alternateButton:TXTLS(@"TDCPreferencesController[aib-iy]")
						   otherButton:TXTLS(@"TDCPreferencesController[dj8-1t]")
					   completionBlock:^(TDCAlertResponse buttonClicked, BOOL suppressed, id underlyingAlert) {
						   [self openPathToThemesCallback:buttonClicked withOriginalAlert:underlyingAlert];
					   }];

		return;
	}

	[self openPathToTheme];
}

- (void)openPathToTheme
{
	NSURL *fileURL = themeController().originalURL;

	[RZWorkspace() openURL:fileURL];
}

- (void)onThemeListDidChange:(NSNotification *)aNote
{
	[self updateThemeSelection];
}

#pragma mark -
#pragma mark NSWindow Delegate

- (void)windowWillClose:(NSNotification *)note
{
	[RZNotificationCenter() removeObserver:self];

	[self releaseFontPanel];

	[self saveWindowFrame];

	if ([self.delegate respondsToSelector:@selector(preferencesDialogWillClose:)]) {
		[self.delegate preferencesDialogWillClose:self];
	}
}

@end

NS_ASSUME_NONNULL_END
