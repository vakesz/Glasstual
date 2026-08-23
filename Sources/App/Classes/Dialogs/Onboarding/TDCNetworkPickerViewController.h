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

NS_ASSUME_NONNULL_BEGIN

@class IRCClientConfigMutable, IRCNetwork, IRCNetworkList;
@class TDCNetworkPickerViewController;

@protocol TDCNetworkPickerViewControllerDelegate <NSObject>
@optional
/* Sent when the selected network or any of the editable fields change. */
- (void)networkPickerSelectionDidChange:(TDCNetworkPickerViewController *)sender;

/* Sent when the user double-clicks a network or presses Return in the list. */
- (void)networkPickerDidConfirmSelection:(TDCNetworkPickerViewController *)sender;
@end

/* A searchable list of well known networks with a detail area for the
 selected network (server, port, TLS, and an account group when the network
 has account services). The last row, "Custom server…", reveals the same
 detail area empty so that any server can be entered.

 The picker is used by the onboarding window and by the Server Properties
 sheet. It produces an IRCClientConfig through -clientConfig. */
@interface TDCNetworkPickerViewController : NSViewController
@property(nonatomic, weak, nullable) id<TDCNetworkPickerViewControllerDelegate> delegate;

@property(readonly, strong) IRCNetworkList *networkList;

/* Used as the default account name. */
@property(nonatomic, copy, nullable) NSString *defaultNickname;

/* The network selected in the list, or nil for no selection and for the
 custom server row. */
@property(readonly, nullable) IRCNetwork *selectedNetwork;

@property(readonly) BOOL customServerSelected;

/* YES when a network or the custom server row is selected. */
@property(readonly) BOOL hasSelection;

/* Values of the editable fields in the detail area. */
@property(readonly, copy) NSString *serverAddress;
@property(readonly) uint16_t serverPort;
@property(readonly) BOOL prefersSecuredConnection;
@property(readonly, copy) NSString *accountName;
@property(readonly, copy) NSString *accountPassword;
@property(readonly) BOOL usesSASL;

/* Channels the selected network suggests joining. Empty for custom servers. */
@property(readonly, copy) NSArray<NSString *> *suggestedChannels;

- (void)selectNetwork:(IRCNetwork *)network;

/* Selects the network matching the address when one exists. Otherwise the
 custom server row is selected and the fields are filled with the values. */
- (void)selectServerAddress:(NSString *)serverAddress port:(uint16_t)port secured:(BOOL)secured;

- (void)clearSelection;

/* Returns NO and sets errorDescription when the entered values can not
 produce a connection. */
- (BOOL)validateWithError:(NSString *_Nullable *_Nullable)errorDescription;

/* A new configuration for the current selection. nil when there is no
 selection or the values do not validate. The nickname is left at its
 default; callers set identity fields themselves. */
- (nullable IRCClientConfigMutable *)clientConfig;

/* Moves keyboard focus to the search field. */
- (void)focusSearchField;
@end

NS_ASSUME_NONNULL_END
