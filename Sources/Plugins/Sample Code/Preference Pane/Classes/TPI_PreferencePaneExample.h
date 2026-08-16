
#import "Glasstual.h"

@interface TPI_PreferencePaneExample : NSObject <THOPluginProtocol>
@property(nonatomic, strong) IBOutlet NSView *ourView;

- (IBAction)preferenceChanged:(nullable id)sender;
@end
