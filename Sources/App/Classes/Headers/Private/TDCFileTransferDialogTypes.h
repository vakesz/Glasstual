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

typedef NS_ENUM(NSUInteger, TDCFileTransferDialogTransferStatus) {
	TDCFileTransferDialogTransferStatusComplete,
	TDCFileTransferDialogTransferStatusConnecting,
	TDCFileTransferDialogTransferStatusFatalError,
	TDCFileTransferDialogTransferStatusInitializing,
	TDCFileTransferDialogTransferStatusIsListeningAsReceiver,
	TDCFileTransferDialogTransferStatusIsListeningAsSender,
	TDCFileTransferDialogTransferStatusMappingListeningPort,
	TDCFileTransferDialogTransferStatusReceiving,
	TDCFileTransferDialogTransferStatusRecoverableError,
	TDCFileTransferDialogTransferStatusSending,
	TDCFileTransferDialogTransferStatusStopped,
	TDCFileTransferDialogTransferStatusWaitingForLocalIPAddress,
	TDCFileTransferDialogTransferStatusWaitingForReceiverToAccept,
	TDCFileTransferDialogTransferStatusWaitingForResumeAccept
};

typedef NS_ENUM(NSUInteger, TDCFileTransferDialogSelection) {
	TDCFileTransferDialogSelectionAll = 0,
	TDCFileTransferDialogSelectionSending = 1,
	TDCFileTransferDialogSelectionReceiving = 2
};

typedef void (^TDCFileTransferDialogIPAddressBlock)(NSString *_Nullable address);

NS_ASSUME_NONNULL_END
