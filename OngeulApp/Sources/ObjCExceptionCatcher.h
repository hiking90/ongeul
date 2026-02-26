#import <Foundation/Foundation.h>

@interface ObjCExceptionCatcher : NSObject
+ (BOOL)performSafely:(void (NS_NOESCAPE ^)(void))block;
@end
