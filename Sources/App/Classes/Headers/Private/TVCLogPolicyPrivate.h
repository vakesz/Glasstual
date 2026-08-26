/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

@class TVCLogView;

/* The element the style last pointed at before asking for a context
 menu or reporting a double click: a link, a nickname or a channel name.
 The style sends these in a separate message ahead of the action, so
 they are held per view (see -[TVCLogView contextMenuTarget]) and taken
 by the policy at the moment the menu is built. Holding them on the
 shared policy let two views interleave their messages. */
@interface TVCLogPolicyTarget : NSObject
@property(nonatomic, copy, nullable) NSString *anchorURL;
@property(nonatomic, copy, nullable) NSString *channelName;
@property(nonatomic, copy, nullable) NSString *nickname;

/* The line under the pointer, reported by the style ahead of the menu.
 A line with a message identifier can be replied to and reacted to. */
@property(nonatomic, copy, nullable) NSString *lineNumber;
@property(nonatomic, copy, nullable) NSString *lineMessageIdentifier;
@property(nonatomic, copy, nullable) NSString *lineType;
@property(nonatomic, copy, nullable) NSString *lineNickname;
@property(nonatomic, copy, nullable) NSString *lineExcerpt;
@end

/* One instance is shared by every web view. It holds no per-view state. */
@interface TVCLogPolicy : NSObject
- (void)displayContextMenuInWebView:(TVCLogView *)webView;

- (void)channelNameDoubleClickedInWebView:(TVCLogView *)webView;
- (void)nicknameDoubleClickedInWebView:(TVCLogView *)webView;
- (void)topicBarDoubleClicked;

- (void)webView2:(WKWebView *)webView
                              logView:(TVCLogView *)logView
    didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
                    completionHandler:
                        (void (^)(
                            NSURLSessionAuthChallengeDisposition disposition,
                            NSURLCredential *credential))completionHandler;
- (void)webView2:(WKWebView *)webView
                            logView:(TVCLogView *)logView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:
                        (void (^)(WKNavigationActionPolicy))decisionHandler;
- (NSMenu *)webView2:(WKWebView *)webView
                       logView:(TVCLogView *)logView
    contextMenuWithDefaultMenu:(NSMenu *)defaultMenu;
@end

NS_ASSUME_NONNULL_END
