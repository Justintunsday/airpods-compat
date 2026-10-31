#import "Runtime.h"
#import <fcntl.h>
#import <errno.h>
#import <unistd.h>
void ACWithRegistrationGuard(void (^work)(void)) {
        NSString *guard = ACSupportPath([@".registration-in-progress." stringByAppendingString:ACProcessName()]);
        NSFileManager *fm = [NSFileManager defaultManager];
        NSError *directoryError = nil;
        if (![fm createDirectoryAtPath:[guard stringByDeletingLastPathComponent]
            withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
            AC_LOG(@"cannot create registration guard directory: %@", directoryError);
            return;
        }
        int marker = open(guard.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0644);
        if (marker < 0) {
            AC_LOG(@"registration guard exists or cannot be created for %@ (errno=%d); skipping registration until guard is removed",
                   ACProcessName(), errno);
            return;
        }
        close(marker);
        work();
        if (![fm removeItemAtPath:guard error:nil]) {
            AC_LOG(@"could not clear registration guard %@", guard);
        }
}
