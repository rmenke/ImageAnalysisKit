//
//  IABuffer.m
//  ImageAnalysisKit
//
//  Created by Rob Menke on 4/20/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#import "IABuffer.h"

#include "IABufferAnalysis.h"

@import Accelerate.vImage;
@import AppKit.NSColorSpace;

@implementation NSColorSpace (LabColorSpace)

+ (nullable instancetype)LabColorSpaceWithWhitePoint:(const CGFloat *)whitePoint
                                          blackPoint:(const CGFloat *)blackPoint
                                               range:(const CGFloat *)range {
    CGColorSpaceRef labColorSpace = CGColorSpaceCreateLab(whitePoint, blackPoint, range);
    NSColorSpace *instance = [[NSColorSpace alloc] initWithCGColorSpace:labColorSpace];
    CGColorSpaceRelease(labColorSpace);
    return instance;
}

@end

@implementation IABuffer {
    vImage_Buffer buffer;
    vImage_CGImageFormat format;
}

NSString * const ImageAnalysisKitErrorDomain = @"ImageAnalysisKitErrorDomain";

+ (void)initialize {
    [NSError setUserInfoValueProviderForDomain:ImageAnalysisKitErrorDomain provider:^id (NSError *err, NSString *userInfoKey) {
        if ([NSLocalizedFailureReasonErrorKey isEqualToString:userInfoKey]) {
            switch (err.code) {
                case kvImageNoError:
                    return @"No error";
                case kvImageRoiLargerThanInputBuffer:
                    return @"The ROI was larger than input buffer.";
                case kvImageInvalidKernelSize:
                    return @"The kernel size was invalid.";
                case kvImageInvalidEdgeStyle:
                    return @"The edge style was invalid.";
                case kvImageInvalidOffset_X:
                    return @"The X offset was invalid.";
                case kvImageInvalidOffset_Y:
                    return @"The Y offset was invalid.";
                case kvImageMemoryAllocationError:
                    return @"There was an error during memory allocation.";
                case kvImageNullPointerArgument:
                    return @"A null pointer was supplied as an argument.";
                case kvImageInvalidParameter:
                    return @"A parameter was invalid.";
                case kvImageBufferSizeMismatch:
                    return @"The buffer sizes did not match.";
                case kvImageUnknownFlagsBit:
                    return @"An unknown flag was set.";
                case kvImageInternalError:
                    return @"An internal error occurred.";
                case kvImageInvalidRowBytes:
                    return @"The row bytes count was invalid.";
                case kvImageInvalidImageFormat:
                    return @"The image format was invalid.";
                case kvImageColorSyncIsAbsent:
                    return @"ColorSync is not available.";
                case kvImageOutOfPlaceOperationRequired:
                    return @"An out-of-place operation was required, but the operation requested it to be done in place.";
                case kvImageInvalidImageObject:
                    return @"The image object was invalid.";
                case kvImageInvalidCVImageFormat:
                    return @"The CVImage format was invalid.";
                case kvImageUnsupportedConversion:
                    return @"The requested conversion is not supported.";
                case kvImageCoreVideoIsAbsent:
                    return @"CoreVideo is not available.";
            }
        }

        return nil;
    }];
}

- (instancetype)initWithHeight:(NSUInteger)height width:(NSUInteger)width
              bitsPerComponent:(NSUInteger)bitsPerComponent
                  bitsPerPixel:(NSUInteger)bitsPerPixel
                    colorSpace:(nullable NSColorSpace *)colorSpace
                         error:(NSError **)error {
    self = [super init];

    if (self) {
        format.bitsPerComponent = (uint32_t)bitsPerComponent;
        format.bitsPerPixel = (uint32_t)bitsPerPixel;
        format.colorSpace = CGColorSpaceRetain(colorSpace.CGColorSpace);

        if (bitsPerComponent == 8) {
            if (bitsPerPixel == 32) {
                format.bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaLast;
            }
            else if (bitsPerPixel == 8) {
                format.bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNone;
            }
            else {
                if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageInvalidParameter userInfo:nil];
                return NO;
            }
        }
        else if (bitsPerComponent == 32) {
            if (bitsPerPixel == 128) {
                format.bitmapInfo = kCGBitmapByteOrder32Host | kCGBitmapFloatComponents | kCGImageAlphaLast;
            }
            else if (bitsPerPixel == 32) {
                format.bitmapInfo = kCGBitmapByteOrder32Host | kCGBitmapFloatComponents | kCGImageAlphaNone;
            }
            else {
                if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageInvalidParameter userInfo:nil];
                return NO;
            }
        }
        else {
            if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageInvalidParameter userInfo:nil];
            return NO;
        }

        format.version = 0;
        format.decode = NULL;
        format.renderingIntent = kCGRenderingIntentPerceptual;

        vImage_Error code = vImageBuffer_Init(&buffer, height, width, (uint32_t)bitsPerPixel, kvImageNoFlags);

        if (code != kvImageNoError) {
            if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
            return nil;
        }
    }

    return self;
}

- (instancetype)initWithImage:(CGImageRef)image error:(NSError **)error {
    self = [super init];

    if (self) {
        buffer.data = NULL;

        format.bitsPerComponent = 8;
        format.bitsPerPixel = 32;
        format.colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        format.bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaLast;
        format.version = 0;
        format.decode = NULL;
        format.renderingIntent = kCGRenderingIntentPerceptual;

        vImage_Error code = vImageBuffer_InitWithCGImage(&buffer, &format, NULL, image, kvImageNoFlags);

        if (code != kvImageNoError) {
            if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
            return nil;
        }
    }

    return self;
}

- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data) return nil;

    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    if (!source) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:kPOSIXErrorEFTYPE userInfo:nil];
        return nil;
    }

    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);

    self = [self initWithImage:image error:error];

    CGImageRelease(image);

    return self;
}

- (instancetype)initWithPlanes:(NSArray<IABuffer *> *)planes error:(NSError **)error {
    NSParameterAssert(planes.count == 4);

    vImagePixelCount height = planes[0]->buffer.height;
    vImagePixelCount width  = planes[0]->buffer.width;
    vImagePixelCount bitsPerComponent = planes[0]->format.bitsPerComponent;

    __block NSError *_error = nil;

    if (planes[0]->format.bitsPerPixel != planes[0]->format.bitsPerComponent) {
        _error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageInvalidImageFormat userInfo:nil];
        return nil;
    }
    if (planes[1]->format.bitsPerPixel != planes[1]->format.bitsPerComponent || planes[1]->format.bitsPerComponent != bitsPerComponent) {
        _error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageInvalidImageFormat userInfo:nil];
        return nil;
    }
    if (planes[1]->buffer.height != height || planes[1]->buffer.width != width) {
        _error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageBufferSizeMismatch userInfo:nil];
        return nil;
    }
    if (planes[2]->format.bitsPerPixel != planes[2]->format.bitsPerComponent || planes[2]->format.bitsPerComponent != bitsPerComponent) {
        _error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageInvalidImageFormat userInfo:nil];
        return nil;
    }
    if (planes[2]->buffer.height != height || planes[2]->buffer.width != width) {
        _error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageBufferSizeMismatch userInfo:nil];
        return nil;
    }
    if (planes[3]->format.bitsPerPixel != planes[3]->format.bitsPerComponent || planes[3]->format.bitsPerComponent != bitsPerComponent) {
        _error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageInvalidImageFormat userInfo:nil];
        return nil;
    }
    if (planes[3]->buffer.height != height || planes[3]->buffer.width != width) {
        _error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageBufferSizeMismatch userInfo:nil];
        return nil;
    }

    self = [self initWithHeight:height width:width bitsPerComponent:bitsPerComponent bitsPerPixel:(4 * bitsPerComponent) colorSpace:[NSColorSpace sRGBColorSpace] error:error];

    if (self) {
        vImage_Error (*vImageConvert)(const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, vImage_Flags);

        if (format.bitsPerComponent == 8) {
            vImageConvert = vImageConvert_Planar8toARGB8888;
        }
        else {
            NSAssert(format.bitsPerComponent == 32, @"Unsupported image type");
            vImageConvert = vImageConvert_PlanarFtoARGBFFFF;
        }

        vImage_Error code = vImageConvert(&(planes[0]->buffer), &(planes[1]->buffer), &(planes[2]->buffer), &(planes[3]->buffer), &buffer, kvImageNoFlags);

        if (code != kvImageNoError) {
            if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
            return nil;
        }
    }

    return self;
}

- (void)dealloc {
    CGColorSpaceRelease(format.colorSpace);
    free(buffer.data);
}

- (IABuffer *)flattenAgainstColor:(NSColor *)color error:(NSError **)error {
    NSColorSpace *colorSpace = [[NSColorSpace alloc] initWithCGColorSpace:format.colorSpace];

    IABuffer *result = [[IABuffer alloc] initWithHeight:buffer.height
                                                  width:buffer.width
                                       bitsPerComponent:format.bitsPerComponent
                                           bitsPerPixel:format.bitsPerPixel
                                             colorSpace:colorSpace
                                                  error:error];

    result->format.bitmapInfo &= ~kCGBitmapAlphaInfoMask;
    result->format.bitmapInfo |= kCGImageAlphaNoneSkipLast;

    color = [color colorUsingColorSpace:colorSpace];
    NSAssert(color.numberOfComponents <= 4, @"Too many color components in target color space.");

    CGFloat backgroundColor[4];
    [color getComponents:backgroundColor];

    vImage_Error code;

    vImageConverterRef converter = vImageConverter_CreateWithCGImageFormat(&format, &result->format, backgroundColor, kvImageNoFlags, &code);

    if (!converter) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
        return nil;
    }

    code = vImageConvert_AnyToAny(converter, &buffer, &result->buffer, NULL, kvImageNoFlags);

    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
        return nil;
    }

    CFRelease(converter);

    return result;
}

- (IABuffer *)dilateWithKernelSize:(NSSize)kernelSize error:(NSError **)error {
    IABuffer *result = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width
                                       bitsPerComponent:format.bitsPerComponent bitsPerPixel:format.bitsPerPixel
                                             colorSpace:[[NSColorSpace alloc] initWithCGColorSpace:format.colorSpace]
                                                  error:error];
    if (!result) return nil;

    vImage_Error (*vImageMax)(const vImage_Buffer *, const vImage_Buffer *,
                              void *, vImagePixelCount, vImagePixelCount,
                              vImagePixelCount, vImagePixelCount, vImage_Flags);

    if (format.bitsPerComponent == 8) {
        if (format.bitsPerPixel == 8) {
            vImageMax = vImageMax_Planar8;
        }
        else {
            assert(format.bitsPerPixel == 32);
            vImageMax = vImageMax_ARGB8888;
        }
    } else {
        if (format.bitsPerPixel == 32) {
            vImageMax = vImageMax_PlanarF;
        }
        else {
            assert(format.bitsPerPixel == 128);
            vImageMax = vImageMax_ARGBFFFF;
        }
    }

    vImage_Error code = vImageMax(&buffer, &(result->buffer), NULL, 0, 0, kernelSize.height, kernelSize.width, kvImageNoFlags);

    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
        return nil;
    }

    return result;
}

- (IABuffer *)erodeWithKernelSize:(NSSize)kernelSize error:(NSError **)error {
    IABuffer *result = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width
                                       bitsPerComponent:format.bitsPerComponent bitsPerPixel:format.bitsPerPixel
                                             colorSpace:[[NSColorSpace alloc] initWithCGColorSpace:format.colorSpace]
                                                  error:error];
    if (!result) return nil;

    vImage_Error (*vImageMin)(const vImage_Buffer *, const vImage_Buffer *,
                              void *, vImagePixelCount, vImagePixelCount,
                              vImagePixelCount, vImagePixelCount, vImage_Flags);

    if (format.bitsPerComponent == 8) {
        if (format.bitsPerPixel == 8) {
            vImageMin = vImageMin_Planar8;
        }
        else {
            NSAssert(format.bitsPerPixel == 32, @"Unsupported image type");
            vImageMin = vImageMin_ARGB8888;
        }
    } else {
        if (format.bitsPerPixel == 32) {
            vImageMin = vImageMin_PlanarF;
        }
        else {
            NSAssert(format.bitsPerPixel == 128, @"Unsupported image type");
            vImageMin = vImageMin_ARGBFFFF;
        }
    }

    vImage_Error code = vImageMin(&buffer, &(result->buffer), NULL, 0, 0, kernelSize.height, kernelSize.width, kvImageNoFlags);

    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
        return nil;
    }

    return result;
}

- (IABuffer *)subtractBuffer:(IABuffer *)subtrahend error:(NSError **)error {
    if (format.bitsPerPixel != 8 || subtrahend->format.bitsPerPixel != 8) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageInvalidImageFormat
                                            userInfo:@{NSLocalizedDescriptionKey:@"Only 8-bit images supported for subtraction operation."}];
        return nil;
    }

    if (buffer.width != subtrahend->buffer.width || buffer.height != subtrahend->buffer.height) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain
                                                code:kvImageBufferSizeMismatch userInfo:nil];
        return nil;
    }

    IABuffer *result = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width
                                       bitsPerComponent:format.bitsPerComponent bitsPerPixel:format.bitsPerPixel
                                             colorSpace:[[NSColorSpace alloc] initWithCGColorSpace:format.colorSpace]
                                                  error:error];
    if (!result) return nil;

    const NSUInteger row_width = (buffer.width + 15) >> 4;

    const vImage_Buffer *a = &buffer;
    const vImage_Buffer *b = &subtrahend->buffer;
    const vImage_Buffer *d = &result->buffer;

    dispatch_apply(buffer.height, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t y) {
        const vector_uchar16 *srcA = a->data + a->rowBytes * y;
        const vector_uchar16 *srcB = b->data + b->rowBytes * y;
        vector_uchar16 *dst        = d->data + d->rowBytes * y;
        vector_uchar16 *const end  = dst + row_width;

        do {
            *dst = *srcA - *srcB;
        } while (++srcA, ++srcB, ++dst < end);
    });

    return result;
}

- (nullable IABuffer *)extractChannel:(NSUInteger)channel error:(NSError **)error {
    if (format.bitsPerComponent * 4 != format.bitsPerPixel) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:kvImageInvalidParameter userInfo:nil];
    }

    IABuffer *result = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width bitsPerComponent:format.bitsPerComponent bitsPerPixel:format.bitsPerComponent colorSpace:[NSColorSpace genericGrayColorSpace] error:error];
    if (!result) return nil;

    vImage_Error (*vImageExtractChannel)(const vImage_Buffer *, const vImage_Buffer *, long, vImage_Flags) =
        (format.bitsPerPixel == 32) ? vImageExtractChannel_ARGB8888 : vImageExtractChannel_ARGBFFFF;

    vImage_Error code = vImageExtractChannel(&buffer, &(result->buffer), channel, kvImageNoFlags);

    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
        return nil;
    }

    return result;
}

- (nullable IABuffer *)extractBorderMaskWithROI:(NSRect)ROI error:(NSError * _Nullable __autoreleasing *)error {
    return [self extractBorderMaskWithFuzziness:13.7f ROI:ROI error:error];
}

- (nullable IABuffer *)extractBorderMaskWithFuzziness:(float)fuzziness ROI:(NSRect)ROI error:(NSError * _Nullable __autoreleasing *)error {
    CGFloat whitePoint[] = { 0.95047, 1.0, 1.08883 };
    CGFloat blackPoint[] = { 0, 0, 0 };
    CGFloat range[] = { -127, 127, -127, 127 };

    NSColorSpace *LabColorSpace = [NSColorSpace LabColorSpaceWithWhitePoint:whitePoint blackPoint:blackPoint range:range];
    NSAssert(LabColorSpace, @"Unable to create L*a*b* color space");

    IABuffer *labBuffer = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width
                                          bitsPerComponent:32 bitsPerPixel:128
                                                colorSpace:LabColorSpace error:error];
    if (!labBuffer) return nil;

    vImage_Error code;
    vImageConverterRef converter = vImageConverter_CreateWithCGImageFormat(&format, &(labBuffer->format), NULL, kvImageNoFlags, &code);

    if (converter == NULL) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
        return nil;
    }

    code = vImageConvert_AnyToAny(converter, &buffer, &(labBuffer->buffer), NULL, kvImageNoFlags);

    CFRelease(converter);

    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
        return nil;
    }

    CFErrorRef cferror = NULL;
    if (!IAAddAlphaBorderToBuffer(&(labBuffer->buffer), ROI, &cferror)) {
        if (error) *error = CFBridgingRelease(cferror);
        return nil;
    }

    vImagePixelCount minX = CGRectGetMinX(ROI);
    vImagePixelCount minY = CGRectGetMinY(ROI);
    vImagePixelCount maxX = CGRectGetMaxX(ROI) - 1;
    vImagePixelCount maxY = CGRectGetMaxY(ROI) - 1;

    IAAddAlphaToBuffer(&(labBuffer->buffer), minX, minY, fuzziness);
    IAAddAlphaToBuffer(&(labBuffer->buffer), maxX, minY, fuzziness);
    IAAddAlphaToBuffer(&(labBuffer->buffer), minX, maxY, fuzziness);
    IAAddAlphaToBuffer(&(labBuffer->buffer), maxX, maxY, fuzziness);

    IABuffer *alphaBuffer = [labBuffer extractChannel:3 error:error];
    if (!alphaBuffer) return nil;

    if (format.bitsPerComponent == 32) return alphaBuffer;

    IABuffer *maskBuffer = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width
                                           bitsPerComponent:8 bitsPerPixel:8
                                                 colorSpace:[NSColorSpace genericGrayColorSpace] error:error];
    if (!maskBuffer) return nil;

    code = vImageConvert_PlanarFtoPlanar8(&(alphaBuffer->buffer), &(maskBuffer->buffer), 1.0f, 0.0f, kvImageNoFlags);

    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
        return nil;
    }

    return maskBuffer;
}

- (NSArray<IABuffer *> *)extractAllPlanesAndReturnError:(NSError **)error {
    vImage_Error code;

    NSColorSpace *genericGrayColorSpace = [NSColorSpace genericGrayColorSpace];

    IABuffer *bufferA = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width bitsPerComponent:format.bitsPerComponent bitsPerPixel:format.bitsPerComponent colorSpace:genericGrayColorSpace error:error];
    if (!bufferA) return nil;

    IABuffer *bufferR = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width bitsPerComponent:format.bitsPerComponent bitsPerPixel:format.bitsPerComponent colorSpace:genericGrayColorSpace error:error];
    if (!bufferR) return nil;

    IABuffer *bufferG = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width bitsPerComponent:format.bitsPerComponent bitsPerPixel:format.bitsPerComponent colorSpace:genericGrayColorSpace error:error];
    if (!bufferG) return nil;

    IABuffer *bufferB = [[IABuffer alloc] initWithHeight:buffer.height width:buffer.width bitsPerComponent:format.bitsPerComponent bitsPerPixel:format.bitsPerComponent colorSpace:genericGrayColorSpace error:error];
    if (!bufferB) return nil;

    vImage_Error (*vImageConvert)(const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, vImage_Flags);

    if (format.bitsPerComponent == 8) {
        vImageConvert = vImageConvert_ARGB8888toPlanar8;
    }
    else {
        NSAssert(format.bitsPerComponent == 32, @"Unsupported image type");
        vImageConvert = vImageConvert_ARGBFFFFtoPlanarF;
    }

    code = vImageConvert(&buffer, &(bufferA->buffer), &(bufferR->buffer), &(bufferG->buffer), &(bufferB->buffer), kvImageNoFlags);

    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];
        return nil;
    }

    return @[bufferA, bufferR, bufferG, bufferB];
}

- (NSArray<NSValue *> *)extractSegmentsWithParameters:(NSDictionary<NSString *,id> *)parameters error:(NSError **)error {
    CFErrorRef cfError;
    NSArray<NSArray<NSNumber *> *> *segments = CFBridgingRelease(IACreateSegmentArray(&buffer, (__bridge CFDictionaryRef)(parameters), error ? &cfError : NULL));
    if (!segments) {
        if (error) *error = CFBridgingRelease(cfError);
        return nil;
    }

    NSMutableArray<NSValue *> *result = [NSMutableArray arrayWithCapacity:segments.count];

    for (NSArray<NSNumber *> *segment in segments) {
        CGPoint s[2];

        s[0].x = segment[0].doubleValue;
        s[0].y = segment[1].doubleValue;
        s[1].x = segment[2].doubleValue;
        s[1].y = segment[3].doubleValue;

        [result addObject:[NSValue valueWithBytes:s objCType:@encode(CGPoint[2])]];
    }

    return result;
}

- (NSArray<NSValue *> *)extractRegionsWithParameters:(NSDictionary<NSString *,id> *)parameters error:(NSError **)error {
    CFErrorRef cfError;
    NSArray<NSArray<NSNumber *> *> *regions = CFBridgingRelease(IACreateRegionArray(&buffer, (__bridge CFDictionaryRef)(parameters), error ? &cfError : NULL));
    if (!regions) {
        if (error) *error = CFBridgingRelease(cfError);
        return nil;
    }

    NSMutableArray<NSValue *> *result = [NSMutableArray arrayWithCapacity:regions.count];

    for (NSArray<NSNumber *> *region in regions) {
        double x = region[0].doubleValue;
        double y = region[1].doubleValue;
        double w = region[2].doubleValue;
        double h = region[3].doubleValue;

        [result addObject:[NSValue valueWithRect:NSMakeRect(x, y, w, h)]];
    }

    return result;
}

- (CGImageRef)newCGImageAndReturnError:(NSError **)error {
    vImage_Error code = kvImageNoError;

    CGImageRef image = vImageCreateCGImageFromBuffer(&buffer, &format, NULL, NULL, kvImageNoFlags, &code);
    if (image == NULL && error) *error = [NSError errorWithDomain:ImageAnalysisKitErrorDomain code:code userInfo:nil];

    return image;
}

- (BOOL)writePNGFileToURL:(NSURL *)url error:(NSError **)error {
    id image = CFBridgingRelease([self newCGImageAndReturnError:error]);
    if (!image) return NO;

    id destination = CFBridgingRelease(CGImageDestinationCreateWithURL((CFURLRef)url, kUTTypePNG, 1, NULL));
    NSAssert(destination != nil, @"Unable to create image destination");

    CGImageDestinationAddImage((CGImageDestinationRef)destination, (CGImageRef)image, NULL);
    CGImageDestinationFinalize((CGImageDestinationRef)destination);

    return YES;
}

- (NSUInteger)height {
    return buffer.height;
}

- (NSUInteger)width {
    return buffer.width;
}

- (void *)getRow:(NSUInteger)row {
    NSParameterAssert(row < buffer.height);
    return buffer.data + (buffer.rowBytes * row);
}

@end
