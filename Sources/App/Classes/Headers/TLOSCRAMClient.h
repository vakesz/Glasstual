/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

NS_ASSUME_NONNULL_BEGIN

/* Implemented in TLOSCRAMClient.swift */

typedef NS_ENUM(NSInteger, TLOSCRAMClientErrorCode) {
  TLOSCRAMClientErrorCodeInvalidState = 1,
  TLOSCRAMClientErrorCodeMalformedServerMessage,
  TLOSCRAMClientErrorCodeNonceMismatch,
  TLOSCRAMClientErrorCodeIterationCountTooLow,
  TLOSCRAMClientErrorCodeServerRejected,
  TLOSCRAMClientErrorCodeServerSignatureMismatch,
  TLOSCRAMClientErrorCodeKeyDerivationFailed,
};

typedef NS_ENUM(NSInteger, TLOSCRAMClientState) {
  TLOSCRAMClientStateInitial = 0,
  TLOSCRAMClientStateSentClientFirst,
  TLOSCRAMClientStateSentClientFinal,
  TLOSCRAMClientStateAuthenticated,
  TLOSCRAMClientStateFailed,
};

/**
 * Client side of SASL SCRAM-SHA-256 (RFC 5802, RFC 7677).
 *
 * Send -clientFirstMessage, hand the server's reply to
 * -clientFinalMessageForServerFirstMessage:error: and send the result,
 * then check the server's last message with -verifyServerFinalMessage:error:.
 * An object runs one exchange. Errors are in the domain named by
 * +errorDomain with a TLOSCRAMClientErrorCode.
 */
@interface TLOSCRAMClient : NSObject
@property(class, readonly, copy) NSString *errorDomain;
@property(class, readonly, copy) NSString *mechanismName; // "SCRAM-SHA-256"

@property(readonly) TLOSCRAMClientState state;

- (instancetype)initWithUsername:(NSString *)username
                        password:(NSString *)password;
- (instancetype)initWithUsername:(NSString *)username
                        password:(NSString *)password
                     clientNonce:(NSString *)clientNonce
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@property(readonly, copy) NSString *clientFirstMessage;

- (nullable NSString *)
    clientFinalMessageForServerFirstMessage:(NSString *)serverFirstMessage
                                      error:(NSError **)error;

- (BOOL)verifyServerFinalMessage:(NSString *)serverFinalMessage
                           error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
