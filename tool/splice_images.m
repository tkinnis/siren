#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 4) {
            NSLog(@"Usage: splice_images <img1_left> <img2_right> <output_png>");
            return 1;
        }

        NSString *path1 = [NSString stringWithUTF8String:argv[1]];
        NSString *path2 = [NSString stringWithUTF8String:argv[2]];
        NSString *outPath = [NSString stringWithUTF8String:argv[3]];

        NSImage *img1 = [[NSImage alloc] initWithContentsOfFile:path1];
        NSImage *img2 = [[NSImage alloc] initWithContentsOfFile:path2];

        if (!img1 || !img2) {
            NSLog(@"Error: Failed to load input images.");
            return 1;
        }

        NSSize size = NSMakeSize(1200, 800);
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
                          pixelsWide:(NSInteger)size.width
                          pixelsHigh:(NSInteger)size.height
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSDeviceRGBColorSpace
                         bytesPerRow:0
                        bitsPerPixel:0];

        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext setCurrentContext:context];

        NSRect fullRect = NSMakeRect(0, 0, size.width, size.height);

        // 1. Draw Image 1 (Left - Light)
        [img1 drawInRect:fullRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];

        // 2. Define diagonal cut for Image 2 (Right - Dark)
        // In Cocoa NSView/NSImage coords, y=0 is bottom, y=size.height is top.
        // Let's angle it so top seam is at x = 680, bottom seam is at x = 520.
        CGFloat topX = size.width * 0.56;    // 672
        CGFloat bottomX = size.height * 0.65; // 520
        // Wait, let's use width fractions:
        topX = size.width * 0.56;    // 672
        bottomX = size.width * 0.44; // 528

        CGContextRef cgContext = [context CGContext];
        CGContextSaveGState(cgContext);

        CGMutablePathRef clipPath = CGPathCreateMutable();
        CGPathMoveToPoint(clipPath, NULL, topX, size.height);
        CGPathAddLineToPoint(clipPath, NULL, size.width, size.height);
        CGPathAddLineToPoint(clipPath, NULL, size.width, 0);
        CGPathAddLineToPoint(clipPath, NULL, bottomX, 0);
        CGPathCloseSubpath(clipPath);

        CGContextAddPath(cgContext, clipPath);
        CGContextClip(cgContext);
        CGPathRelease(clipPath);

        // Draw Image 2 into clipped region
        [img2 drawInRect:fullRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
        CGContextRestoreGState(cgContext);

        // 3. Draw elegant divider line along seam
        // First a subtle dark shadow line for contrast
        CGContextSaveGState(cgContext);
        CGContextSetLineWidth(cgContext, 3.0);
        CGContextSetRGBStrokeColor(cgContext, 0.0, 0.0, 0.0, 0.4);
        CGContextMoveToPoint(cgContext, topX, size.height);
        CGContextAddLineToPoint(cgContext, bottomX, 0);
        CGContextStrokePath(cgContext);

        // Then a clean crisp white divider line in the center
        CGContextSetLineWidth(cgContext, 1.5);
        CGContextSetRGBStrokeColor(cgContext, 1.0, 1.0, 1.0, 0.85);
        CGContextMoveToPoint(cgContext, topX, size.height);
        CGContextAddLineToPoint(cgContext, bottomX, 0);
        CGContextStrokePath(cgContext);
        CGContextRestoreGState(cgContext);

        [NSGraphicsContext restoreGraphicsState];

        NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        BOOL ok = [pngData writeToFile:outPath atomically:YES];
        if (!ok) {
            NSLog(@"Failed to write output image to %@", outPath);
            return 1;
        }

        NSLog(@"Successfully created spliced image at %@", outPath);
    }
    return 0;
}
