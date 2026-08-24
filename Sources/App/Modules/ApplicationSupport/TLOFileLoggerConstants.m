/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import "TLOFileLoggerPrivate.h"

NSString *const TLOFileLoggerConsoleDirectoryName = @"Console";
NSString *const TLOFileLoggerChannelDirectoryName = @"Channels";
NSString *const TLOFileLoggerPrivateMessageDirectoryName = @"Queries";

NSString *const TLOFileLoggerUndefinedNicknameFormat = @"<%@%n>";
NSString *const TLOFileLoggerActionNicknameFormat = @"\u2022 %n:";
NSString *const TLOFileLoggerNoticeNicknameFormat = @"-%n-";

NSString *const TLOFileLoggerISOStandardClockFormat = @"[%Y-%m-%dT%H:%M:%S%z]";
