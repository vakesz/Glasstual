
#import "TXApplicationPrivate.h"

int main(int argc, const char *argv[])
{
	@autoreleasepool {
#ifndef DEBUG
		if ([TXApplication checkForOtherCopiesOfGlasstualRunning] == NO) {
			exit(0);
		}
#endif

		NSApplicationMain(argc, argv);
	}

	return 0;
}
