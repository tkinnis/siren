#import <ApplicationServices/ApplicationServices.h>
#import <unistd.h>
#import <stdlib.h>

int main(int argc, char* argv[]) {
    if (argc < 3) return 1;
    double x = atof(argv[1]);
    double y = atof(argv[2]);
    CGPoint pt = CGPointMake(x, y);
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, pt, kCGMouseButtonLeft);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, pt, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, down);
    usleep(50000);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    return 0;
}
