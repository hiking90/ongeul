#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher
+ (BOOL)performSafely:(void (NS_NOESCAPE ^)(void))block {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"ObjCExceptionCatcher: %@", exception);
        return NO;
    }
}
@end
