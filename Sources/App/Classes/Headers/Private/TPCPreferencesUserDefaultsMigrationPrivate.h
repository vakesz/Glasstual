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

#import "TPCPreferencesUserDefaults.h"

NS_ASSUME_NONNULL_BEGIN

@interface TPCPreferencesUserDefaults (
    TPCPreferencesUserDefaultsMigrationPrivate)
- (void)_setObject:(nullable id)value forKey:(NSString *)defaultName;
- (void)_migrateObject:(nullable id)value forKey:(NSString *)defaultName;
@end

NS_ASSUME_NONNULL_END
