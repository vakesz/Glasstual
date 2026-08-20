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

#define _toolbarItemIndexGeneral 101
#define _toolbarItemIndexHighlights 104
#define _toolbarItemIndexNotifications 103
#define _toolbarItemIndexBehavior 102
#define _toolbarItemIndexControls 107
#define _toolbarItemIndexInterface 105
#define _toolbarItemIndexStyle 106
#define _toolbarItemIndexAddons 109
#define _toolbarItemIndexAdvanced 108

#define _toolbarItemIndexChannelManagement 108000
#define _toolbarItemIndexCommandScope 108001
#define _toolbarItemIndexFloodControl 108002
#define _toolbarItemIndexIncomingData 108003
#define _toolbarItemIndexCompatibility 108004
#define _toolbarItemIndexFileTransfers 108005
#define _toolbarItemIndexInlineMedia 108006
#define _toolbarItemIndexLogLocation 108007
#define _toolbarItemIndexDefaultIdentity 108008
#define _toolbarItemIndexDefaultIRCopMessages 108009
#define _toolbarItemIndexOffRecordMessaging 108010
#define _toolbarItemIndexHiddenPreferences 108011

#define _addonsToolbarInstalledAddonsMenuItemIndex 109000
#define _addonsToolbarItemMultiplier 995

#define _unsignedIntegerString(_value_) [NSString stringWithUnsignedInteger:_value_]

/* Declared by hand rather than imported from the generated Swift header: the
 Swift side references TDCPreferencesController, so importing it here would be
 circular. Kept in step with TDCPreferencesSettingsView.swift. */
@interface TDCPreferencesSettingsBridge : NSObject
- (void)selectPane:(NSString *)identifier;
- (NSViewController *)makeViewControllerWithController:(TDCPreferencesController *)controller;
@end

@interface TDCPreferencesController ()
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
@property(nonatomic, strong) IBOutlet NSToolbar *navigationToolbar;
@property(nonatomic, strong) IBOutlet NSMenu *installedAddonsMenu;
@property(nonatomic, strong) NSViewController *settingsHostingController;
@property(nonatomic, strong) TDCPreferencesSettingsBridge *settingsBridge;
@property(nonatomic, assign) BOOL reloadingTheme;
@property(nonatomic, assign) BOOL reloadingThemeBySelection;
@property(nonatomic, weak) IBOutlet NSView *notificationControllerHostView;
@property(nonatomic, strong) IBOutlet TVCNotificationConfigurationViewController *notificationController;
@property(nonatomic, strong) TDCPreferencesUserStyleSheet *userStyleSheet;

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
- (IBAction)onChangedTransparency:(nullable id)sender;
- (IBAction)onChangedUserListModeColor:(nullable id)sender;
- (IBAction)onChangedUserListModeSortOrder:(nullable id)sender;
- (IBAction)onFileTransferDownloadDestinationFolderChanged:(nullable id)sender;
- (IBAction)onFileTransferIPAddressDetectionMethodChanged:(nullable id)sender;
- (IBAction)onModifyUserStyleSheetRules:(nullable id)sender;
- (IBAction)onOpenPathToScripts:(nullable id)sender;
- (IBAction)onOpenPathToTheme:(nullable id)sender; // changed
- (IBAction)onPrefPaneSelected:(nullable id)sender;
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

	[self setUpToolbarItemsAndMenus];

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

	[self installSettingsSidebar];

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

	[self.settingsBridge selectPane:identifier];

	[super show];
}

#pragma mark -
#pragma mark NSToolbar Delegates

- (void)setUpToolbarItemsAndMenus
{
	NSArray *plugins = sharedPluginManager().pluginsWithPreferencePanes;

	if (plugins.count > 0) {
		[self.installedAddonsMenu addItem:[NSMenuItem separatorItem]];
	}

	[plugins enumerateObjectsUsingBlock:^(THOPluginItem *plugin, NSUInteger index, BOOL *stop) {
		NSUInteger tagIndex = (index + _addonsToolbarItemMultiplier);

		NSMenuItem *pluginMenu = [NSMenuItem menuItemWithTitle:plugin.pluginPreferencesPaneMenuItemTitle
														target:self
														action:@selector(onPrefPaneSelected:)];

		pluginMenu.tag = tagIndex;

		[self.installedAddonsMenu addItem:pluginMenu];
	}];
}

- (void)onPrefPaneSelected:(nullable id)sender
{
	NSInteger tag = [sender tag];
	NSString *identifier = [self settingsPaneIdentifierForTag:tag];

	if (identifier) {
		[self.settingsBridge selectPane:identifier];
	}
}

/* Group identifiers are a contract with TDCPreferencesSettingsView.swift,
 which uses them to build the sidebar's sections. */
#define _settingsGroupMain @"main"
#define _settingsGroupAddons @"addons"
#define _settingsGroupAdvanced @"advanced"

/* One table drives the sidebar, the toolbar/menu tag lookup, and the pane
 lookup. Keeping them in a single place is deliberate: when they were three
 separate switch statements the Compatibility pane silently fell out of the
 sidebar while remaining reachable everywhere else. */
typedef struct {
	NSInteger tag;
	__unsafe_unretained NSString *identifier;
	__unsafe_unretained NSString *symbolName;
	__unsafe_unretained NSString *contentViewKey;
	__unsafe_unretained NSString *group;
} TDCPreferencesSettingsPane;

static const TDCPreferencesSettingsPane _settingsPanes[] = {
	{_toolbarItemIndexGeneral, @"general", @"gearshape", @"contentViewGeneral", _settingsGroupMain},
	{_toolbarItemIndexBehavior, @"behavior", @"slider.horizontal.3", @"contentViewBehavior", _settingsGroupMain},
	{_toolbarItemIndexNotifications, @"notifications", @"bell", @"contentViewNotifications", _settingsGroupMain},
	{_toolbarItemIndexHighlights, @"highlights", @"text.magnifyingglass", @"contentViewHighlights", _settingsGroupMain},
	{_toolbarItemIndexInterface, @"interface", @"macwindow", @"contentViewInterface", _settingsGroupMain},
	{_toolbarItemIndexStyle, @"style", @"paintbrush", @"contentViewStyle", _settingsGroupMain},
	{_toolbarItemIndexControls, @"controls", @"keyboard", @"contentViewControls", _settingsGroupMain},

	{_toolbarItemIndexAddons, @"addons", @"puzzlepiece.extension", @"contentViewInstalledAddons", _settingsGroupAddons},

	{_toolbarItemIndexChannelManagement,
	 @"channelManagement",
	 @"person.2",
	 @"contentViewChannelManagement",
	 _settingsGroupAdvanced},
	{_toolbarItemIndexCommandScope, @"commandScope", @"terminal", @"contentViewCommandScope", _settingsGroupAdvanced},
	{_toolbarItemIndexCompatibility,
	 @"compatibility",
	 @"wrench.and.screwdriver",
	 @"contentViewCompatibility",
	 _settingsGroupAdvanced},
	{_toolbarItemIndexFloodControl, @"floodControl", @"timer", @"contentViewFloodControl", _settingsGroupAdvanced},
	{_toolbarItemIndexIncomingData,
	 @"incomingData",
	 @"arrow.down.circle",
	 @"contentViewIncomingData",
	 _settingsGroupAdvanced},
	{_toolbarItemIndexFileTransfers,
	 @"fileTransfers",
	 @"arrow.down.app",
	 @"contentViewFileTransfers",
	 _settingsGroupAdvanced},
	{_toolbarItemIndexInlineMedia, @"inlineMedia", @"photo", @"contentViewInlineMedia", _settingsGroupAdvanced},
	{_toolbarItemIndexLogLocation, @"logLocation", @"folder", @"contentViewLogLocation", _settingsGroupAdvanced},
	{_toolbarItemIndexDefaultIdentity,
	 @"defaultIdentity",
	 @"person.crop.circle",
	 @"contentViewDefaultIdentity",
	 _settingsGroupAdvanced},
	{_toolbarItemIndexDefaultIRCopMessages,
	 @"defaultIRCopMessages",
	 @"shield",
	 @"contentViewDefaultIRCopMessages",
	 _settingsGroupAdvanced},
#if GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION == 1
	{_toolbarItemIndexOffRecordMessaging,
	 @"offRecordMessaging",
	 @"lock.fill",
	 @"contentViewOffRecordMessaging",
	 _settingsGroupAdvanced},
#endif
	{_toolbarItemIndexHiddenPreferences,
	 @"hidden",
	 @"eye.slash",
	 @"contentViewHiddenPreferences",
	 _settingsGroupAdvanced},
};

static const NSUInteger _settingsPaneCount = (sizeof(_settingsPanes) / sizeof(TDCPreferencesSettingsPane));

static NSString *TDCPreferencesSettingsPluginIdentifier(NSUInteger index)
{
	return [NSString stringWithFormat:@"plugin-%lu", (unsigned long)index];
}

static const TDCPreferencesSettingsPane *TDCPreferencesSettingsPaneForIdentifier(NSString *identifier)
{
	for (NSUInteger i = 0; i < _settingsPaneCount; i++) {
		if ([_settingsPanes[i].identifier isEqualToString:identifier]) {
			return &_settingsPanes[i];
		}
	}

	return NULL;
}

- (nullable NSString *)settingsPaneIdentifierForTag:(NSInteger)tag
{
	if (tag == _addonsToolbarInstalledAddonsMenuItemIndex) {
		return @"addons";
	}

	for (NSUInteger i = 0; i < _settingsPaneCount; i++) {
		if (_settingsPanes[i].tag == tag) {
			return _settingsPanes[i].identifier;
		}
	}

	if (tag >= _addonsToolbarItemMultiplier) {
		return TDCPreferencesSettingsPluginIdentifier((NSUInteger)(tag - _addonsToolbarItemMultiplier));
	}

	return nil;
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

- (void)installSettingsSidebar
{
	NSWindow *window = self.window;
	window.toolbarStyle = NSWindowToolbarStyleUnified;
	window.titlebarAppearsTransparent = NO;
	window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleAutomatic;
	window.styleMask = (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
						NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView);
	window.minSize = NSMakeSize(860.0, 560.0);
	window.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	window.contentMinSize = NSMakeSize(640.0, 480.0);
	window.contentMaxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	window.toolbar = nil;

	TDCPreferencesSettingsBridge *settingsBridge = [TDCPreferencesSettingsBridge new];
	self.settingsBridge = settingsBridge;

	NSViewController *hostingController = [settingsBridge makeViewControllerWithController:self];
	self.settingsHostingController = hostingController;
	window.contentViewController = hostingController;
}

- (void)restoreWindowFrame
{
	NSWindow *window = self.window;

	window.styleMask = (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
						NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView);
	window.minSize = NSMakeSize(860.0, 560.0);
	window.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	window.contentMinSize = NSMakeSize(640.0, 480.0);
	window.contentMaxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);

	[window saveSizeAsDefault];

	[window restoreWindowStateForClass:self.class];

	NSSize frameSize = window.frame.size;

	if (frameSize.width < 860.0 || frameSize.height < 560.0) {
		[window setContentSize:NSMakeSize(960.0, 640.0)];
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

		if (valueInteger > valueRangeEnd) {
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

		if (valueInteger < valueRangeStart) {
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

- (void)onChangedTransparency:(nullable id)sender
{
	[mainWindow() updateAlphaValueToReflectPreferences];
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
