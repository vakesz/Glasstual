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

#import "HLSHistoricLogProtocol.h"

#import "TXMasterController.h"
#import "IRCTreeItem.h"
#import "IRCWorld.h"
#import "TDCAlert.h"
#import "TLOLocalization.h"
#import "TPCPathInfo.h"
#import "TPCPreferencesLocalPrivate.h"
#import "TPCPreferencesUserDefaults.h"
#import "TVCLogControllerPrivate.h"
#import "TVCLogLinePrivate.h"
#import "TVCLogLineXPCPrivate.h"
#import "TVCLogControllerHistoricLogFilePrivate.h"

NS_ASSUME_NONNULL_BEGIN

/* What the client knows about the lines of one view, kept in memory so
 that chat history replayed by the server can be checked against the
 local scrollback without a round trip to the XPC service. The index is
 filled from every line written and every line fetched. */
@interface TVCLogControllerHistoricLogViewIndex : NSObject
@property(nonatomic, strong) NSMutableSet<NSString *> *messageIdentifiers;
@property(nonatomic, strong) NSMutableSet<NSString *> *fallbackKeys;
@property(nonatomic, copy, nullable) NSDate *newestDate;
@property(nonatomic, copy, nullable) NSDate *oldestDate;
@end

@implementation TVCLogControllerHistoricLogViewIndex

- (instancetype)init
{
	if ((self = [super init])) {
		self.messageIdentifiers = [NSMutableSet set];
		self.fallbackKeys = [NSMutableSet set];

		return self;
	}

	return nil;
}

@end

#pragma mark -

@interface TVCLogControllerHistoricLogFile ()
@property(nonatomic, strong) NSMutableDictionary<NSString *, TVCLogControllerHistoricLogViewIndex *> *viewIndexes;
@property(nonatomic, assign, readwrite) BOOL isSaving;
@property(nonatomic, assign, readwrite) BOOL isTerminating;
@property(nonatomic, assign, readwrite) BOOL processLoaded;
@property(nonatomic, assign, readwrite) BOOL processLoading;
@property(nonatomic, strong, nullable) NSXPCConnection *serviceConnection;
@property(nonatomic, assign) BOOL connectionInvalidatedVoluntarily;
@property(nonatomic, assign) BOOL connectionInvalidatedErrorDialogDisplayed;
@property(nonatomic, copy, nullable) NSError *lastServiceConnectionError;
@property(nonatomic, copy, nullable) void (^terminationCompletionBlock)(void);
@end

@implementation TVCLogControllerHistoricLogFile

+ (TVCLogControllerHistoricLogFile *)sharedInstance
{
	static id sharedSelf = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		sharedSelf = [[self alloc] init];
	});

	return sharedSelf;
}

- (instancetype)init
{
	if ((self = [super init])) {
		self.viewIndexes = [NSMutableDictionary dictionary];

		return self;
	}

	return nil;
}

#pragma mark -
#pragma mark Save Path

- (NSString *)databaseSavePath
{
	return [TPCPathInfo groupContainerApplicationCaches];
}

#pragma mark -
#pragma mark Construction

- (void)warmProcessIfNeeded
{
	if (self.processLoading || self.processLoaded) {
		return;
	}

	LogToConsoleDebug("Warming process...");

	self.processLoading = YES;

	[self connectToService];

	[self openDatabase];

	[self resetMaximumLineCount];
}

- (void)invalidateProcess
{
	if (self.processLoading == NO && self.processLoaded == NO) {
		return;
	}

	LogToConsoleDebug("Invalidating process...");

	self.connectionInvalidatedVoluntarily = YES;

	[self.serviceConnection invalidate];
}

- (void)openDatabase
{
	[[self remoteObjectProxyWithErrorHandler:^(NSError *error) {
		self.processLoading = NO;
		self.processLoaded = NO;

		LogToConsoleError("Failed to communicate with process to open database");
	}] openDatabaseInDirectory:[self databaseSavePath]
		   withCompletionBlock:^(BOOL success) {
			   if (success) {
				   LogToConsoleDebug("Successfully opened database");
			   } else {
				   LogToConsoleError("Failed to open database");
			   }

			   self.processLoading = NO;
			   self.processLoaded = success;
		   }];
}

- (void)connectToService
{
	NSXPCConnection *serviceConnection =
		[[NSXPCConnection alloc] initWithServiceName:@"com.vakesz.glasstual.ScrollbackHistoryManager"];

	NSXPCInterface *remoteObjectInterface =
		[NSXPCInterface interfaceWithProtocol:@protocol(HLSHistoricLogServerProtocol)];

	[remoteObjectInterface setClasses:[NSSet setWithObjects:[NSArray class], [TVCLogLineXPC class], nil]
						  forSelector:@selector(fetchEntriesForView:
														  ascending:fetchLimit:limitToDate:withCompletionBlock:)
						argumentIndex:0
							  ofReply:YES];

	[remoteObjectInterface
		   setClasses:[NSSet setWithObjects:[NSArray class], [TVCLogLineXPC class], nil]
		  forSelector:@selector(fetchEntriesForView:
							   withUniqueIdentifier:beforeFetchLimit:afterFetchLimit:limitToDate:withCompletionBlock:)
		argumentIndex:0
			  ofReply:YES];

	[remoteObjectInterface setClasses:[NSSet setWithObjects:[NSArray class], [TVCLogLineXPC class], nil]
						  forSelector:@selector(fetchEntriesForView:
											 beforeUniqueIdentifier:fetchLimit:limitToDate:withCompletionBlock:)
						argumentIndex:0
							  ofReply:YES];

	[remoteObjectInterface setClasses:[NSSet setWithObjects:[NSArray class], [TVCLogLineXPC class], nil]
						  forSelector:@selector(fetchEntriesForView:
											  afterUniqueIdentifier:fetchLimit:limitToDate:withCompletionBlock:)
						argumentIndex:0
							  ofReply:YES];

	[remoteObjectInterface
		   setClasses:[NSSet setWithObjects:[NSArray class], [TVCLogLineXPC class], nil]
		  forSelector:@selector(fetchEntriesForView:
							  afterUniqueIdentifier:beforeUniqueIdentifier:fetchLimit:withCompletionBlock:)
		argumentIndex:0
			  ofReply:YES];

	serviceConnection.remoteObjectInterface = remoteObjectInterface;

	NSXPCInterface *exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(HLSHistoricLogClientProtocol)];

	serviceConnection.exportedInterface = exportedInterface;

	serviceConnection.exportedObject = self;

	__weak TVCLogControllerHistoricLogFile *weakSelf = self;

	/* Both handlers run on the connection's queue. The state they
	 touch is read by main-thread callers, so hop there first. */
	serviceConnection.interruptionHandler = ^{
		XRPerformBlockSynchronouslyOnMainQueue(^{
			[weakSelf interruptionHandler];
		});

		LogToConsole("Interruption handler called");
	};

	serviceConnection.invalidationHandler = ^{
		XRPerformBlockSynchronouslyOnMainQueue(^{
			[weakSelf invalidationHandler];
		});

		LogToConsole("Invalidation handler called");
	};

	[serviceConnection resume];

	self.serviceConnection = serviceConnection;
}

- (void)interruptionHandler
{
	[self invalidateProcess];
}

- (void)invalidationHandler
{
	self.serviceConnection = nil;

	[self resetContext];

	/* Nothing further can be saved once the connection is gone. */
	if (self.isTerminating) {
		[self invokeTerminationCompletionBlock];
	}

	if (self.connectionInvalidatedVoluntarily) {
		self.connectionInvalidatedVoluntarily = NO;

		return;
	}

	/* Error dialog is purposely only ever shown once */
	if (self.connectionInvalidatedErrorDialogDisplayed == NO) {
		self.connectionInvalidatedErrorDialogDisplayed = YES;
	} else {
		return;
	}

	NSString *lastErrorMessage = self.lastServiceConnectionError.localizedDescription;

	if (lastErrorMessage == nil) {
		lastErrorMessage = @"";
	} else {
		lastErrorMessage = TXTLS(@"Prompts[nlz-um]", lastErrorMessage);
	}

	[TDCAlert alertWithMessage:lastErrorMessage
						 title:TXTLS(@"Prompts[h99-3q]")
				 defaultButton:TXTLS(@"Prompts[c7s-dq]")
			   alternateButton:nil];
}

- (void)resetContext
{
	self.isSaving = NO;

	self.processLoading = NO;
	self.processLoaded = NO;
}

- (void)resetMaximumLineCount
{
	NSUInteger maximumLineCount = [TPCPreferences scrollbackSaveLimit];

	[[self remoteObjectProxy] setMaximumLineCount:maximumLineCount];
}

- (void)prepareForApplicationTermination
{
	[self prepareForApplicationTerminationWithCompletionBlock:nil];
}

- (void)prepareForApplicationTerminationWithCompletionBlock:(void (^_Nullable)(void))completionBlock
{
	self.isTerminating = YES;

	self.terminationCompletionBlock = completionBlock;

	/* -saveData returns NO when there is nothing to save (the service was
	 never warmed) in which case the completion block is called right away.
	 Otherwise it is called once the save that is in flight completes. */
	if ([self saveData] == NO) {
		[self invokeTerminationCompletionBlock];
	}
}

- (void)invokeTerminationCompletionBlock
{
	void (^completionBlock)(void) = self.terminationCompletionBlock;

	if (completionBlock == nil) {
		return;
	}

	self.terminationCompletionBlock = nil;

	XRPerformBlockAsynchronouslyOnMainQueue(completionBlock);
}

#pragma mark -
#pragma mark Private API

- (id<HLSHistoricLogServerProtocol>)remoteObjectProxy
{
	return [self remoteObjectProxyWithErrorHandler:nil];
}

- (id<HLSHistoricLogServerProtocol>)remoteObjectProxyWithErrorHandler:(void (^_Nullable)(NSError *error))handler
{
	return [self.serviceConnection remoteObjectProxyWithErrorHandler:^(NSError *error) {
		self.lastServiceConnectionError = error;

		LogToConsoleError("Error occurred while communicating with service: %{public}@", error.localizedDescription);

		if (handler) {
			handler(error);
		}
	}];
}

#pragma mark -
#pragma mark Public API

- (NSArray<TVCLogLine *> *)_logLinesFromXPCObjects:(NSArray<TVCLogLineXPC *> *)xpcObjects forItem:(IRCTreeItem *)item
{
	NSParameterAssert(xpcObjects != nil);

	NSMutableArray *logLines = [NSMutableArray arrayWithCapacity:xpcObjects.count];

	for (TVCLogLineXPC *xpcObject in xpcObjects) {
		TVCLogLine *logLine = [TVCLogLine logLineFromXPCObject:xpcObject];

		if (logLine == nil) {
			LogToConsoleError("Failed to initialize object %{public}@. Corrupt data?", xpcObject.description);

			continue;
		}

		[self indexLogLine:logLine forItem:item];

		[logLines addObject:logLine];
	}

	return [logLines copy];
}

#pragma mark -
#pragma mark Line Index

- (TVCLogControllerHistoricLogViewIndex *)_viewIndexForItem:(IRCTreeItem *)item create:(BOOL)create
{
	NSString *viewId = item.uniqueIdentifier;

	if (viewId == nil) {
		return nil;
	}

	@synchronized(self.viewIndexes) {
		TVCLogControllerHistoricLogViewIndex *index = self.viewIndexes[viewId];

		if (index == nil && create) {
			index = [TVCLogControllerHistoricLogViewIndex new];

			self.viewIndexes[viewId] = index;
		}

		return index;
	}
}

+ (nullable NSString *)_fallbackKeyForDate:(NSDate *)date
								  nickname:(nullable NSString *)nickname
							   messageBody:(nullable NSString *)messageBody
{
	if (date == nil || messageBody == nil) {
		return nil;
	}

	/* Server timestamps carry millisecond precision. Rounding to the
	 millisecond keeps a value parsed twice from the same string equal. */
	long long milliseconds = (long long)llround(date.timeIntervalSince1970 * 1000.0);

	return [NSString stringWithFormat:@"%lld\x1f%@\x1f%@", milliseconds, (nickname ?: @""), messageBody];
}

- (void)indexLogLine:(TVCLogLine *)logLine forItem:(IRCTreeItem *)item
{
	NSParameterAssert(logLine != nil);
	NSParameterAssert(item != nil);

	TVCLogControllerHistoricLogViewIndex *index = [self _viewIndexForItem:item create:YES];

	if (index == nil) {
		return;
	}

	NSString *messageIdentifier = logLine.messageIdentifier;

	NSString *fallbackKey = [self.class _fallbackKeyForDate:logLine.receivedAt
												   nickname:logLine.nickname
												messageBody:logLine.messageBody];

	NSDate *receivedAt = logLine.receivedAt;

	@synchronized(index) {
		if (messageIdentifier.length > 0) {
			[index.messageIdentifiers addObject:messageIdentifier];
		}

		if (fallbackKey) {
			[index.fallbackKeys addObject:fallbackKey];
		}

		if (receivedAt) {
			if (index.newestDate == nil || [receivedAt compare:index.newestDate] == NSOrderedDescending) {
				index.newestDate = receivedAt;
			}

			if (index.oldestDate == nil || [receivedAt compare:index.oldestDate] == NSOrderedAscending) {
				index.oldestDate = receivedAt;
			}
		}
	}
}

- (BOOL)containsMessageIdentifier:(NSString *)messageIdentifier forItem:(IRCTreeItem *)item
{
	NSParameterAssert(messageIdentifier != nil);
	NSParameterAssert(item != nil);

	TVCLogControllerHistoricLogViewIndex *index = [self _viewIndexForItem:item create:NO];

	if (index == nil) {
		return NO;
	}

	@synchronized(index) {
		return [index.messageIdentifiers containsObject:messageIdentifier];
	}
}

- (BOOL)containsLineReceivedAt:(NSDate *)receivedAt
					  nickname:(nullable NSString *)nickname
				   messageBody:(NSString *)messageBody
					   forItem:(IRCTreeItem *)item
{
	NSParameterAssert(receivedAt != nil);
	NSParameterAssert(messageBody != nil);
	NSParameterAssert(item != nil);

	TVCLogControllerHistoricLogViewIndex *index = [self _viewIndexForItem:item create:NO];

	if (index == nil) {
		return NO;
	}

	NSString *fallbackKey = [self.class _fallbackKeyForDate:receivedAt nickname:nickname messageBody:messageBody];

	@synchronized(index) {
		return [index.fallbackKeys containsObject:fallbackKey];
	}
}

- (nullable NSDate *)newestLineDateForItem:(IRCTreeItem *)item
{
	NSParameterAssert(item != nil);

	TVCLogControllerHistoricLogViewIndex *index = [self _viewIndexForItem:item create:NO];

	@synchronized(index) {
		return index.newestDate;
	}
}

- (nullable NSDate *)oldestLineDateForItem:(IRCTreeItem *)item
{
	NSParameterAssert(item != nil);

	TVCLogControllerHistoricLogViewIndex *index = [self _viewIndexForItem:item create:NO];

	@synchronized(index) {
		return index.oldestDate;
	}
}

- (void)_forgetIndexForItem:(IRCTreeItem *)item
{
	NSString *viewId = item.uniqueIdentifier;

	if (viewId == nil) {
		return;
	}

	@synchronized(self.viewIndexes) {
		[self.viewIndexes removeObjectForKey:viewId];
	}
}

- (void)fetchEntriesForItem:(IRCTreeItem *)item
				  ascending:(BOOL)ascending
				 fetchLimit:(NSUInteger)fetchLimit
				limitToDate:(nullable NSDate *)limitToDate
		withCompletionBlock:(void (^)(NSArray<TVCLogLine *> *entries))completionBlock
{
	[self warmProcessIfNeeded];

	__weak typeof(self) weakSelf = self;

	[[self remoteObjectProxy] fetchEntriesForView:item.uniqueIdentifier
										ascending:ascending
									   fetchLimit:fetchLimit
									  limitToDate:limitToDate
							  withCompletionBlock:^(NSArray<TVCLogLineXPC *> *entries) {
								  NSArray *logLines = [weakSelf _logLinesFromXPCObjects:entries forItem:item];

								  completionBlock(logLines);
							  }];
}

- (void)fetchEntriesForItem:(IRCTreeItem *)item
	   withUniqueIdentifier:(NSString *)uniqueId
		   beforeFetchLimit:(NSUInteger)fetchLimitBefore
			afterFetchLimit:(NSUInteger)fetchLimitAfter
				limitToDate:(nullable NSDate *)limitToDate
		withCompletionBlock:(void (^)(NSArray<TVCLogLine *> *entries))completionBlock
{
	[self warmProcessIfNeeded];

	__weak typeof(self) weakSelf = self;

	[[self remoteObjectProxy] fetchEntriesForView:item.uniqueIdentifier
							 withUniqueIdentifier:uniqueId
								 beforeFetchLimit:fetchLimitBefore
								  afterFetchLimit:fetchLimitAfter
									  limitToDate:limitToDate
							  withCompletionBlock:^(NSArray<TVCLogLineXPC *> *entries) {
								  NSArray *logLines = [weakSelf _logLinesFromXPCObjects:entries forItem:item];

								  completionBlock(logLines);
							  }];
}

- (void)fetchEntriesForItem:(IRCTreeItem *)item
	 beforeUniqueIdentifier:(NSString *)uniqueId
				 fetchLimit:(NSUInteger)fetchLimit
				limitToDate:(nullable NSDate *)limitToDate
		withCompletionBlock:(void (^)(NSArray<TVCLogLine *> *entries))completionBlock
{
	[self warmProcessIfNeeded];

	__weak typeof(self) weakSelf = self;

	[[self remoteObjectProxy] fetchEntriesForView:item.uniqueIdentifier
						   beforeUniqueIdentifier:uniqueId
									   fetchLimit:fetchLimit
									  limitToDate:limitToDate
							  withCompletionBlock:^(NSArray<TVCLogLineXPC *> *entries) {
								  NSArray *logLines = [weakSelf _logLinesFromXPCObjects:entries forItem:item];

								  completionBlock(logLines);
							  }];
}

- (void)fetchEntriesForItem:(IRCTreeItem *)item
	  afterUniqueIdentifier:(NSString *)uniqueId
				 fetchLimit:(NSUInteger)fetchLimit
				limitToDate:(nullable NSDate *)limitToDate
		withCompletionBlock:(void (^)(NSArray<TVCLogLine *> *entries))completionBlock
{
	[self warmProcessIfNeeded];

	__weak typeof(self) weakSelf = self;

	[[self remoteObjectProxy] fetchEntriesForView:item.uniqueIdentifier
							afterUniqueIdentifier:uniqueId
									   fetchLimit:fetchLimit
									  limitToDate:limitToDate
							  withCompletionBlock:^(NSArray<TVCLogLineXPC *> *entries) {
								  NSArray *logLines = [weakSelf _logLinesFromXPCObjects:entries forItem:item];

								  completionBlock(logLines);
							  }];
}

- (void)fetchEntriesForItem:(IRCTreeItem *)item
	  afterUniqueIdentifier:(NSString *)uniqueIdAfter
	 beforeUniqueIdentifier:(NSString *)uniqueIdBefore
				 fetchLimit:(NSUInteger)fetchLimit
		withCompletionBlock:(void (^)(NSArray<TVCLogLine *> *entries))completionBlock
{
	[self warmProcessIfNeeded];

	__weak typeof(self) weakSelf = self;

	[[self remoteObjectProxy] fetchEntriesForView:item.uniqueIdentifier
							afterUniqueIdentifier:uniqueIdAfter
						   beforeUniqueIdentifier:uniqueIdBefore
									   fetchLimit:fetchLimit
							  withCompletionBlock:^(NSArray<TVCLogLineXPC *> *entries) {
								  NSArray *logLines = [weakSelf _logLinesFromXPCObjects:entries forItem:item];

								  completionBlock(logLines);
							  }];
}

- (BOOL)saveData
{
	if (self.isTerminating) {
		if (self.processLoaded == NO && self.processLoading == NO) {
			return NO;
		}
	}

	if (self.isSaving == NO) {
		self.isSaving = YES;
	} else {
		LogToConsoleDebug("Cancelled save because a save is already saving");

		return YES;
	}

	[self warmProcessIfNeeded];

	__weak TVCLogControllerHistoricLogFile *weakSelf = self;

	void (^saveCompleted)(void) = ^{
		TVCLogControllerHistoricLogFile *strongSelf = weakSelf;

		if (strongSelf == nil) {
			return;
		}

		strongSelf.isSaving = NO;

		if (strongSelf.isTerminating) {
			[strongSelf invalidateProcess];

			[strongSelf invokeTerminationCompletionBlock];
		}
	};

	/* If the service fails while saving, the error handler is the only
	 callback we get. Treat that as the save having ended so that
	 termination is not held up waiting on a reply that never comes. */
	[[self remoteObjectProxyWithErrorHandler:^(NSError *error) {
		saveCompleted();
	}] saveDataWithCompletionBlock:saveCompleted];

	return YES;
}

- (void)forgetItem:(IRCTreeItem *)item
{
	[self _forgetIndexForItem:item];

	[self warmProcessIfNeeded];

	[[self remoteObjectProxy] forgetView:item.uniqueIdentifier];
}

- (void)resetDataForItem:(IRCTreeItem *)item
{
	[self _forgetIndexForItem:item];

	[self warmProcessIfNeeded];

	[[self remoteObjectProxy] resetDataForView:item.uniqueIdentifier];
}

- (void)writeNewEntryWithLogLine:(TVCLogLine *)logLine forItem:(IRCTreeItem *)item
{
	[self indexLogLine:logLine forItem:item];

	[self warmProcessIfNeeded];

	TVCLogLineXPC *newEntry = [logLine xpcObjectForTreeItem:item];

	[[self remoteObjectProxy] writeLogLine:newEntry];
}

#pragma mark -
#pragma mark Private API (Client)

- (void)willDeleteUniqueIdentifiers:(NSArray<NSString *> *)uniqueIdentifiers inView:(NSString *)viewId
{
	IRCTreeItem *item = [worldController() findItemWithId:viewId];

	if (item == nil) {
		return;
	}

	[item.viewController notifyHistoricLogWillDeleteLines:uniqueIdentifiers];
}

@end

NS_ASSUME_NONNULL_END
