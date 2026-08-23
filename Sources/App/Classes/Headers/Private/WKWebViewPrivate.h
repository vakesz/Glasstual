/* WebKit private API that Glasstual still depends on.

 Everything here is SPI without a public replacement. The two file
 access flags let a style loaded from a file URL reference its own
 resources; the context menu delegate lets the channel view replace
 WebKit's menu while keeping WebKit's own items. Both are used from
 TVCLogViewInternalWK2.m only. */

@interface WKPreferences ()
@property(nonatomic, setter=_setAllowFileAccessFromFileURLs:) BOOL _allowFileAccessFromFileURLs;
@end

@interface WKWebViewConfiguration ()
@property(nonatomic, setter=_setAllowUniversalAccessFromFileURLs:) BOOL _allowUniversalAccessFromFileURLs;
@end
