/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import "TVCAutoExpandingTextField.h"

BOOL TVCAutoExpandingFieldUpdatePreferredMaxLayoutWidth(NSTextField *field) {
  NSCParameterAssert(field != nil);

  if (field.cell.wraps == NO) {
    return NO;
  }

  CGFloat width = NSWidth(field.bounds);

  if (width <= 0.0 || field.preferredMaxLayoutWidth == width) {
    return NO;
  }

  field.preferredMaxLayoutWidth = width;

  [field invalidateIntrinsicContentSize];

  return YES;
}
