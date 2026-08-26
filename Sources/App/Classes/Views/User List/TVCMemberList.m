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

#import "IRCChannelMemberListControllerPrivate.h"
#import "IRCChannelUser.h"
#import "IRCUser.h"
#import "NSViewHelperPrivate.h"
#import "TLOLocalization.h"
#import "TPCPreferencesLocal.h"
#import "TVCMainWindow.h"
#import "TVCMemberListCellPrivate.h"
#import "TVCMemberListPrivate.h"
#import "TVCMemberListUserInfoPopoverPrivate.h"
#import "TXMasterController.h"
#import "TXMenuControllerPrivate.h"

NS_ASSUME_NONNULL_BEGIN

/* Source list rows in Messages and Contacts are 28 points; headers take
 the height AppKit uses for its own section headers. */
static const CGFloat TVCMemberListMemberRowHeight = 28.0;
static const CGFloat TVCMemberListHeaderRowHeight = 22.0;

static NSString *const TVCMemberListMemberViewIdentifier = @"MemberView";
static NSString *const TVCMemberListHeaderViewIdentifier = @"HeaderView";

@interface TVCMemberListSection ()
@property(nonatomic, assign, readwrite) IRCUserRank rank;
@property(nonatomic, copy, readwrite) NSString *title;
@property(nonatomic, assign, readwrite) NSRange memberRange;
@end

@interface TVCMemberList () <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong, nullable) NSTrackingArea *userPopoverTrackingArea;
@property(nonatomic, assign) BOOL userPopoverMouseIsInView;
@property(nonatomic, assign) BOOL userPopoverTimerIsActive;
@property(nonatomic, assign) NSPoint userPopoverLastKnownLocalPoint;
@property(nonatomic, assign) NSInteger lastRowShownUserInfoPopover;
@property(nonatomic, strong, readwrite)
    IBOutlet TVCMemberListUserInfoPopover *memberListUserInfoPopover;
@property(nonatomic, strong, readwrite)
    IBOutlet IRCChannelMemberListController *contentController;
@property(nonatomic, strong) NSMutableArray<TVCMemberListSection *> *sections;
@end

@implementation TVCMemberListSection

- (NSString *)description {
  return [NSString stringWithFormat:@"<TVCMemberListSection %@ %@>", self.title,
                                    NSStringFromRange(self.memberRange)];
}

@end

@implementation TVCMemberList

- (void)awakeFromNib {
  [super awakeFromNib];

  self.dataSource = self;
  self.delegate = self;

  [self updateTrackingAreas];

  [self registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];

  /* -viewDidMoveToWindow is not guaranteed to alternate between a window
   and nil. Remove any previous registration first so that moving within
   the same window does not leave duplicate observers behind. Only our
   own names are removed; a blanket -removeObserver: would also drop
   the registrations AppKit keeps for the table itself. */
  [RZNotificationCenter() removeObserver:self
                                    name:NSWindowDidBecomeKeyNotification
                                  object:nil];
  [RZNotificationCenter() removeObserver:self
                                    name:NSWindowDidResignKeyNotification
                                  object:nil];
  [RZNotificationCenter() removeObserver:self
                                    name:TVCMainWindowRedrawSubviewsNotification
                                  object:nil];
  [RZNotificationCenter() removeObserver:self
                                    name:NSViewBoundsDidChangeNotification
                                  object:[self scrollViewContentView]];

  TVCMainWindow *mainWindow = self.mainWindow;

  if (mainWindow == nil) {
    return;
  }

  [RZNotificationCenter() addObserver:self
                             selector:@selector(windowDidBecomeKey:)
                                 name:NSWindowDidBecomeKeyNotification
                               object:mainWindow];

  [RZNotificationCenter() addObserver:self
                             selector:@selector(windowDidResignKey:)
                                 name:NSWindowDidResignKeyNotification
                               object:mainWindow];

  [RZNotificationCenter() addObserver:self
                             selector:@selector(windowMainStateChanged:)
                                 name:NSWindowDidBecomeMainNotification
                               object:mainWindow];

  [RZNotificationCenter() addObserver:self
                             selector:@selector(windowMainStateChanged:)
                                 name:NSWindowDidResignMainNotification
                               object:mainWindow];

  [RZNotificationCenter() addObserver:self
                             selector:@selector(mainWindowRequiresRedraw:)
                                 name:TVCMainWindowRedrawSubviewsNotification
                               object:mainWindow];

  [RZNotificationCenter()
      addObserver:self
         selector:@selector(scrollViewBoundsDidChangeNotification:)
             name:NSViewBoundsDidChangeNotification
           object:[self scrollViewContentView]];
}

#pragma mark -
#pragma mark Utilities

- (void)assignToChannel:(nullable IRCChannel *)channel {
  [self.contentController assignToChannel:channel];
}

- (NSArray<IRCChannelUser *> *)members {
  return self.contentController.arrangedObjects;
}

- (NSMutableArray<TVCMemberListSection *> *)sections {
  if (self->_sections == nil) {
    self->_sections = [NSMutableArray array];
  }

  return self->_sections;
}

- (nullable id)itemAtRow:(NSInteger)row {
  NSParameterAssert(row >= 0);

  NSInteger memberIndex = [self memberIndexForRow:row];

  if (memberIndex < 0) {
    return nil;
  }

  NSArray *members = self.members;

  if ((NSUInteger)memberIndex >= members.count) {
    return nil;
  }

  return members[memberIndex];
}

- (NSInteger)rowForItem:(nullable id)item {
  if (item == nil) {
    return (-1);
  }

  NSInteger index = [self.members indexOfObjectIdenticalTo:item];

  if (index == NSNotFound) {
    return (-1);
  }

  return [self rowForMemberAtIndex:index];
}

#pragma mark -
#pragma mark Sections

/* The sort order groups server staff first when the preference asks for
 it, then by channel rank. Sections follow the same key so that each one
 is a contiguous run of the sorted list. */
+ (IRCUserRank)sectionRankForMember:(IRCChannelUser *)member {
  if (member.user.isIRCop && [TPCPreferences memberListSortFavorsServerStaff]) {
    return IRCUserRankIRCopByMode;
  }

  return member.rank;
}

+ (NSString *)titleForSectionRank:(IRCUserRank)rank {
  switch (rank) {
  case IRCUserRankIRCopByMode:
    return TXTLS(@"TVCMainWindow[mls-sf]");
  case IRCUserRankChannelOwner:
    return TXTLS(@"TVCMainWindow[mls-ow]");
  case IRCUserRankSuperOperator:
    return TXTLS(@"TVCMainWindow[mls-ad]");
  case IRCUserRankNormalOperator:
    return TXTLS(@"TVCMainWindow[mls-op]");
  case IRCUserRankHalfOperator:
    return TXTLS(@"TVCMainWindow[mls-ho]");
  case IRCUserRankVoiced:
    return TXTLS(@"TVCMainWindow[mls-vo]");
  default:
    return TXTLS(@"TVCMainWindow[mls-me]");
  }
}

+ (TVCMemberListSection *)sectionWithRank:(IRCUserRank)rank
                              memberRange:(NSRange)memberRange {
  TVCMemberListSection *section = [TVCMemberListSection new];

  section.rank = rank;
  section.title = [self titleForSectionRank:rank];
  section.memberRange = memberRange;

  return section;
}

- (BOOL)isGrouped {
  return (self.sections.count > 1);
}

- (void)rebuildSections {
  NSMutableArray<TVCMemberListSection *> *sections = [NSMutableArray array];

  TVCMemberListSection *current = nil;

  NSArray<IRCChannelUser *> *members = self.members;

  for (NSUInteger index = 0; index < members.count; index++) {
    IRCUserRank rank = [self.class sectionRankForMember:members[index]];

    if (current && current.rank == rank) {
      current.memberRange = NSMakeRange(current.memberRange.location,
                                        (current.memberRange.length + 1));

      continue;
    }

    current = [self.class sectionWithRank:rank
                              memberRange:NSMakeRange(index, 1)];

    [sections addObject:current];
  }

  self.sections = sections;
}

- (void)shiftSectionsAfter:(NSInteger)sectionIndex by:(NSInteger)delta {
  NSArray<TVCMemberListSection *> *sections = self.sections;

  for (NSInteger index = (sectionIndex + 1); index < (NSInteger)sections.count;
       index++) {
    TVCMemberListSection *section = sections[index];

    section.memberRange = NSMakeRange((section.memberRange.location + delta),
                                      section.memberRange.length);
  }
}

- (NSInteger)sectionIndexContainingMemberIndex:(NSUInteger)memberIndex {
  NSArray<TVCMemberListSection *> *sections = self.sections;

  for (NSUInteger index = 0; index < sections.count; index++) {
    if (NSLocationInRange(memberIndex, sections[index].memberRange)) {
      return index;
    }
  }

  return (-1);
}

#pragma mark -
#pragma mark Row Geometry

- (BOOL)isGroupRow:(NSInteger)row {
  return ([self sectionIndexForHeaderRow:row] >= 0);
}

- (NSInteger)headerRowForSectionAtIndex:(NSUInteger)sectionIndex {
  if (self.isGrouped == NO) {
    return (-1);
  }

  return (self.sections[sectionIndex].memberRange.location + sectionIndex);
}

- (NSInteger)sectionIndexForHeaderRow:(NSInteger)row {
  if (self.isGrouped == NO || row < 0) {
    return (-1);
  }

  NSArray<TVCMemberListSection *> *sections = self.sections;

  for (NSUInteger index = 0; index < sections.count; index++) {
    NSInteger headerRow = (sections[index].memberRange.location + index);

    if (headerRow == row) {
      return index;
    }

    if (headerRow > row) {
      break;
    }
  }

  return (-1);
}

- (NSInteger)rowForMemberAtIndex:(NSInteger)memberIndex {
  if (memberIndex < 0) {
    return (-1);
  }

  if (self.isGrouped == NO) {
    return memberIndex;
  }

  /* One header precedes every section that starts at or before
   the member, including the member's own. */
  NSInteger headers = 0;

  for (TVCMemberListSection *section in self.sections) {
    if ((NSInteger)section.memberRange.location > memberIndex) {
      break;
    }

    headers++;
  }

  return (memberIndex + headers);
}

- (NSInteger)memberIndexForRow:(NSInteger)row {
  if (row < 0) {
    return (-1);
  }

  if (self.isGrouped == NO) {
    return row;
  }

  NSArray<TVCMemberListSection *> *sections = self.sections;

  for (NSUInteger index = 0; index < sections.count; index++) {
    NSRange memberRange = sections[index].memberRange;

    NSInteger headerRow = (memberRange.location + index);

    if (row == headerRow) {
      return (-1);
    }

    if (row <= (headerRow + (NSInteger)memberRange.length)) {
      return (row - index - 1);
    }
  }

  return (-1);
}

#pragma mark -
#pragma mark Content Changes

- (void)membersReplaced {
  [self rebuildSections];

  [self reloadData];
}

- (void)memberInsertedAtIndex:(NSUInteger)memberIndex {
  NSArray<IRCChannelUser *> *members = self.members;

  if (memberIndex >= members.count) {
    [self membersReplaced];

    return;
  }

  IRCUserRank rank = [self.class sectionRankForMember:members[memberIndex]];

  NSMutableArray<TVCMemberListSection *> *sections = self.sections;

  BOOL wasGrouped = self.isGrouped;

  /* Find a section that can absorb the member: the one whose
   range the index falls in, or the one that ends right before it. */
  NSInteger sectionIndex = (-1);
  NSInteger insertionIndex = sections.count;

  for (NSUInteger index = 0; index < sections.count; index++) {
    NSRange memberRange = sections[index].memberRange;

    if (memberIndex < memberRange.location) {
      insertionIndex = index;

      break;
    }

    if (memberIndex <= NSMaxRange(memberRange)) {
      if (sections[index].rank == rank) {
        sectionIndex = index;

        break;
      }

      if (memberIndex < NSMaxRange(memberRange)) {
        /* A differently ranked member landed inside a section.
         The sort key and the section key disagree; start over. */
        [self membersReplaced];

        return;
      }

      insertionIndex = (index + 1);
    }
  }

  if (sectionIndex >= 0) {
    TVCMemberListSection *section = sections[sectionIndex];

    section.memberRange = NSMakeRange(section.memberRange.location,
                                      (section.memberRange.length + 1));

    [self shiftSectionsAfter:sectionIndex by:1];

    [self insertRowsAtIndexes:
              [NSIndexSet
                  indexSetWithIndex:[self rowForMemberAtIndex:memberIndex]]
                withAnimation:NSTableViewAnimationEffectNone];

    return;
  }

  TVCMemberListSection *section =
      [self.class sectionWithRank:rank memberRange:NSMakeRange(memberIndex, 1)];

  [sections insertObject:section atIndex:insertionIndex];

  [self shiftSectionsAfter:insertionIndex by:1];

  NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];

  [rows addIndex:[self rowForMemberAtIndex:memberIndex]];

  if (self.isGrouped) {
    if (wasGrouped) {
      [rows addIndex:[self headerRowForSectionAtIndex:insertionIndex]];
    } else {
      /* The list just went from flat to grouped: every section
       gains a header, not only the new one. */
      for (NSUInteger index = 0; index < sections.count; index++) {
        [rows addIndex:[self headerRowForSectionAtIndex:index]];
      }
    }
  }

  [self insertRowsAtIndexes:rows withAnimation:NSTableViewAnimationEffectNone];
}

- (void)memberRemovedAtIndex:(NSUInteger)memberIndex {
  NSInteger sectionIndex = [self sectionIndexContainingMemberIndex:memberIndex];

  if (sectionIndex < 0) {
    [self membersReplaced];

    return;
  }

  NSMutableArray<TVCMemberListSection *> *sections = self.sections;

  TVCMemberListSection *section = sections[sectionIndex];

  /* Rows are removed by their index before the change. */
  NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];

  [rows addIndex:[self rowForMemberAtIndex:memberIndex]];

  BOOL sectionIsEmptied = (section.memberRange.length == 1);

  if (sectionIsEmptied) {
    [rows addIndex:[self headerRowForSectionAtIndex:sectionIndex]];

    if (sections.count == 2) {
      /* Back to a flat list; the surviving section loses its header. */
      [rows
          addIndex:[self headerRowForSectionAtIndex:((sectionIndex == 0) ? 1
                                                                         : 0)]];
    }

    [sections removeObjectAtIndex:sectionIndex];

    [self shiftSectionsAfter:(sectionIndex - 1) by:(-1)];
  } else {
    section.memberRange = NSMakeRange(section.memberRange.location,
                                      (section.memberRange.length - 1));

    [self shiftSectionsAfter:sectionIndex by:(-1)];
  }

  [self removeRowsAtIndexes:rows withAnimation:NSTableViewAnimationEffectNone];
}

#pragma mark -
#pragma mark Table View Data Source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  NSInteger rows = self.members.count;

  if (self.isGrouped) {
    rows += self.sections.count;
  }

  return rows;
}

- (nullable id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
                          row:(NSInteger)row {
  NSInteger sectionIndex = [self sectionIndexForHeaderRow:row];

  if (sectionIndex >= 0) {
    return self.sections[sectionIndex];
  }

  return [self itemAtRow:row];
}

#pragma mark -
#pragma mark Table View Delegate

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
  return [self isGroupRow:row];
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
  return ([self isGroupRow:row] == NO);
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
  if ([self isGroupRow:row]) {
    return TVCMemberListHeaderRowHeight;
  }

  return TVCMemberListMemberRowHeight;
}

- (nullable NSString *)tableView:(NSTableView *)tableView
    typeSelectStringForTableColumn:(nullable NSTableColumn *)tableColumn
                               row:(NSInteger)row {
  IRCChannelUser *member = [self itemAtRow:row];

  return member.user.nickname;
}

- (nullable NSView *)tableView:(NSTableView *)tableView
            viewForTableColumn:(nullable NSTableColumn *)tableColumn
                           row:(NSInteger)row {
  if ([self isGroupRow:row]) {
    return [self makeViewWithIdentifier:TVCMemberListHeaderViewIdentifier
                                  owner:self];
  }

  return [self makeViewWithIdentifier:TVCMemberListMemberViewIdentifier
                                owner:self];
}

- (nullable NSTableRowView *)tableView:(NSTableView *)tableView
                         rowViewForRow:(NSInteger)row {
  if ([self isGroupRow:row]) {
    return nil; // AppKit's source list header row
  }

  return [[TVCMemberListRowCell alloc] initWithMemberList:self];
}

- (void)tableView:(NSTableView *)tableView
    didAddRowView:(NSTableRowView *)rowView
           forRow:(NSInteger)row {
  [self refreshDrawingForRow:row];
}

#pragma mark -
#pragma mark Mouse Tracking

- (void)updateTrackingAreas {
  [super updateTrackingAreas];

  if (self.userPopoverTrackingArea) {
    [self removeTrackingArea:self.userPopoverTrackingArea];
  }

  self.userPopoverTrackingArea = [[NSTrackingArea alloc]
      initWithRect:self.bounds
           options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                    NSTrackingActiveInActiveApp | NSTrackingInVisibleRect)
             owner:self
          userInfo:nil];

  [self addTrackingArea:self.userPopoverTrackingArea];
}

- (void)destroyUserInfoPopoverOnWindowKeyChange {
  [self destroyUserInfoPopover]; // Destroy anything shown
}

- (void)destroyUserInfoPopover {
  [self cancelPerformRequestsWithSelector:@selector
        (popDelayedUserInfoExpansionFrame)
                                   object:nil];

  self.lastRowShownUserInfoPopover = (-1);

  self.userPopoverMouseIsInView = NO;
  self.userPopoverTimerIsActive = NO;

  self.userPopoverLastKnownLocalPoint = NSZeroPoint;

  if (self.memberListUserInfoPopover.shown) {
    [self.memberListUserInfoPopover close];
  }
}

- (void)mouseEntered:(NSEvent *)theEvent {
  self.userPopoverMouseIsInView = YES;

  if (self.userPopoverTimerIsActive == NO) {
    self.userPopoverTimerIsActive = YES;

    [self performSelector:@selector(popDelayedUserInfoExpansionFrame)
               withObject:nil
               afterDelay:1.0];
  }
}

- (void)mouseExited:(NSEvent *)theEvent {
  [self destroyUserInfoPopover];
}

- (void)mouseMoved:(NSEvent *)theEvent {
  NSPoint localPoint = [self convertPoint:theEvent.locationInWindow
                                 fromView:nil];

  [self popUserInfoExpansionFrameAtPoint:localPoint ignoreTimerCheck:NO];
}

- (void)popUserInfoExpansionFrameAtPoint:(NSPoint)localPoint
                        ignoreTimerCheck:(BOOL)ignoreTimer {
  self.userPopoverLastKnownLocalPoint = localPoint;

  if ([XRAccessibility isVoiceOverEnabled]) {
    return;
  }

  if (self.userPopoverTimerIsActive && ignoreTimer == NO) {
    return; // Only allow the timer to pop it
  }

  if (self.window.keyWindow == NO) {
    return;
  }

  NSInteger row = [self rowAtPoint:localPoint];

  if (row < 0 || [self isGroupRow:row]) {
    return;
  }

  if (self.lastRowShownUserInfoPopover != row) {
    self.lastRowShownUserInfoPopover = row;

    id rowView = [self viewAtColumn:0 row:row makeIfNecessary:NO];

    [rowView drawWithExpansionFrame];
  }
}

- (void)popDelayedUserInfoExpansionFrame {
  /* Basically we delay the expansion frame (also known as the popover)
   by one second from the time the user enters the frame so that if they
   are just moving the mouse through it to another portion of the window
   we do not try to show a popover. We only want to show a popover if the
   user has some intention of being in the list. */

  if (self.userPopoverMouseIsInView) {
    [self popUserInfoExpansionFrameAtPoint:self.userPopoverLastKnownLocalPoint
                          ignoreTimerCheck:YES];
  }

  self.userPopoverTimerIsActive = NO;
}

#pragma mark -
#pragma mark Scroll View

- (void)scrollViewBoundsDidChangeNotification:(NSNotification *)notification {
  if ([TPCPreferences memberListUpdatesUserInfoPopoverOnScroll] == NO) {
    return;
  }

  if (notification.object != [self scrollViewContentView]) {
    return;
  }

  NSPoint mouseLocation = [NSEvent mouseLocation];

  NSRect mouseLocationFaked =
      NSMakeRect(mouseLocation.x, mouseLocation.y, 1.0, 1.0);

  NSRect remotePoint = [self.window convertRectFromScreen:mouseLocationFaked];

  NSPoint localPoint = [self convertPoint:remotePoint.origin fromView:nil];

  [self popUserInfoExpansionFrameAtPoint:localPoint ignoreTimerCheck:YES];
}

- (id)scrollViewContentView {
  return self.enclosingScrollView.contentView;
}

#pragma mark -
#pragma mark Drag and Drop

/* Files can only be dropped on a member, not on a section header. */
- (NSInteger)draggedRow:(id<NSDraggingInfo>)sender {
  NSPoint p = [self convertPoint:[sender draggingLocation] fromView:nil];

  NSInteger row = [self rowAtPoint:p];

  if (row < 0 || [self isGroupRow:row]) {
    return (-1);
  }

  return row;
}

- (NSArray *)draggedFiles:(id<NSDraggingInfo>)sender {
  NSArray<NSURL *> *fileURLs = [[sender draggingPasteboard]
      readObjectsForClasses:@[ [NSURL class] ]
                    options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];

  NSMutableArray<NSString *> *filePaths = [NSMutableArray array];

  for (NSURL *fileURL in fileURLs) {
    if (fileURL.path.length > 0) {
      [filePaths addObject:fileURL.path];
    }
  }

  return [filePaths copy];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  return [self draggingUpdated:sender];
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
  NSArray *files = [self draggedFiles:sender];

  if (files.count > 0 && [self draggedRow:sender] >= 0) {
    return NSDragOperationCopy;
  } else {
    return NSDragOperationNone;
  }
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
  NSArray *files = [self draggedFiles:sender];

  return (files.count > 0 && [self draggedRow:sender] >= 0);
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  NSArray *files = [self draggedFiles:sender];

  if (files.count > 0) {
    NSInteger row = [self draggedRow:sender];

    if (row >= 0) {
      [menuController() memberSendDroppedFiles:files row:row];

      return YES;
    }
  }

  return NO;
}

#pragma mark -
#pragma mark Drawing Updates

- (void)refreshAllDrawings {
  [self refreshAllDrawings:NO];
}

- (void)refreshAllDrawings:(BOOL)skipOcclusionCheck {
  for (NSInteger i = 0; i < self.numberOfRows; i++) {
    [self refreshDrawingForRow:i skipOcclusionCheck:skipOcclusionCheck];
  }
}

- (void)refreshDrawingForRow:(NSInteger)rowIndex {
  [self refreshDrawingForRow:rowIndex skipOcclusionCheck:NO];
}

- (void)refreshDrawingForRow:(NSInteger)rowIndex
          skipOcclusionCheck:(BOOL)skipOcclusionCheck {
  if (rowIndex < 0) {
    return;
  }

  if (skipOcclusionCheck == NO && self.mainWindow.occluded) {
    return;
  }

  NSView *cellView = [self viewAtColumn:0 row:rowIndex makeIfNecessary:NO];

  cellView.needsDisplay = YES;

  /* The row view draws the selection, whose emphasis follows the
   window's key state. */
  [self rowViewAtRow:rowIndex makeIfNecessary:NO].needsDisplay = YES;
}

- (void)refreshDrawingForMember:(IRCChannelUser *)cellItem {
  NSParameterAssert(cellItem != nil);

  NSInteger rowIndex = [self rowForItem:cellItem];

  [self refreshDrawingForRow:rowIndex];
}

- (void)refreshDrawingForChangesToPreference:(NSString *)preferenceKey {
  static NSDictionary<NSString *, NSNumber *> *preferenceMap = nil;

  static dispatch_once_t onceToken;

  dispatch_once(&onceToken, ^{
    preferenceMap = @{
      @"User List Mode Badge Colors -> +y" : @(IRCUserRankIRCopByMode),
      @"User List Mode Badge Colors -> +q" : @(IRCUserRankChannelOwner),
      @"User List Mode Badge Colors -> +a" : @(IRCUserRankSuperOperator),
      @"User List Mode Badge Colors -> +o" : @(IRCUserRankNormalOperator),
      @"User List Mode Badge Colors -> +h" : @(IRCUserRankHalfOperator),
      @"User List Mode Badge Colors -> +v" : @(IRCUserRankVoiced),
      @"User List Mode Badge Colors -> no mode" : @(IRCUserRankNone)
    };
  });

  NSNumber *rank = preferenceMap[preferenceKey];

  if (rank == nil) {
    return;
  }

  IRCUserRank rankEnum = rank.unsignedIntegerValue;

  [self refreshDrawingForMembersWithRank:rankEnum
                                 isIRCop:(rankEnum == IRCUserRankIRCopByMode)];
}

- (void)refreshDrawingForMembersWithRank:(IRCUserRank)rank
                                 isIRCop:(BOOL)isIRCop {
  [self.members enumerateObjectsUsingBlock:^(IRCChannelUser *member,
                                             NSUInteger index, BOOL *stop) {
    if ((member.ranks & rank) == 0 &&
        (isIRCop && isIRCop != member.user.isIRCop)) {
      return;
    }

    [self refreshDrawingForRow:[self rowForMemberAtIndex:index]];
  }];
}

- (void)drawContextMenuHighlightForRow:(int)row {
  // Do not draw focus ring ...
}

- (BOOL)allowsVibrancy {
  return YES;
}

- (void)applicationAppearanceChanged {
  [self invalidateBackgroundForSelection];

  [self refreshAllDrawings:YES];

  self.needsDisplay = YES;
}

- (void)systemAppearanceChanged {
  [self applicationAppearanceChanged];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  [self windowKeyStateChanged:notification];
}

- (void)windowDidResignKey:(NSNotification *)notification {
  [self destroyUserInfoPopoverOnWindowKeyChange];

  [self windowKeyStateChanged:notification];
}

- (void)windowKeyStateChanged:(NSNotification *)notification {
  [self respondToRequiresRedraw];
}

- (void)windowMainStateChanged:(NSNotification *)notification {
  /* Row emphasis follows main-window status (see TVCMemberListRowCell),
   which AppKit does not re-evaluate on its own. */
  [self enumerateAvailableRowViewsUsingBlock:^(__kindof NSTableRowView *rowView,
                                               NSInteger row) {
    if ([rowView isKindOfClass:[TVCMemberListRowCell class]]) {
      [rowView refreshEmphasis];
    }
  }];

  [self respondToRequiresRedraw];
}

- (void)mainWindowRequiresRedraw:(NSNotification *)notification {
  [self respondToRequiresRedraw];
}

- (void)respondToRequiresRedraw {
  [self refreshAllDrawings:YES];
}

#pragma mark -
#pragma mark Events

- (nullable NSMenu *)menuForEvent:(NSEvent *)theEvent {
  NSInteger rowBeneathMouse = self.rowBeneathMouse;

  if (rowBeneathMouse < 0 || [self isGroupRow:rowBeneathMouse]) {
    return nil;
  }

  if ([self.selectedRowIndexes containsIndex:rowBeneathMouse] == NO) {
    [self selectItemAtIndex:rowBeneathMouse];
  }

  return menuController().userControlMenu;
}

- (void)keyDown:(NSEvent *)e {
  if (self.keyDelegate == nil) {
    return;
  }

  switch (e.keyCode) {
  case 125: // down arrow
  case 126: // up arrow
  {
    [super keyDown:e];

    break;
  }
  case 123: // left arrow
  case 124: // right arrow
  case 116: // page up
  case 121: // page down
  {
    break;
  }
  default: {
    [self.keyDelegate memberListKeyDown:e];

    break;
  }
  }
}

@end

NS_ASSUME_NONNULL_END
