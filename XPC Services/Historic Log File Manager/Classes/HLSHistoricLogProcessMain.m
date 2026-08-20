/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
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

#import "TPCPreferencesUserDefaults.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, HLSHistoricLogUniqueIdentifierFetchType) {
	HLSHistoricLogReturnEntriesUniqueIdentifierTypeBefore,
	HLSHistoricLogReturnEntriesUniqueIdentifierTypeAfter
};

@interface HLSHistoricLogProcessMain ()
@property(nonatomic, strong, nullable) NSXPCConnection *serviceConnection;
@property(nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property(nonatomic, strong) NSManagedObjectModel *managedObjectModel;
@property(nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property(nonatomic, copy) NSString *databasePath;		// Path to database file
@property(nonatomic, copy) NSString *databaseDirectory; // Path to database directory
/* contextObjects is mutable. It should only be accessed in a queue. Use the global context's queue. */
@property(nonatomic, strong) NSMutableDictionary<NSString *, HLSHistoricLogViewContext *> *contextObjects;
@property(nonatomic, assign) NSUInteger maximumLineCount;
/* Saves are performed on saveQueue. saveTimer is only read and written on that queue.
 A save waits on each view context's queue and then on the global context's queue.
 It must never be performed while holding either of those queues because a view
 context save waits on the global context's queue in turn. */
@property(nonatomic, strong) dispatch_queue_t saveQueue;
@property(nonatomic, strong, nullable) dispatch_source_t saveTimer;
@property(nonatomic, assign) BOOL connectionIsInvalidated; // Only read and written on saveQueue
@end

@implementation HLSHistoricLogProcessMain

- (instancetype)initWithConnection:(NSXPCConnection *)connection
{
	NSParameterAssert(connection != nil);

	if ((self = [super init])) {
		self.serviceConnection = connection;

		LogToConsoleSetDefaultSubsystemToMainBundle(@"General");

		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	self.contextObjects = [NSMutableDictionary dictionary];

	self.maximumLineCount = 100;

	self.saveQueue = dispatch_queue_create("HLSHistoricLogProcessMain.saveQueue", DISPATCH_QUEUE_SERIAL);
}

/* Returns the filename it stored so that the caller does not have to read the
 defaults back to learn what it is. The previous shape wrote the new name and
 returned the stale nil the caller had already read, which left the first run
 on a fresh database building a path out of nothing. */
- (NSString *)_resetDatabaseFilename
{
	NSString *filename = [NSString stringWithFormat:@"logControllerHistoricLog_%@.sqlite", [NSString stringWithUUID]];

	[RZUserDefaults() setObject:filename forKey:@"TVCLogControllerHistoricLogFileSavePath_v3"];

	return filename;
}

- (NSString *)_databaseSaveFilename
{
	NSString *filename = [RZUserDefaults() objectForKey:@"TVCLogControllerHistoricLogFileSavePath_v3"];

	if (filename == nil) {
		filename = [self _resetDatabaseFilename];
	}

	return filename;
}

- (void)_setDatabasePathInDirectory:(NSString *)databaseDirectory
{
	NSParameterAssert(databaseDirectory != nil);

	self.databaseDirectory = databaseDirectory;

	[self _setDatabasePath];
}

- (void)_setDatabasePath
{
	NSString *filename = [self _databaseSaveFilename];

	NSString *databasePath = [self.databaseDirectory stringByAppendingPathComponent:filename];

	self.databasePath = databasePath;
}

- (void)_resetDatabasePath
{
	[self _resetDatabaseFilename];

	[self _setDatabasePath];
}

- (void)openDatabaseInDirectory:(NSString *)databaseDirectory
			withCompletionBlock:(void(NS_NOESCAPE ^ _Nullable)(BOOL))completionBlock
{
	NSParameterAssert(databaseDirectory != nil);

	[self _setDatabasePathInDirectory:databaseDirectory];

	LogToConsoleInfo("Opening database at path: %{public}@", self.databasePath.standardizedTildePath);

	/* NSXPCConnection can service messages concurrently, so a fetch sent
	 immediately after this one can land while the stack is still being built.
	 -contextForView: takes this same lock, so holding it here makes such a
	 fetch wait for the stack rather than observe it half-constructed. */
	BOOL success = NO;

	@synchronized(self.contextObjects) {
		success = [self _createBaseModel];
	}

	if (completionBlock) {
		completionBlock(success);
	}

	if (success == NO) {
		return;
	}

	dispatch_async(self.saveQueue, ^{
		if (self.connectionIsInvalidated) {
			return;
		}

		[self _rescheduleSave];
	});
}

- (void)setMaximumLineCount:(NSUInteger)maximumLineCount
{
	NSParameterAssert(maximumLineCount > 0);

	if (self->_maximumLineCount != maximumLineCount) {
		self->_maximumLineCount = maximumLineCount;
	}
}

- (NSFetchRequest *)_fetchRequestForView:(NSString *)viewId
							  fetchLimit:(NSUInteger)fetchLimit
							 limitToDate:(nullable NSDate *)limitToDate
							  resultType:(NSFetchRequestResultType)resultType
{

	return [self _fetchRequestForView:viewId
							ascending:YES
						   fetchLimit:fetchLimit
				lowestEntryIdentifier:0
			   highestEntryIdentifier:NSIntegerMax
						  limitToDate:limitToDate
						   resultType:resultType];
}

- (NSFetchRequest *)_fetchRequestForView:(NSString *)viewId
							   ascending:(BOOL)ascending
							  fetchLimit:(NSUInteger)fetchLimit
							 limitToDate:(nullable NSDate *)limitToDate
							  resultType:(NSFetchRequestResultType)resultType
{
	return [self _fetchRequestForView:viewId
							ascending:ascending
						   fetchLimit:fetchLimit
				lowestEntryIdentifier:0
			   highestEntryIdentifier:NSIntegerMax
						  limitToDate:limitToDate
						   resultType:resultType];
}

- (NSFetchRequest *)_fetchRequestForView:(NSString *)viewId
							   ascending:(BOOL)ascending
							  fetchLimit:(NSUInteger)fetchLimit
				   lowestEntryIdentifier:(NSUInteger)lowestEntryIdentifier
				  highestEntryIdentifier:(NSUInteger)highestEntryIdentifier
							 limitToDate:(nullable NSDate *)limitToDate
							  resultType:(NSFetchRequestResultType)resultType
{
	NSParameterAssert(viewId != nil);

	if (limitToDate == nil) {
		limitToDate = [NSDate distantFuture];
	}

	NSDictionary *substitutionVariables = @{
		@"view_id" : viewId,
		@"entry_id_lowest" : @(lowestEntryIdentifier),
		@"entry_id_highest" : @(highestEntryIdentifier),
		@"creation_date" : @([limitToDate timeIntervalSince1970])
	};

	NSFetchRequest *fetchRequest = [self.managedObjectModel fetchRequestFromTemplateWithName:@"GenericConditional"
																	   substitutionVariables:substitutionVariables];

	if (fetchLimit > 0) {
		fetchRequest.fetchLimit = fetchLimit;
	}

	fetchRequest.includesPendingChanges = YES;
	fetchRequest.includesPropertyValues = YES;
	fetchRequest.returnsObjectsAsFaults = NO;

	fetchRequest.resultType = resultType;

	fetchRequest.sortDescriptors = @[ [[NSSortDescriptor alloc] initWithKey:@"entryCreationDate" ascending:ascending] ];

	return fetchRequest;
}

- (void)forgetView:(NSString *)viewId
{
	NSParameterAssert(viewId != nil);

	LogToConsoleDebug("Forgetting view: %{public}@", viewId);

	HLSHistoricLogViewContext *viewContext = [self contextForView:viewId];

	[viewContext performBlockAndWait:^{
		[self cancelResizeInViewContext:viewContext];

		NSFetchRequest *fetchRequest = [self _fetchRequestForView:viewContext.hls_viewId
													   fetchLimit:0
													  limitToDate:nil
													   resultType:NSManagedObjectResultType];

		[self _deleteDataInViewContext:viewContext withFetchRequest:fetchRequest performOnQueue:NO];

		[viewContext reset];
	}];

	NSManagedObjectContext *parentContext = self.managedObjectContext;

	[parentContext performBlockAndWait:^{
		[self.contextObjects removeObjectForKey:viewId];
	}];
}

- (void)resetDataForView:(NSString *)viewId
{
	NSParameterAssert(viewId != nil);

	LogToConsoleDebug("Resetting the contents of view: %{public}@", viewId);

	HLSHistoricLogViewContext *viewContext = [self contextForView:viewId];

	[viewContext performBlockAndWait:^{
		[self cancelResizeInViewContext:viewContext];

		NSFetchRequest *fetchRequest = [self _fetchRequestForView:viewContext.hls_viewId
													   fetchLimit:0
													  limitToDate:nil
													   resultType:NSManagedObjectResultType];

		[self _deleteDataInViewContext:viewContext withFetchRequest:fetchRequest performOnQueue:NO];

		[viewContext reset];
	}];
}

- (void)fetchEntriesForView:(NSString *)viewId
	 beforeUniqueIdentifier:(NSString *)uniqueId
				 fetchLimit:(NSUInteger)fetchLimit
				limitToDate:(nullable NSDate *)limitToDate
		withCompletionBlock:(void(NS_NOESCAPE ^)(NSArray<TVCLogLineXPC *> *entries))completionBlock
{
	return [self fetchEntriesForView:viewId
				withUniqueIdentifier:uniqueId
						   fetchType:HLSHistoricLogReturnEntriesUniqueIdentifierTypeBefore
						  fetchLimit:fetchLimit
						 limitToDate:limitToDate
				 withCompletionBlock:completionBlock];
}

- (void)fetchEntriesForView:(NSString *)viewId
	  afterUniqueIdentifier:(NSString *)uniqueId
				 fetchLimit:(NSUInteger)fetchLimit
				limitToDate:(nullable NSDate *)limitToDate
		withCompletionBlock:(void(NS_NOESCAPE ^)(NSArray<TVCLogLineXPC *> *entries))completionBlock
{
	return [self fetchEntriesForView:viewId
				withUniqueIdentifier:uniqueId
						   fetchType:HLSHistoricLogReturnEntriesUniqueIdentifierTypeAfter
						  fetchLimit:fetchLimit
						 limitToDate:limitToDate
				 withCompletionBlock:completionBlock];
}

/* This method is used to get line matching unique identifier and any that surround it. */
- (void)fetchEntriesForView:(NSString *)viewId
	   withUniqueIdentifier:(NSString *)uniqueId
		   beforeFetchLimit:(NSUInteger)fetchLimitBefore
			afterFetchLimit:(NSUInteger)fetchLimitAfter
				limitToDate:(nullable NSDate *)limitToDate
		withCompletionBlock:(void(NS_NOESCAPE ^)(NSArray<TVCLogLineXPC *> *entries))completionBlock
{
	NSParameterAssert(viewId != nil);
	NSParameterAssert(uniqueId != nil);

	HLSHistoricLogViewContext *viewContext = [self contextForView:viewId];

	if (viewContext == nil) {
		completionBlock(@[]);

		return;
	}

	[viewContext performBlockAndWait:^{
		NSUInteger firstEntryId = [self _identifierInViewContext:viewContext
											 forUniqueIdentifier:uniqueId
												  performOnQueue:NO];

		if (firstEntryId == NSNotFound) {
			completionBlock(@[]);

			return;
		}

		/* Identifiers are unsigned. Subtracting below zero wraps around to a
		 value larger than any entry identifier, which matches nothing. */
		NSUInteger lowestEntryId = ((firstEntryId > fetchLimitBefore) ? (firstEntryId - fetchLimitBefore) : 0);
		NSUInteger highestEntryId = (firstEntryId + fetchLimitAfter);

		NSFetchRequest *fetchRequest = [self _fetchRequestForView:viewContext.hls_viewId
														ascending:YES
													   fetchLimit:0
											lowestEntryIdentifier:lowestEntryId
										   highestEntryIdentifier:highestEntryId
													  limitToDate:limitToDate
													   resultType:NSManagedObjectResultType];

		NSError *fetchRequestError = nil;

		NSArray<NSManagedObject *> *fetchedObjects = [viewContext executeFetchRequest:fetchRequest
																				error:&fetchRequestError];

		if (fetchedObjects == nil) {
			LogToConsoleError("Error occurred fetching objects: %{public}@", fetchRequestError.localizedDescription);

			/* The reply block must always be invoked so the client's
			 pending request is released. An empty result is the answer. */
			completionBlock(@[]);

			return;
		}

		LogToConsoleDebug("%{public}lu results fetched for view %{public}@", fetchedObjects.count, viewId);

		@autoreleasepool {
			NSArray<TVCLogLineXPC *> *fetchedEntries = [self _logLineXPCObjectsFromManagedObjects:fetchedObjects];

			completionBlock([fetchedEntries copy]);
		}
	}];
}

/* This method is used to get a list of lines between two unique identifiers. */
- (void)fetchEntriesForView:(NSString *)viewId
	  afterUniqueIdentifier:(NSString *)uniqueIdAfter
	 beforeUniqueIdentifier:(NSString *)uniqueIdBefore
				 fetchLimit:(NSUInteger)fetchLimit
		withCompletionBlock:(void(NS_NOESCAPE ^)(NSArray<TVCLogLineXPC *> *entries))completionBlock
{
	NSParameterAssert(viewId != nil);
	NSParameterAssert(uniqueIdAfter != nil);
	NSParameterAssert(uniqueIdBefore != nil);

	HLSHistoricLogViewContext *viewContext = [self contextForView:viewId];

	if (viewContext == nil) {
		completionBlock(@[]);

		return;
	}

	[viewContext performBlockAndWait:^{
		NSUInteger firstEntryId = [self _identifierInViewContext:viewContext
											 forUniqueIdentifier:uniqueIdAfter
												  performOnQueue:NO];

		NSUInteger secondEntryId = [self _identifierInViewContext:viewContext
											  forUniqueIdentifier:uniqueIdBefore
												   performOnQueue:NO];

		if (firstEntryId == NSNotFound || secondEntryId == NSNotFound) {
			completionBlock(@[]);

			return;
		}

		/* We are getting the lines in-between these two lines which means we subtract self. */
		NSUInteger lowestEntryId = (firstEntryId + 1);
		NSUInteger highestEntryId = ((secondEntryId > 0) ? (secondEntryId - 1) : 0);

		NSFetchRequest *fetchRequest = [self _fetchRequestForView:viewContext.hls_viewId
														ascending:YES
													   fetchLimit:fetchLimit
											lowestEntryIdentifier:lowestEntryId
										   highestEntryIdentifier:highestEntryId
													  limitToDate:nil
													   resultType:NSManagedObjectResultType];

		NSError *fetchRequestError = nil;

		NSArray<NSManagedObject *> *fetchedObjects = [viewContext executeFetchRequest:fetchRequest
																				error:&fetchRequestError];

		if (fetchedObjects == nil) {
			LogToConsoleError("Error occurred fetching objects: %{public}@", fetchRequestError.localizedDescription);

			/* The reply block must always be invoked so the client's
			 pending request is released. An empty result is the answer. */
			completionBlock(@[]);

			return;
		}

		LogToConsoleDebug("%{public}lu results fetched for view %{public}@", fetchedObjects.count, viewId);

		@autoreleasepool {
			NSArray<TVCLogLineXPC *> *fetchedEntries = [self _logLineXPCObjectsFromManagedObjects:fetchedObjects];

			completionBlock([fetchedEntries copy]);
		}
	}];
}

- (void)fetchEntriesForView:(NSString *)viewId
	   withUniqueIdentifier:(NSString *)uniqueId
				  fetchType:(HLSHistoricLogUniqueIdentifierFetchType)fetchType
				 fetchLimit:(NSUInteger)fetchLimit
				limitToDate:(nullable NSDate *)limitToDate
		withCompletionBlock:(void(NS_NOESCAPE ^)(NSArray<TVCLogLineXPC *> *entries))completionBlock
{
	NSParameterAssert(viewId != nil);
	NSParameterAssert(uniqueId != nil);
	NSParameterAssert(completionBlock != nil);
	NSParameterAssert(fetchLimit > 0);

	HLSHistoricLogViewContext *viewContext = [self contextForView:viewId];

	if (viewContext == nil) {
		completionBlock(@[]);

		return;
	}

	[viewContext performBlockAndWait:^{
		/* Unique identifiers are strings. We find what is the the entry identifier
		 for this string. The entry identifier is an integer. We can then subtract
		 or add the fetch limit to that to get the entries we are interested in. */
		NSUInteger firstEntryId = [self _identifierInViewContext:viewContext
											 forUniqueIdentifier:uniqueId
												  performOnQueue:NO];

		if (firstEntryId == NSNotFound) {
			completionBlock(@[]);

			return;
		}

		NSUInteger lowestEntryId = 0;
		NSUInteger highestEntryId = 0;

		switch (fetchType) {
		case HLSHistoricLogReturnEntriesUniqueIdentifierTypeBefore: {
			/* 1 is subtracted so we can still return fetchLimit
				 while accounting for the fact that firstEntryId is
				 not a value we are interested in. */
			/* Identifiers are unsigned. Clamp at zero instead of wrapping. */
			lowestEntryId = ((firstEntryId > fetchLimit) ? (firstEntryId - fetchLimit) : 0);

			highestEntryId = ((firstEntryId > 0) ? (firstEntryId - 1) : 0);

			break;
		}
		case HLSHistoricLogReturnEntriesUniqueIdentifierTypeAfter: {
			lowestEntryId = (firstEntryId + 1);

			highestEntryId = (firstEntryId + fetchLimit);

			break;
		}
		default: {
			NSAssert(NO, @"Bad 'fetchType' value");

			break;
		}
		}

		NSFetchRequest *fetchRequest = [self _fetchRequestForView:viewContext.hls_viewId
														ascending:YES
													   fetchLimit:fetchLimit
											lowestEntryIdentifier:lowestEntryId
										   highestEntryIdentifier:highestEntryId
													  limitToDate:limitToDate
													   resultType:NSManagedObjectResultType];

		NSError *fetchRequestError = nil;

		NSArray<NSManagedObject *> *fetchedObjects = [viewContext executeFetchRequest:fetchRequest
																				error:&fetchRequestError];

		if (fetchedObjects == nil) {
			LogToConsoleError("Error occurred fetching objects: %{public}@", fetchRequestError.localizedDescription);

			/* The reply block must always be invoked so the client's
			 pending request is released. An empty result is the answer. */
			completionBlock(@[]);

			return;
		}

		LogToConsoleDebug("%{public}lu results fetched for view %{public}@", fetchedObjects.count, viewId);

		@autoreleasepool {
			NSArray<TVCLogLineXPC *> *fetchedEntries = [self _logLineXPCObjectsFromManagedObjects:fetchedObjects];

			completionBlock([fetchedEntries copy]);
		}
	}];
}

- (void)fetchEntriesForView:(NSString *)viewId
				  ascending:(BOOL)ascending
				 fetchLimit:(NSUInteger)fetchLimit
				limitToDate:(nullable NSDate *)limitToDate
		withCompletionBlock:(void(NS_NOESCAPE ^)(NSArray<TVCLogLineXPC *> *entries))completionBlock
{
	NSParameterAssert(viewId != nil);
	NSParameterAssert(completionBlock != nil);

	HLSHistoricLogViewContext *viewContext = [self contextForView:viewId];

	if (viewContext == nil) {
		completionBlock(@[]);

		return;
	}

	[viewContext performBlockAndWait:^{
		NSFetchRequest *fetchRequest = [self _fetchRequestForView:viewContext.hls_viewId
														ascending:ascending
													   fetchLimit:fetchLimit
													  limitToDate:limitToDate
													   resultType:NSManagedObjectResultType];

		NSError *fetchRequestError = nil;

		NSArray<NSManagedObject *> *fetchedObjects = [viewContext executeFetchRequest:fetchRequest
																				error:&fetchRequestError];

		if (fetchedObjects == nil) {
			LogToConsoleError("Error occurred fetching objects: %{public}@", fetchRequestError.localizedDescription);

			/* The reply block must always be invoked so the client's
			 pending request is released. An empty result is the answer. */
			completionBlock(@[]);

			return;
		}

		LogToConsoleDebug("%{public}lu results fetched for view %{public}@", fetchedObjects.count, viewId);

		@autoreleasepool {
			NSArray<TVCLogLineXPC *> *fetchedEntries = [self _logLineXPCObjectsFromManagedObjects:fetchedObjects];

			completionBlock([fetchedEntries copy]);
		}
	}];
}

- (NSArray<TVCLogLineXPC *> *)_logLineXPCObjectsFromManagedObjects:(NSArray<NSManagedObject *> *)managedObjects
{
	NSParameterAssert(managedObjects != nil);

	NSMutableArray<TVCLogLineXPC *> *xpcObjects = [NSMutableArray arrayWithCapacity:managedObjects.count];

	for (NSManagedObject *managedObject in managedObjects) {
		TVCLogLineXPC *xpcObject = [[TVCLogLineXPC alloc] initWithManagedObject:managedObject];

		[xpcObjects addObject:xpcObject];
	}

	return [xpcObjects copy];
}

- (void)writeLogLine:(TVCLogLineXPC *)logLine
{
	NSParameterAssert(logLine != nil);

	HLSHistoricLogViewContext *viewContext = [self contextForView:logLine.viewIdentifier];

	[viewContext performBlockAndWait:^{
		NSEntityDescription *entity = [NSEntityDescription entityForName:@"LogLine2"
												  inManagedObjectContext:viewContext];

		NSManagedObject *newEntry = [[NSManagedObject alloc] initWithEntity:entity
											 insertIntoManagedObjectContext:viewContext];

		NSUInteger newestIdentifier = [self _incrementNewestIdentifierInViewContext:viewContext];

		[newEntry setValue:@(newestIdentifier) forKey:@"entryIdentifier"];

		[newEntry setValue:@([[NSDate date] timeIntervalSince1970]) forKey:@"entryCreationDate"];

		[newEntry setValue:logLine.viewIdentifier forKey:@"logLineViewIdentifier"];

		[newEntry setValue:logLine.data forKey:@"logLineData"];

		[newEntry setValue:logLine.uniqueIdentifier forKey:@"logLineUniqueIdentifier"];

		[newEntry setValue:@(logLine.sessionIdentifier) forKey:@"sessionIdentifier"];

		[self scheduleResizeInViewContext:viewContext];
	}];
}

- (BOOL)_createBaseModel
{
	return [self _createBaseModelWithRecursion:0];
}

- (BOOL)_createBaseModelWithRecursion:(NSUInteger)recursionDepth
{
	NSURL *modelPath = [[NSBundle mainBundle] URLForResource:@"HistoricLogFileStorageModel" withExtension:@"momd"];

	NSManagedObjectModel *managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelPath];

	NSPersistentStoreCoordinator *persistentStoreCoordinator =
		[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];

	NSDictionary *pragmaOptions = @{@"synchronous" : @"NORMAL", @"journal_mode" : @"WAL"};

	NSDictionary *persistentStoreOptions = @{
		NSMigratePersistentStoresAutomaticallyOption : @(YES),
		NSInferMappingModelAutomaticallyOption : @(YES),
		NSSQLitePragmasOption : pragmaOptions
	};

	NSURL *persistentStorePath = [NSURL fileURLWithPath:self.databasePath];

	NSError *addPersistentStoreError = nil;

	NSPersistentStore *persistentStore =
		[persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType
												 configuration:nil
														   URL:persistentStorePath
													   options:persistentStoreOptions
														 error:&addPersistentStoreError];

	if (persistentStore == nil) {
		LogToConsoleError("Error Creating Persistent Store: %{public}@", addPersistentStoreError.localizedDescription);

		if (recursionDepth == 0) {
			LogToConsoleInfo("Attempting to create a new persistent store");

			/* If we failed to load our store, we create a brand new one at a new path
			 incase the old one is corrupted. */
			[self _resetDatabasePath]; // Destroy any data that may exist

			return [self _createBaseModelWithRecursion:1];
		}

		return NO;
	} else {
		NSManagedObjectContext *managedObjectContext =
			[[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];

		managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator;

		managedObjectContext.retainsRegisteredObjects = YES;

		managedObjectContext.undoManager = nil;

		self.managedObjectContext = managedObjectContext;
		self.managedObjectModel = managedObjectModel;

		self.persistentStoreCoordinator = persistentStoreCoordinator;

		return YES;
	}
}

/* Only call on saveQueue. */
- (void)_cancelScheduledSave
{
	dispatch_source_t saveTimer = self.saveTimer;

	if (saveTimer == nil) {
		return;
	}

	XRCancelScheduledBlock(saveTimer);

	self.saveTimer = nil;
}

/* Only call on saveQueue. */
- (void)_rescheduleSave
{
	[self _cancelScheduledSave];

	static NSTimeInterval saveTimerInterval = (60 * 2); // 2 minutes

	dispatch_source_t saveTimer = XRScheduleBlockOnQueue(
		dispatch_get_main_queue(),
		^{
			[self saveDataWithCompletionBlock:nil];
		},
		saveTimerInterval,
		YES);

	XRResumeScheduledBlock(saveTimer);

	self.saveTimer = saveTimer;
}

- (void)_quickSaveContext:(NSManagedObjectContext *)context
{
	NSParameterAssert(context != nil);

	if ([context hasChanges] == NO) {
		return;
	}

	NSError *saveError = nil;

	if ([context save:&saveError] == NO) {
		LogToConsoleError("Failed to perform save: %{public}@", saveError.localizedDescription);
	}

	[context reset];
}

/* Only call on saveQueue.
 Each view context is a child of the global context and owns a private
 queue of its own, so each one is saved on that queue which pushes its
 changes into the global context. The global context is then saved to
 the store. Saves are serialized by saveQueue; there is no need for a
 flag to guard against overlapping saves. */
- (void)_saveAllContextsCancellingResize:(BOOL)cancelResize
{
	NSManagedObjectContext *context = self.managedObjectContext;

	if (context == nil) {
		return;
	}

	LogToConsoleDebug("Performing save");

	/* contextObjects is mutated on the global context's queue. */
	__block NSArray<HLSHistoricLogViewContext *> *viewContexts = nil;

	[context performBlockAndWait:^{
		viewContexts = self.contextObjects.allValues;
	}];

	for (HLSHistoricLogViewContext *viewContext in viewContexts) {
		[viewContext performBlockAndWait:^{
			if (cancelResize) {
				[self cancelResizeInViewContext:viewContext];
			}

			[self _quickSaveContext:viewContext];
		}];
	}

	[context performBlockAndWait:^{
		[self _quickSaveContext:context];
	}];
}

- (void)saveDataWithCompletionBlock:(void (^_Nullable)(void))completionBlock
{
	dispatch_async(self.saveQueue, ^{
		/* A timer that fired just before the connection was invalidated
		 must not schedule another one. The repeating timer retains this
		 object, so that would keep it alive for the life of the process. */
		if (self.connectionIsInvalidated == NO) {
			[self _rescheduleSave];
		}

		[self _saveAllContextsCancellingResize:NO];

		if (completionBlock) {
			completionBlock();
		}
	});
}

#pragma mark -
#pragma mark Connection Lifetime

/* Called when the connection that owns this object is invalidated.
 Performs a final save, stops timers, and drops the reference to the
 connection so that the connection and this object can deallocate. */
- (void)connectionInvalidated
{
	LogToConsoleDebug("Connection invalidated");

	dispatch_sync(self.saveQueue, ^{
		self.connectionIsInvalidated = YES;

		[self _cancelScheduledSave];

		[self _saveAllContextsCancellingResize:YES];
	});

	self.serviceConnection = nil;
}

#pragma mark -
#pragma mark View Resize Logic

- (void)cancelResizeInViewContext:(HLSHistoricLogViewContext *)viewContext
{
	NSParameterAssert(viewContext != nil);

	if (viewContext.hls_resizeTimer == nil) {
		return;
	}

	XRCancelScheduledBlock(viewContext.hls_resizeTimer);

	viewContext.hls_resizeTimer = nil;
}

- (void)scheduleResizeInViewContext:(HLSHistoricLogViewContext *)viewContext
{
	NSParameterAssert(viewContext != nil);

	if (viewContext.hls_resizeTimer != nil) {
		return;
	}

	if (viewContext.hls_totalLineCount < self.maximumLineCount) {
		return;
	}

	NSString *viewId = viewContext.hls_viewId;

	NSTimeInterval resizeTimerInterval = (NSTimeInterval)arc4random_uniform(60 * 30); // Somewhere in 30 minutes

	dispatch_source_t resizeTimer = XRScheduleBlockOnQueue(
		dispatch_get_main_queue(),
		^{
			[self resizeView:viewId];
		},
		resizeTimerInterval,
		NO);

	XRResumeScheduledBlock(resizeTimer);

	viewContext.hls_resizeTimer = resizeTimer;

	LogToConsoleDebug("Scheduled to resize %{public}@ in %{public}f seconds", viewId, resizeTimerInterval);
}

- (void)resizeView:(NSString *)viewId
{
	NSParameterAssert(viewId != nil);

	HLSHistoricLogViewContext *viewContext = [self contextForView:viewId];

	[viewContext performBlock:^{
		[self _resizeViewContext:viewContext];
	}];
}

- (void)_resizeViewContext:(HLSHistoricLogViewContext *)viewContext
{
	NSParameterAssert(viewContext != nil);

	LogToConsoleDebug("Resizing view %{public}@", viewContext.hls_viewId);

	viewContext.hls_resizeTimer = nil;

	NSString *viewId = viewContext.hls_viewId;

	NSUInteger newestIdentifier = viewContext.hls_newestIdentifier;
	NSUInteger maximumLineCount = self.maximumLineCount;

	NSUInteger lowestIdentifier = ((newestIdentifier > maximumLineCount) ? (newestIdentifier - maximumLineCount) : 0);

	NSDictionary *substitutionVariables = @{@"view_id" : viewId, @"entry_id_lowest" : @(lowestIdentifier)};

	NSFetchRequest *fetchRequest = [self.managedObjectModel fetchRequestFromTemplateWithName:@"Truncate"
																	   substitutionVariables:substitutionVariables];

	fetchRequest.includesPendingChanges = YES;
	fetchRequest.includesPropertyValues = YES;
	fetchRequest.returnsObjectsAsFaults = NO;

	NSUInteger rowsDeleted = [self _deleteDataInViewContext:viewContext
										   withFetchRequest:fetchRequest
											 performOnQueue:NO];

	viewContext.hls_totalLineCount -= rowsDeleted;
}

#pragma mark -
#pragma mark Batch Delete Logic

- (NSUInteger)_deleteDataInViewContext:(HLSHistoricLogViewContext *)viewContext
					  withFetchRequest:(NSFetchRequest *)fetchRequest
						performOnQueue:(BOOL)performOnQueue
{
	NSParameterAssert(viewContext != nil);
	NSParameterAssert(fetchRequest != nil);

	__block NSUInteger rowsDeleted = 0;

	dispatch_block_t blockToPerform = ^{
		rowsDeleted = [self __deleteDataForFetchRequestUsingBatch:fetchRequest inViewContext:viewContext];
	};

	if (performOnQueue) {
		[viewContext performBlockAndWait:blockToPerform];
	} else {
		blockToPerform();
	}

	LogToConsoleDebug("Deleted %{public}lu rows in %{public}@", rowsDeleted, viewContext.hls_viewId);

	return rowsDeleted;
}

/* Only call on the view context's queue.

 A batch delete runs against the store directly. It does not see rows that
 are still pending in memory, and the contexts do not see what it removed.
 Both are handled here: pending rows are pushed down to the store before
 the delete, the unique identifiers of the rows that are about to go are
 collected so the client can be told, and the deleted object identifiers
 are merged back into the view context and its parent afterwards. */
- (NSUInteger)__deleteDataForFetchRequestUsingBatch:(NSFetchRequest *)fetchRequest
									  inViewContext:(HLSHistoricLogViewContext *)viewContext
{
	NSParameterAssert(fetchRequest != nil);
	NSParameterAssert(viewContext != nil);

	NSManagedObjectContext *parentContext = viewContext.parentContext;

	if (parentContext == nil) {
		return 0;
	}

	/* Flush pending changes so the store holds everything the delete should cover. */
	[self _quickSaveContext:viewContext];

	[parentContext performBlockAndWait:^{
		[self _quickSaveContext:parentContext];
	}];

	/* Collect the unique identifiers of the rows that are about to be deleted. */
	NSFetchRequest *identifierRequest = [fetchRequest copy];

	identifierRequest.resultType = NSDictionaryResultType;
	identifierRequest.propertiesToFetch = @[ @"logLineUniqueIdentifier" ];
	identifierRequest.includesPendingChanges = NO;
	identifierRequest.returnsObjectsAsFaults = NO;
	identifierRequest.sortDescriptors = nil;

	NSError *identifierRequestError = nil;

	NSArray<NSDictionary<NSString *, id> *> *identifierRows = [viewContext executeFetchRequest:identifierRequest
																						 error:&identifierRequestError];

	if (identifierRows == nil) {
		LogToConsoleError("Error occurred fetching objects: %{public}@", identifierRequestError.localizedDescription);

		return 0;
	}

	if (identifierRows.count == 0) {
		return 0;
	}

	NSMutableArray<NSString *> *uniqueIdentifiers = [NSMutableArray arrayWithCapacity:identifierRows.count];

	for (NSDictionary<NSString *, id> *row in identifierRows) {
		NSString *uniqueIdentifier = row[@"logLineUniqueIdentifier"];

		if (uniqueIdentifier) {
			[uniqueIdentifiers addObject:uniqueIdentifier];
		}
	}

	/* Perform the delete against the store. */
	NSFetchRequest *deleteRequest = [fetchRequest copy];

	deleteRequest.resultType = NSManagedObjectResultType;
	deleteRequest.includesPendingChanges = NO;
	deleteRequest.sortDescriptors = nil;

	NSBatchDeleteRequest *batchDeleteRequest = [[NSBatchDeleteRequest alloc] initWithFetchRequest:deleteRequest];

	batchDeleteRequest.resultType = NSBatchDeleteResultTypeObjectIDs;

	__block NSBatchDeleteResult *batchDeleteResult = nil;
	__block NSError *batchDeleteError = nil;

	[parentContext performBlockAndWait:^{
		batchDeleteResult = [parentContext executeRequest:batchDeleteRequest error:&batchDeleteError];
	}];

	if (batchDeleteResult == nil) {
		LogToConsoleError("Failed to perform batch delete: %{public}@", batchDeleteError.localizedDescription);

		return 0;
	}

	NSArray<NSManagedObjectID *> *rowsDeleted = batchDeleteResult.result;

	NSUInteger rowsDeletedCount = rowsDeleted.count;

	if (rowsDeletedCount == 0) {
		return 0;
	}

	/* Bring the contexts in line with the store. */
	[NSManagedObjectContext mergeChangesFromRemoteContextSave:@{NSDeletedObjectsKey : rowsDeleted}
												 intoContexts:@[ parentContext, viewContext ]];

	[self __notifyClientOfDeletedUniqueIdentifiers:[uniqueIdentifiers copy] inViewContext:viewContext];

	return rowsDeletedCount;
}

/* Notify XPC client of intent to delete these unique identifiers. */
/* Deletes can happen based on a timer, without the client asking for it,
 which means we need a way to inform it of the delete. */
- (void)__notifyClientOfDeletedUniqueIdentifiers:(NSArray<NSString *> *)uniqueIdentifiers
								   inViewContext:(HLSHistoricLogViewContext *)viewContext
{
	NSParameterAssert(uniqueIdentifiers != nil);
	NSParameterAssert(viewContext != nil);

	[[self remoteObjectProxy] willDeleteUniqueIdentifiers:uniqueIdentifiers inView:viewContext.hls_viewId];
}

#pragma mark -
#pragma mark Identifier Cache Management

- (nullable HLSHistoricLogViewContext *)contextForView:(NSString *)viewId
{
	NSParameterAssert(viewId != nil);

	@synchronized(self.contextObjects) {
		/* Returned cached object or create new */
		HLSHistoricLogViewContext *viewContext = self.contextObjects[viewId];

		if (viewContext != nil) {
			return viewContext;
		}

		NSManagedObjectContext *parentObjectContext = self.managedObjectContext;

		/* -setParentContext: raises NSInvalidArgumentException ("Parent
		 NSManagedObjectContext must not be nil.") when the stack is absent,
		 which terminates this service and takes the client's history with it.
		 The stack is absent when the database has not been opened yet, or
		 when opening it failed. Refuse to vend a context instead. */
		if (parentObjectContext == nil) {
			LogToConsoleError("Requested context for %{public}@ before the database was opened", viewId);

			return nil;
		}

		viewContext = [[HLSHistoricLogViewContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];

		/* Properties specific to NSManagedObjectContext */
		viewContext.parentContext = parentObjectContext;

		viewContext.retainsRegisteredObjects = YES;

		viewContext.undoManager = nil;

		/* Properties specific to HLSHistoricLogViewContext */
		viewContext.hls_viewId = viewId;

		viewContext.hls_totalLineCount = [self _lineCountInViewContextFromDatabase:viewContext performOnQueue:YES];

		viewContext.hls_newestIdentifier = [self _newestIdentifierInViewContextFromDatabase:viewContext
																			 performOnQueue:YES];

		/* Log information for debugging */
		LogToConsoleDebug("Context created for %{public}@ - Line count: %{public}lu, Newest identifier: %{public}lu",
						  viewContext.hls_viewId,
						  viewContext.hls_totalLineCount,
						  viewContext.hls_newestIdentifier);

		/* Cache new object and return it */
		[parentObjectContext performBlockAndWait:^{
			self.contextObjects[viewId] = viewContext;
		}];

		return viewContext;
	}
}

- (NSUInteger)_incrementNewestIdentifierInViewContext:(HLSHistoricLogViewContext *)viewContext
{
	NSParameterAssert(viewContext != nil);

	viewContext.hls_totalLineCount += 1;

	viewContext.hls_newestIdentifier += 1;

	return viewContext.hls_newestIdentifier;
}

- (NSUInteger)_newestIdentifierInViewContext:(HLSHistoricLogViewContext *)viewContext
{
	NSParameterAssert(viewContext != nil);

	return viewContext.hls_newestIdentifier;
}

- (NSUInteger)_newestIdentifierInViewContextFromDatabase:(HLSHistoricLogViewContext *)viewContext
										  performOnQueue:(BOOL)performOnQueue
{
	NSParameterAssert(viewContext != nil);

	__block NSUInteger newestIdentifier = 0;

	dispatch_block_t blockToPerform = ^{
		NSFetchRequest *fetchRequest = [self _fetchRequestForView:viewContext.hls_viewId
														ascending:NO
													   fetchLimit:1
													  limitToDate:nil
													   resultType:NSManagedObjectResultType];

		NSError *fetchRequestError = nil;

		NSArray<NSManagedObject *> *fetchedObjects = [viewContext executeFetchRequest:fetchRequest
																				error:&fetchRequestError];

		if (fetchedObjects == nil) {
			NSAssert1(NO, @"Error occurred fetching objects: %@", fetchRequestError.localizedDescription);
		}

		NSManagedObject *fetchedObject = fetchedObjects.firstObject;

		if (fetchedObject == nil) {
			return;
		}

		NSNumber *newestIdentifierObject = [fetchedObject valueForKey:@"entryIdentifier"];

		newestIdentifier = newestIdentifierObject.unsignedIntegerValue;
	};

	if (performOnQueue) {
		[viewContext performBlockAndWait:blockToPerform];
	} else {
		blockToPerform();
	}

	return newestIdentifier;
}

- (NSUInteger)_lineCountInViewContextFromDatabase:(HLSHistoricLogViewContext *)viewContext
								   performOnQueue:(BOOL)performOnQueue
{
	NSParameterAssert(viewContext != nil);

	__block NSUInteger lineCount = 0;

	dispatch_block_t blockToPerform = ^{
		NSFetchRequest *fetchRequest = [self _fetchRequestForView:viewContext.hls_viewId
													   fetchLimit:0
													  limitToDate:nil
													   resultType:NSCountResultType];

		NSError *fetchRequestError = nil;

		lineCount = [viewContext countForFetchRequest:fetchRequest error:&fetchRequestError];

		if (lineCount == NSNotFound) {
			NSAssert1(NO, @"Error occurred fetching objects: %@", fetchRequestError.localizedDescription);
		}
	};

	if (performOnQueue) {
		[viewContext performBlockAndWait:blockToPerform];
	} else {
		blockToPerform();
	}

	return lineCount;
}

/* Given a logLineUniqueIdentifier, figure out which entryIdentifier is associated with it. */
- (NSUInteger)_identifierInViewContext:(HLSHistoricLogViewContext *)viewContext
				   forUniqueIdentifier:(NSString *)uniqueIdentifier
						performOnQueue:(BOOL)performOnQueue
{
	NSUInteger identifier = [self _identifierInViewContextFromDatabase:viewContext
												   forUniqueIdentifier:uniqueIdentifier
														performOnQueue:performOnQueue];

	return identifier;
}

- (NSUInteger)_identifierInViewContextFromDatabase:(HLSHistoricLogViewContext *)viewContext
							   forUniqueIdentifier:(NSString *)uniqueIdentifier
									performOnQueue:(BOOL)performOnQueue
{
	NSParameterAssert(viewContext != nil);
	NSParameterAssert(uniqueIdentifier != nil);

	__block NSUInteger identifier = NSNotFound;

	dispatch_block_t blockToPerform = ^{
		NSString *viewId = viewContext.hls_viewId;

		NSDictionary *substitutionVariables = @{@"view_id" : viewId, @"unique_id" : uniqueIdentifier};

		NSFetchRequest *fetchRequest = [self.managedObjectModel fetchRequestFromTemplateWithName:@"UniqueIdToEntryId"
																		   substitutionVariables:substitutionVariables];

		fetchRequest.includesPendingChanges = YES;
		fetchRequest.includesPropertyValues = YES;
		fetchRequest.returnsObjectsAsFaults = NO;

		NSError *fetchRequestError = nil;

		NSArray<NSManagedObject *> *fetchedObjects = [viewContext executeFetchRequest:fetchRequest
																				error:&fetchRequestError];

		if (fetchedObjects == nil) {
			NSAssert1(NO, @"Error occurred fetching objects: %@", fetchRequestError.localizedDescription);
		}

		NSManagedObject *fetchedObject = fetchedObjects.firstObject;

		if (fetchedObject == nil) {
			return;
		}

		NSNumber *identifierObject = [fetchedObject valueForKey:@"entryIdentifier"];

		identifier = identifierObject.unsignedIntegerValue;
	};

	if (performOnQueue) {
		[viewContext performBlockAndWait:blockToPerform];
	} else {
		blockToPerform();
	}

	return identifier;
}

#pragma mark -
#pragma mark XPC Connection

- (nullable id<HLSHistoricLogClientProtocol>)remoteObjectProxy
{
	return self.serviceConnection.remoteObjectProxy;
}

@end

NS_ASSUME_NONNULL_END
