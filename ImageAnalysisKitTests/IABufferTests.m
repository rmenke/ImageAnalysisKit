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
    
    XCTAssertNotNil(buffer, @"%@", error);
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
    NSError * __autoreleasing error;

    id source = CFBridgingRelease(CGImageSourceCreateWithURL((CFURLRef)_imageURLs[0], NULL));
    id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex((CGImageSourceRef)source, 0, NULL));

    IABuffer *buffer = [[IABuffer alloc] initWithImage:(CGImageRef)image error:&error];

    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertEqual(buffer.width, 320);
    XCTAssertEqual(buffer.height, 240);
}

- (void)testExtractAlpha {
    NSError * __autoreleasing error;

    id source = CFBridgingRelease(CGImageSourceCreateWithURL((CFURLRef)_imageURLs[0], NULL));
    id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex((CGImageSourceRef)source, 0, NULL));

    IABuffer *buffer;

    buffer = [[[IABuffer alloc] initWithImage:(CGImageRef)image error:&error] extractAlphaChannelAndReturnError:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    uint8_t *row = [buffer getRow:140];
    XCTAssertEqual(row[75], 255);
    row = [buffer getRow:115];
    XCTAssertEqual(row[125], 255);
    row = [buffer getRow:90];
    XCTAssertEqual(row[175], 255);

    WRITE_TO_FILE(buffer, extract-alpha);
}

- (void)testExtractBorderMask {
    NSError * __autoreleasing error;

    CGContextRef context = CGBitmapContextCreate(NULL, 16, 16, 8, 0, [NSColorSpace sRGBColorSpace].CGColorSpace, kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 16, 16));
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(4, 4, 8, 8));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

    IABuffer *buffer = [[IABuffer alloc] initWithImage:image error:&error];

    CGImageRelease(image);

    XCTAssertNotNil(buffer, @"%@", error);
    
    for (NSUInteger y = 0; y < 16; ++y) {
        vector_uchar4 *row = [buffer getRow:y];
        for (NSUInteger x = 0; x < 16; ++x) {
            XCTAssertEqual(row[x].w, 255, @"pixel expected to be opaque");
        }
    }

    XCTAssertNotNil(buffer = [buffer extractBorderMaskAndReturnError:&error], @"%@", error);

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
    NSError * __autoreleasing error;

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

    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

    IABuffer *buffer = [[IABuffer alloc] initWithImage:image error:&error];

    CGImageRelease(image);

    XCTAssertNotNil(buffer = [buffer extractBorderMaskAndReturnError:&error], @"%@", error);

    WRITE_TO_FILE(buffer, alpha);
}

- (void)testDilate {
    NSError * __autoreleasing error;

    CGContextRef context = CGBitmapContextCreate(NULL, 16, 16, 8, 0, [NSColorSpace sRGBColorSpace].CGColorSpace,
                                                 kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 16, 16));
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(4, 4, 8, 8));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

    IABuffer *buffer = [[IABuffer alloc] initWithImage:image error:&error];

    CGImageRelease(image);

    XCTAssertNotNil(buffer = [buffer dilateWithKernelSize:NSMakeSize(3, 3) error:&error], @"%@", error);

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
    NSError * __autoreleasing error;

    CGContextRef context = CGBitmapContextCreate(NULL, 16, 16, 8, 0, [NSColorSpace sRGBColorSpace].CGColorSpace,
                                                 kCGBitmapByteOrder32Host|kCGImageAlphaPremultipliedFirst);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 16, 16));
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(4, 4, 8, 8));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

    IABuffer *buffer = [[IABuffer alloc] initWithImage:image error:&error];

    CGImageRelease(image);

    XCTAssertNotNil(buffer = [buffer erodeWithKernelSize:NSMakeSize(3, 3) error:&error], @"%@", error);

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
    NSError * __autoreleasing error;

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

    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

    IABuffer *buffer = [[IABuffer alloc] initWithImage:image error:&error];

    CGImageRelease(image);

    XCTAssertNotNil(buffer = [buffer dilateWithKernelSize:NSMakeSize(32, 32) error:&error], @"%@", error);

    WRITE_TO_FILE(buffer, dilate);
}

- (void)testErodeFuzzy {
    NSError * __autoreleasing error;

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

    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

    IABuffer *buffer = [[IABuffer alloc] initWithImage:image error:&error];

    CGImageRelease(image);

    XCTAssertNotNil(buffer = [buffer erodeWithKernelSize:NSMakeSize(32, 32) error:&error], @"%@", error);

    WRITE_TO_FILE(buffer, erode);
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
