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

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, THOPluginItemSupportedFeature) {
	THOPluginItemSupportedFeatureDidReceiveCommandEvent = 1 << 1,
	THOPluginItemSupportedFeatureDidReceivePlainTextMessageEvent = 1 << 2,
	//	THOPluginItemSupportedFeatureInlineMediaManipulation			= 1 << 3,
	THOPluginItemSupportedFeatureNewMessagePostedEvent = 1 << 4,
	THOPluginItemSupportedFeatureOutputSuppressionRules = 1 << 5,
	THOPluginItemSupportedFeaturePreferencePane = 1 << 6,
	THOPluginItemSupportedFeatureServerInputDataInterception = 1 << 7,
	THOPluginItemSupportedFeatureSubscribedServerInputCommands = 1 << 8,
	THOPluginItemSupportedFeatureSubscribedUserInputCommands = 1 << 9,
	THOPluginItemSupportedFeatureUserInputDataInterception = 1 << 10,
	THOPluginItemSupportedFeatureWebViewJavaScriptPayloads = 1 << 11,
	THOPluginItemSupportedFeatureWillRenderMessageEvent = 1 << 12,
};

NS_ASSUME_NONNULL_END
