/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

#import "TXMasterController.h"
#import "TXGlobalModels.h"
#import "TLOLocalization.h"
#import "TPCPreferencesLocal.h"
#import "IRCClient.h"
#import "IRCChannel.h"
#import "IRCWorld.h"
#import "TVCDockIconPrivate.h"

NS_ASSUME_NONNULL_BEGIN

/* The dock tile shows up to two badges: a red one for unread messages
 and a green one for highlights. NSDockTile.badgeLabel only offers the
 red one, so when a distinction is needed the tile content is drawn by
 this view on top of the application icon. */
@interface TVCDockIconBadgeView : NSView
@property(nonatomic, assign) NSUInteger highlightCount;
@property(nonatomic, assign) NSUInteger messageCount;
@end

@interface TVCDockIcon ()
+ (NSString *)badgeStringForCount:(NSUInteger)count;
@end

@implementation TVCDockIcon

static NSInteger _cachedHighlightCount = (-1);
static NSInteger _cachedMessageCount = (-1);

+ (void)updateDockIcon
{
	if ([TPCPreferences displayDockBadge] == NO) {
		return;
	}

	NSUInteger highlightCount = 0;
	NSUInteger messageCount = 0;

	for (IRCClient *u in worldController().clientList) {
		for (IRCChannel *c in u.channelList) {
			if (c.config.pushNotifications) {
				messageCount += c.dockUnreadCount;
			}

			highlightCount += c.nicknameHighlightCount;
		}
	}

	if (messageCount == 0 && highlightCount == 0) {
		[self drawWithoutCount];
	} else {
		[self drawWithHighlightCount:highlightCount messageCount:messageCount];
	}
}

+ (void)resetCachedCount
{
	_cachedMessageCount = (-1);
	_cachedHighlightCount = (-1);
}

+ (void)drawWithoutCount
{
	if (_cachedHighlightCount == 0 && _cachedMessageCount == 0) {
		return;
	}

	_cachedMessageCount = 0;
	_cachedHighlightCount = 0;

	NSDockTile *dockTile = NSApp.dockTile;

	dockTile.badgeLabel = nil;
	dockTile.contentView = nil;

	[dockTile display];
}

+ (void)drawWithHighlightCount:(NSUInteger)highlightCount messageCount:(NSUInteger)messageCount
{
	if (_cachedHighlightCount == (NSInteger)highlightCount && _cachedMessageCount == (NSInteger)messageCount) {
		return;
	}

	_cachedHighlightCount = highlightCount;
	_cachedMessageCount = messageCount;

	NSDockTile *dockTile = NSApp.dockTile;

	/* Messages only: the system badge is exactly right. */
	if (highlightCount == 0) {
		dockTile.contentView = nil;
		dockTile.badgeLabel = [self badgeStringForCount:messageCount];

		[dockTile display];

		return;
	}

	/* The system badge stays set to the combined count so that the Dock
	 exposes it to assistive technology; the custom tile only adds the
	 highlight badge underneath it. */
	dockTile.badgeLabel = [self badgeStringForCount:(messageCount + highlightCount)];

	TVCDockIconBadgeView *badgeView = (TVCDockIconBadgeView *)dockTile.contentView;

	if ([badgeView isKindOfClass:[TVCDockIconBadgeView class]] == NO) {
		badgeView = [[TVCDockIconBadgeView alloc]
			initWithFrame:NSMakeRect(0.0, 0.0, dockTile.size.width, dockTile.size.height)];

		dockTile.contentView = badgeView;
	}

	badgeView.highlightCount = highlightCount;
	badgeView.messageCount = messageCount;

	[badgeView setNeedsDisplay:YES];

	[dockTile display];
}

+ (NSString *)badgeStringForCount:(NSUInteger)count
{
	if (count > 9999) {
		return TXTLS(@"TVCMainWindow[dki-bg]", TXFormattedNumber(9999));
	}

	return TXFormattedNumber(count);
}

@end

#pragma mark -

@implementation TVCDockIconBadgeView

- (BOOL)isFlipped
{
	return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = self.bounds;

	[NSApp.applicationIconImage drawInRect:bounds
								  fromRect:NSZeroRect
								 operation:NSCompositingOperationSourceOver
								  fraction:1.0];

	/* Badge metrics are proportional to the tile so the result
	 looks the same regardless of the dock magnification. The top
	 right slot is left to the system badge (the combined count, see
	 +drawWithHighlightCount:messageCount:); the highlight badge is
	 drawn directly beneath it. */
	CGFloat badgeHeight = floor(bounds.size.height * 0.26);
	CGFloat separator = 1.0;

	if (self.highlightCount > 0) {
		CGFloat top = (NSMaxY(bounds) - badgeHeight - separator);

		[self drawBadgeWithCount:self.highlightCount
						   color:[NSColor systemGreenColor]
						topRight:NSMakePoint(NSMaxX(bounds), top)
						  height:badgeHeight];
	}
}

- (NSRect)drawBadgeWithCount:(NSUInteger)count color:(NSColor *)color topRight:(NSPoint)topRight height:(CGFloat)height
{
	NSString *string = [TVCDockIcon badgeStringForCount:count];

	NSDictionary *attributes = @{
		NSFontAttributeName : [NSFont boldSystemFontOfSize:(height * 0.62)],
		NSForegroundColorAttributeName : [NSColor whiteColor]
	};

	NSSize textSize = [string sizeWithAttributes:attributes];

	CGFloat width = MAX(height, ceil(textSize.width + (height * 0.6)));

	NSRect frame = NSMakeRect((topRight.x - width), (topRight.y - height), width, height);

	NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:frame xRadius:(height / 2.0) yRadius:(height / 2.0)];

	[color setFill];
	[pill fill];

	[[NSColor.whiteColor colorWithAlphaComponent:0.9] setStroke];
	pill.lineWidth = MAX(1.0, (height * 0.06));
	[pill stroke];

	NSPoint textOrigin =
		NSMakePoint((NSMidX(frame) - (textSize.width / 2.0)), (NSMidY(frame) - (textSize.height / 2.0)));

	[string drawAtPoint:textOrigin withAttributes:attributes];

	return frame;
}

@end

NS_ASSUME_NONNULL_END
