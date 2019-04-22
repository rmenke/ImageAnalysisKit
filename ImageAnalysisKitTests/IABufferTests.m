//
//  IABufferTests.m
//  ImageAnalysisKit
//
//  Created by Rob Menke on 4/20/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

@import XCTest;
@import ImageAnalysisKit;

#include <inttypes.h>

#ifdef PRODUCE_TEST_IMAGES
    #define WRITE_TO_FILE(BUFFER, TAG) do { \
        [(BUFFER) writePNGFileToURL:[NSURL fileURLWithPath:@("~/Desktop/test-" #TAG ".png").stringByExpandingTildeInPath] error:NULL]; \
    } while (0)
#else
    #define WRITE_TO_FILE(BUFFER, TAG) do {} while (0)
#endif

#define XCTAssertNoError(EXPRESSION, ...) do { \
    NSError * __autoreleasing error; \
    XCTAssert((EXPRESSION), @"%@" __VA_ARGS__, error); \
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

    XCTAssertNoError(buffer = [[[IABuffer alloc] initWithImage:(CGImageRef)image error:&error] extractAlphaChannelAndReturnError:&error]);

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

@end
