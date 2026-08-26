/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

#import "THOPluginItemSupportedFeature.h"

NS_ASSUME_NONNULL_BEGIN

@class THOPluginOutputSuppressionRule;

@interface THOPluginItem : NSObject
@property(readonly, nullable) NSBundle *bundle;
@property(readonly, nullable) id primaryClass;
@property(readonly, assign) THOPluginItemSupportedFeature supportedFeatures;
@property(readonly, copy, nullable)
    NSArray<NSString *> *supportedServerInputCommands;
@property(readonly, copy, nullable)
    NSArray<NSString *> *supportedUserInputCommands;
@property(readonly, copy, nullable)
    NSArray<THOPluginOutputSuppressionRule *> *outputSuppressionRules;
@property(readonly, copy, nullable)
    NSString *pluginPreferencesPaneMenuItemTitle;
@property(readonly, nullable) NSView *pluginPreferencesPaneView;

- (BOOL)loadBundle:(NSBundle *)bundle;
- (void)unloadBundle;

- (BOOL)supportsFeature:(THOPluginItemSupportedFeature)feature;
@end

NS_ASSUME_NONNULL_END
