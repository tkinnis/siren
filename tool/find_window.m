#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
        NSArray *windows = (__bridge NSArray *)windowList;
        for (NSDictionary *info in windows) {
            NSString *owner = info[(NSString *)kCGWindowOwnerName];
            NSNumber *wid = info[(NSString *)kCGWindowNumber];
            NSDictionary *bounds = info[(NSString *)kCGWindowBounds];
            if (owner) {
                NSLog(@"Owner: %@ ID: %@ Bounds: %@", owner, wid, bounds);
            }
        }
        CFRelease(windowList);
    }
    return 0;
}
