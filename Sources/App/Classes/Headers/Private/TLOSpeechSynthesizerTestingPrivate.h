/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import "TLOSpeechSynthesizerEnginePrivate.h"
#import "TLOSpeechSynthesizerPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLOSpeechSynthesizer ()
- (instancetype)initWithEngine:(id<TLOSpeechSynthesizerEngine>)engine;
@property(nonatomic, readonly) NSUInteger pendingItemCount;
@end

NS_ASSUME_NONNULL_END
