/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

NS_ASSUME_NONNULL_BEGIN

@protocol TLOSpeechSynthesizerEngineDelegate <NSObject>
- (void)speechSynthesizerEngineDidCompleteUtterance;
@end

@protocol TLOSpeechSynthesizerEngine <NSObject>
@property(nonatomic, weak, nullable) id<TLOSpeechSynthesizerEngineDelegate>
    delegate;
@property(nonatomic, readonly, getter=isSpeaking) BOOL speaking;

- (void)speakText:(NSString *)text;
- (void)stopSpeakingImmediately;
@end

@interface TLOAVSpeechSynthesizerEngine : NSObject <TLOSpeechSynthesizerEngine>
@end

NS_ASSUME_NONNULL_END
