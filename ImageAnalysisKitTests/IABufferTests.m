//
//  IABufferTests.m
//  ImageAnalysisKit
//
//  Created by Rob Menke on 4/20/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

@import XCTest;
@import ImageAnalysisKit;
@import CoreImage;

#include <inttypes.h>

#ifdef TEST_IMAGE_DIR
    #define WRITE_TO_FILE(BUFFER, TAG) do { \
        NSURL *dir = [NSURL fileURLWithPath:(TEST_IMAGE_DIR).stringByExpandingTildeInPath isDirectory:YES]; \
        NSURL *url = [NSURL fileURLWithPath:@"test-" @#TAG @".png" isDirectory:NO relativeToURL:dir]; \
        [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL]; \
        [(BUFFER) writePNGFileToURL:url error:NULL]; \
    } while (0)
#else
    #define WRITE_TO_FILE(BUFFER, TAG) do {} while (0)
#endif

#define XCTAssertNoError(EXPRESSION, ...) do { \
    NSError * __autoreleasing error; \
    XCTAssert((EXPRESSION), @"error - %@" __VA_ARGS__, error); \
} while (0)

@interface IABufferTests : XCTestCase

@property (nonatomic, nonnull, readonly) NSArray<NSURL *>* imageURLs;

@end

@implementation IABufferTests

- (void)setUp {
    [super setUp];

    NSBundle *bundle = [NSBundle bundleForClass:self.class];

    NSMutableArray<NSURL *> *imageURLs = [NSMutableArray array];

    for (NSUInteger index = 1; ; ++index) {
        NSURL *url = [bundle URLForImageResource:[NSString stringWithFormat:@"test-image-%lu", index]];
        if (!url) break;
        [imageURLs addObject:url];
    }

    _imageURLs = imageURLs;
}

- (void)testInit {
    NSError * __autoreleasing error;

    IABuffer *buffer = [[IABuffer alloc] initWithHeight:16 width:16 bitsPerComponent:8 bitsPerPixel:8 colorSpace:nil error:&error];
    XCTAssertNoError(buffer);
}

- (void)testInitFailureAndErrorReporting {
    NSError * __autoreleasing error = nil;

    NSLog(@"Ignore the following malloc error; it is expected.");
    IABuffer *buffer = [[IABuffer alloc] initWithHeight:~0 width:~0 bitsPerComponent:32 bitsPerPixel:128 colorSpace:nil error:&error];
    XCTAssertNil(buffer, @"Unexpected success in allocating buffer.");

    XCTAssertNotNil(error, @"NSError not allocated.");
    XCTAssertEqual(error.code, -21771, "Expected code to be kvImageMemoryAllocationError.");
    XCTAssertEqualObjects(error.localizedFailureReason, @"There was an error during memory allocation.", @"Failure reason not filled by NSError.");
}

- (void)testInitWithImage {
    id source = CFBridgingRelease(CGImageSourceCreateWithURL((CFURLRef)_imageURLs[0], NULL));
    id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex((CGImageSourceRef)source, 0, NULL));

    IABuffer *buffer;

    XCTAssertNoError(buffer = [[IABuffer alloc] initWithImage:(CGImageRef)image error:&error]);

    XCTAssertEqual(buffer.width, 320);
    XCTAssertEqual(buffer.height, 240);
}

- (void)testExtractAlpha {
    id source = CFBridgingRelease(CGImageSourceCreateWithURL((CFURLRef)_imageURLs[0], NULL));
    id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex((CGImageSourceRef)source, 0, NULL));

    IABuffer *buffer;

    XCTAssertNoError(buffer = [[[IABuffer alloc] initWithImage:(CGImageRef)image error:&error] extractChannel:3 error:&error]);

    uint8_t *row = [buffer getRow:140];
    XCTAssertEqual(row[75], 255);
    row = [buffer getRow:115];
    XCTAssertEqual(row[125], 255);
    row = [buffer getRow:90];
    XCTAssertEqual(row[175], 255);

    WRITE_TO_FILE(buffer, extract-alpha);
}

- (void)testExtractBorderMask {
    CGContextRef context = CGBitmapContextCreate(NULL, 16, 16, 8, 0, [NSColorSpace sRGBColorSpace].CGColorSpace, kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 16, 16));
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(4, 4, 8, 8));
    id image = CFBridgingRelease(CGBitmapContextCreateImage(context));
    CGContextRelease(context);

    IABuffer *buffer;

    XCTAssertNoError(buffer = [[IABuffer alloc] initWithImage:(__bridge CGImageRef)(image) error:&error]);

    for (NSUInteger y = 0; y < 16; ++y) {
        vector_uchar4 *row = [buffer getRow:y];
        for (NSUInteger x = 0; x < 16; ++x) {
            XCTAssertEqual(row[x].w, 255, @"pixel expected to be opaque");
        }
    }

    XCTAssertNoError(buffer = [buffer extractBorderMaskAndReturnError:&error]);

    for (NSUInteger y = 0; y < 16; ++y) {
        uint8_t *row = [buffer getRow:y];
        for (NSUInteger x = 0; x < 16; ++x) {
            if (x >= 4 && x < 12 && y >= 4 && y < 12) {
                XCTAssertEqual(row[x], 255, @"pixel expected to be opaque");
            }
            else {
                XCTAssertEqual(row[x], 0, @"pixel expected to be transparent");
            }
        }
    }
}

- (void)testExtractBorderMaskFuzzy {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CFArrayRef colors = CFArrayCreate(kCFAllocatorDefault, (const void*[]) { CGColorGetConstantColor(kCGColorBlack), CGColorGetConstantColor(kCGColorWhite) }, 2, &kCFTypeArrayCallBacks);
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, colors, NULL);
    CFRelease(colors);

    const NSUInteger size = 256;

    CGContextRef context = CGBitmapContextCreate(NULL, size, size, 8, 0, colorSpace, kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, size, size));
    CGContextDrawRadialGradient(context, gradient, CGPointMake(size/2,size/2), 0, CGPointMake(size/2,size/2), size/2 - 1, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);

    id image = CFBridgingRelease(CGBitmapContextCreateImage(context));
    CGContextRelease(context);

    IABuffer *buffer;

    XCTAssertNoError(buffer = [[[IABuffer alloc] initWithImage:(__bridge CGImageRef)(image) error:&error]
                               extractBorderMaskAndReturnError:&error]);

    WRITE_TO_FILE(buffer, alpha);
}

- (void)testDilate {
    CGContextRef context = CGBitmapContextCreate(NULL, 16, 16, 8, 0, [NSColorSpace sRGBColorSpace].CGColorSpace,
                                                 kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 16, 16));
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(4, 4, 8, 8));
    id image = CFBridgingRelease(CGBitmapContextCreateImage(context));
    CGContextRelease(context);

    IABuffer *buffer;

    XCTAssertNoError(buffer = [[[IABuffer alloc] initWithImage:(__bridge CGImageRef)(image) error:&error]
                               dilateWithKernelSize:NSMakeSize(3, 3) error:&error]);

    vector_uchar4 black = { 0, 0, 0, 255 };
    vector_uchar4 white = { 255, 255, 255, 255 };

    for (NSUInteger y = 0; y < 16; ++y) {
        vector_uchar4 *row = [buffer getRow:y];
        for (NSUInteger x = 0; x < 16; ++x) {
            if (x >= 5 && x < 11 && y >= 5 && y < 11) {
                XCTAssert(vector_all(row[x] == black), @"pixel (%lu, %lu) expected to be black", x, y);
            }
            else {
                XCTAssert(vector_all(row[x] == white), @"pixel (%lu, %lu) expected to be white", x, y);
            }
        }
    }
}

- (void)testErode {
    CGContextRef context = CGBitmapContextCreate(NULL, 16, 16, 8, 0, [NSColorSpace sRGBColorSpace].CGColorSpace,
                                                 kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 16, 16));
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(4, 4, 8, 8));
    id image = CFBridgingRelease(CGBitmapContextCreateImage(context));
    CGContextRelease(context);

    IABuffer *buffer;

    XCTAssertNoError(buffer = [[[IABuffer alloc] initWithImage:(__bridge CGImageRef)(image) error:&error]
                               erodeWithKernelSize:NSMakeSize(3, 3) error:&error]);

    vector_uchar4 black = { 0, 0, 0, 255 };
    vector_uchar4 white = { 255, 255, 255, 255 };

    for (NSUInteger y = 0; y < 16; ++y) {
        vector_uchar4 *row = [buffer getRow:y];
        for (NSUInteger x = 0; x < 16; ++x) {
            if (x >= 3 && x < 13 && y >= 3 && y < 13) {
                XCTAssert(vector_all(row[x] == black), @"pixel (%lu, %lu) expected to be black", x, y);
            }
            else {
                XCTAssert(vector_all(row[x] == white), @"pixel (%lu, %lu) expected to be white", x, y);
            }
        }
    }
}

- (void)testDilateFuzzy {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CFArrayRef colors = CFArrayCreate(kCFAllocatorDefault, (const void*[]) { CGColorGetConstantColor(kCGColorBlack), CGColorGetConstantColor(kCGColorWhite) }, 2, &kCFTypeArrayCallBacks);
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, colors, NULL);
    CFRelease(colors);

    const NSUInteger size = 256;

    CGContextRef context = CGBitmapContextCreate(NULL, size, size, 8, 0, colorSpace, kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, size, size));
    CGContextDrawRadialGradient(context, gradient, CGPointMake(size/2,size/2), 0, CGPointMake(size/2,size/2), size/2 - 1, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);

    id image = CFBridgingRelease(CGBitmapContextCreateImage(context));
    CGContextRelease(context);

    IABuffer *buffer;

    XCTAssertNoError(buffer = [[[IABuffer alloc] initWithImage:(__bridge CGImageRef)(image) error:&error]
                               dilateWithKernelSize:NSMakeSize(32, 32) error:&error]);

    WRITE_TO_FILE(buffer, dilate);
}

- (void)testErodeFuzzy {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CFArrayRef colors = CFArrayCreate(kCFAllocatorDefault, (const void*[]) { CGColorGetConstantColor(kCGColorBlack), CGColorGetConstantColor(kCGColorWhite) }, 2, &kCFTypeArrayCallBacks);
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, colors, NULL);
    CFRelease(colors);

    const NSUInteger size = 256;

    CGContextRef context = CGBitmapContextCreate(NULL, size, size, 8, 0, colorSpace, kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, size, size));
    CGContextDrawRadialGradient(context, gradient, CGPointMake(size/2,size/2), 0, CGPointMake(size/2,size/2), size/2 - 1, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);

    id image = CFBridgingRelease(CGBitmapContextCreateImage(context));
    CGContextRelease(context);

    IABuffer *buffer;

    XCTAssertNoError(buffer = [[[IABuffer alloc] initWithImage:(__bridge CGImageRef)(image) error:&error]
                               erodeWithKernelSize:NSMakeSize(32, 32) error:&error]);

    WRITE_TO_FILE(buffer, erode);
}

- (void)testExtractAndMergePlanes {
    id source = CFBridgingRelease(CGImageSourceCreateWithURL((CFURLRef)_imageURLs[0], NULL));
    id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex((CGImageSourceRef)source, 0, NULL));

    IABuffer *buffer;
    NSArray<IABuffer *> *planes;

    XCTAssertNoError(buffer = [[IABuffer alloc] initWithImage:(CGImageRef)image error:&error]);
    XCTAssertNoError(planes = [buffer extractAllPlanesAndReturnError:&error]);
    XCTAssertEqual(planes.count, 4);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        const vector_uchar4 *row = [buffer getRow:y];
        const uint8_t *rowR = [planes[0] getRow:y];
        const uint8_t *rowG = [planes[1] getRow:y];
        const uint8_t *rowB = [planes[2] getRow:y];
        const uint8_t *rowA = [planes[3] getRow:y];
        for (NSUInteger x = 0; x < buffer.width; ++x) {
            vector_uchar4 pixel = row[x];
            XCTAssertEqual((int)(pixel.x), (int)(rowR[x]));
            XCTAssertEqual((int)(pixel.y), (int)(rowG[x]));
            XCTAssertEqual((int)(pixel.z), (int)(rowB[x]));
            XCTAssertEqual((int)(pixel.w), (int)(rowA[x]));
        }
    }

    WRITE_TO_FILE(planes[0], plane-R);
    WRITE_TO_FILE(planes[1], plane-G);
    WRITE_TO_FILE(planes[2], plane-B);
    WRITE_TO_FILE(planes[3], plane-A);

    IABuffer *merged;

    XCTAssertNoError(merged = [[IABuffer alloc] initWithPlanes:planes error:&error]);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        const vector_uchar4 *expected = [buffer getRow:y];
        const vector_uchar4 *actual   = [merged getRow:y];

        for (NSUInteger x = 0; x < buffer.width; ++x) {
            XCTAssert(vector_all(expected[x] == actual[x]));
        }
    }

    WRITE_TO_FILE(merged, merged);
}

- (void)testExtractBorderMaskPerformance {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CFArrayRef colors = CFArrayCreate(kCFAllocatorDefault, (const void*[]) { CGColorGetConstantColor(kCGColorBlack), CGColorGetConstantColor(kCGColorWhite) }, 2, &kCFTypeArrayCallBacks);
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, colors, NULL);
    CFRelease(colors);

    const NSUInteger size = 256;

    CGContextRef context = CGBitmapContextCreate(NULL, size, size, 8, 0, colorSpace, kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, size, size));
    CGContextDrawRadialGradient(context, gradient, CGPointMake(size/2,size/2), 0, CGPointMake(size/2,size/2), size/2 - 1, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);

    id image = CFBridgingRelease(CGBitmapContextCreateImage(context));
    CGContextRelease(context);

    [self measureMetrics:XCTestCase.defaultPerformanceMetrics automaticallyStartMeasuring:NO forBlock:^{
        IABuffer *buffer = [[IABuffer alloc] initWithImage:(CGImageRef)image error:NULL];
        XCTAssertNotNil(buffer);

        [self startMeasuring];
        XCTAssertNotNil([buffer extractBorderMaskAndReturnError:NULL]);
        [self stopMeasuring];
    }];
}

- (void)testHoughPipeline {
    [_imageURLs enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idx, BOOL *stop) {
        NSError * __autoreleasing error;
        
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        CGImageRef image  = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);

        IABuffer *imageBuffer = [[IABuffer alloc] initWithImage:image error:&error];

        CGImageRelease(image);

        IABuffer *buffer = [imageBuffer extractBorderMaskAndReturnError:&error];
        buffer = [[buffer erodeWithKernelSize:NSMakeSize(3, 3) error:&error] dilateWithKernelSize:NSMakeSize(3, 3) error:&error];
        buffer = [[buffer dilateWithKernelSize:NSMakeSize(3, 3) error:&error] subtractBuffer:buffer error:&error];
        XCTAssertNotNil(buffer, @"error - %@", error);

        NSArray<NSValue *> *segments = [buffer extractSegmentsWithParameters:@{@"sensitivity":@12, @"maxGap":@4, @"minSegmentLength":@15, @"channelWidth":@3} error:&error];
        XCTAssertNotNil(segments, @"error - %@", error);
        NSArray<NSValue *> *regions = [buffer extractRegionsWithParameters:@{@"sensitivity":@12, @"maxGap":@4, @"minSegmentLength":@15, @"channelWidth":@3} error:&error];
        XCTAssertNotNil(regions, @"error - %@", error);

        switch (idx) {
            case 0:
                XCTAssertEqual(segments.count, 12, @"Expected count for %@", url.lastPathComponent);
                XCTAssertEqual(regions.count, 2, @"Expected count for %@", url.lastPathComponent);
                break;

            case 1:
                XCTAssertEqual(segments.count, 16, @"Expected count for %@", url.lastPathComponent);
                XCTAssertEqual(regions.count, 4, @"Expected count for %@", url.lastPathComponent);
                break;

            case 2:
                XCTAssertEqualWithAccuracy(segments.count, 20, 1, @"Expected count for %@", url.lastPathComponent);
                XCTAssertEqual(regions.count, 5, @"Expected count for %@", url.lastPathComponent);
                break;

            case 3:
                XCTAssertEqualWithAccuracy(segments.count, 93, 5, @"Expected count for %@", url.lastPathComponent);
                XCTAssertEqualWithAccuracy(regions.count, 13, 1, @"Expected count for %@", url.lastPathComponent);
                break;

            default:
                NSLog(@"Unknown count expected for %@", url.lastPathComponent);
        }

#ifdef TEST_IMAGE_DIR
        image = [imageBuffer newCGImageAndReturnError:&error];

        CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef context = CGBitmapContextCreate(NULL, CGImageGetWidth(image), CGImageGetHeight(image), 8, 0, colorSpace, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);

        CGContextSetGrayFillColor(context, 1.00, 1.00);
        CGContextAddRect(context, CGRectMake(0, 0, CGBitmapContextGetWidth(context), CGBitmapContextGetHeight(context)));
        CGContextFillPath(context);

        CGContextSetAlpha(context, 0.50);
        CGContextDrawImage(context, CGRectMake(0, 0, CGBitmapContextGetWidth(context), CGBitmapContextGetHeight(context)), image);
        CGContextSetAlpha(context, 1.00);
        CGImageRelease(image);

        CGContextTranslateCTM(context, 0.00, CGBitmapContextGetHeight(context));
        CGContextScaleCTM(context, 1.00, -1.00);

        CGMutablePathRef path = CGPathCreateMutable();

        for (NSValue *value in regions) {
            CGRect region = NSRectToCGRect(value.rectValue);
            CGPathAddRect(path, NULL, region);
        }

        CGContextAddPath(context, path);
        CGContextSetRGBFillColor(context, 0.00, 0.00, 1.00, 0.50);
        CGContextFillPath(context);

        CGContextAddPath(context, path);
        CGContextSetRGBStrokeColor(context, 0.00, 0.00, 1.00, 1.00);
        CGContextStrokePath(context);

        CGPathRelease(path);

        id font = CFBridgingRelease(CTFontCreateWithName(CFSTR("Monaco"), 24.0, (CGAffineTransform[]){CGAffineTransformMakeScale(1, -1)}));

        NSUInteger index = 0;

        for (NSValue *value in regions) {
            CGRect region = NSRectToCGRect(value.rectValue);

            NSAttributedString *aString = [[NSAttributedString alloc] initWithString:@(++index).stringValue attributes:@{(NSString *)kCTFontAttributeName:font, (NSString *)kCTForegroundColorAttributeName:(id)([NSColor greenColor].CGColor)}];
            CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)aString);
            CGRect bounds = CTLineGetImageBounds(line, context);

            CGContextSetTextPosition(context, CGRectGetMinX(region) + 5.0, CGRectGetMinY(region) + CGRectGetHeight(bounds) + 5.0);
            CTLineDraw(line, context);
            CFRelease(line);
        }

        CGContextFillPath(context);

        for (NSValue *value in segments) {
            CGPoint points[2];

            [value getValue:points];

            CGContextAddLines(context, points, 2);
            CGContextAddEllipseInRect(context, CGRectMake(points[0].x - 2, points[0].y - 2, 4, 4));
            CGContextAddEllipseInRect(context, CGRectMake(points[1].x - 2, points[1].y - 2, 4, 4));
        }

        CGContextSetRGBStrokeColor(context, 1.00, 0.00, 0.00, 1.00);
        CGContextStrokePath(context);

        image = CGBitmapContextCreateImage(context);
        CGContextRelease(context);

        NSURL *dir = [NSURL fileURLWithPath:(TEST_IMAGE_DIR).stringByExpandingTildeInPath isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *base = [url.lastPathComponent.stringByDeletingPathExtension stringByAppendingPathExtension:@"png"];
        base = [base stringByReplacingOccurrencesOfString:@"-image-" withString:@"-pipeline-"];

        CFURLRef cfurl = CFBridgingRetain([NSURL fileURLWithPath:base relativeToURL:dir]);
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL(cfurl, kUTTypePNG, 1, NULL);
        CFRelease(cfurl);

        CGImageDestinationAddImage(destination, image, NULL);
        CGImageRelease(image);
        CGImageDestinationFinalize(destination);
        
        CFRelease(destination);
#endif
    }];
}

@end
