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

#import "BuildConfig.h"
#import "TXSharedApplicationPrivate.h"

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain const TXErrorDomain = @"GlasstualErrorDomain";

os_log_t ApplicationTerminationLogSubsystem(void) {
  static os_log_t cachedValue = NULL;

  static dispatch_once_t onceToken;

  dispatch_once(&onceToken, ^{
    cachedValue =
        os_log_create(TXBundleBuildProductIdentifierCString, "Termination");
  });

  return cachedValue;
}

NS_ASSUME_NONNULL_END
