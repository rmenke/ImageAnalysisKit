//
//  IABuffer.h
//  ImageAnalysisKit
//
//  Created by Rob Menke on 4/20/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

@import Foundation;
@import AppKit.NSColor;
@import simd;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ImageAnalysisKitErrorDomain;

@interface IABuffer : NSObject

@property (nonatomic, readonly) NSUInteger height, width;

- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithHeight:(NSUInteger)height width:(NSUInteger)width
                       bitsPerComponent:(NSUInteger)bitsPerComponent
                           bitsPerPixel:(NSUInteger)bitsPerPixel
                             colorSpace:(nullable NSColorSpace *)colorSpace
                                  error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithImage:(CGImageRef)image error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error;

- (nullable instancetype)initWithPlanes:(NSArray<IABuffer *> *)planes error:(NSError **)error;

- (nullable IABuffer *)flattenAgainstColor:(NSColor *)color error:(NSError **)error;

- (nullable IABuffer *)dilateWithKernelSize:(NSSize)kernelSize error:(NSError **)error;
- (nullable IABuffer *)erodeWithKernelSize:(NSSize)kernelSize error:(NSError **)error;

- (nullable IABuffer *)subtractBuffer:(IABuffer *)buffer error:(NSError **)error;

- (nullable IABuffer *)extractChannel:(NSUInteger)channel error:(NSError **)error;

- (nullable IABuffer *)extractBorderMaskWithROI:(NSRect)ROI error:(NSError **)error;
- (nullable IABuffer *)extractBorderMaskWithFuzziness:(float)fuzziness ROI:(NSRect)ROI error:(NSError **)error;

- (nullable NSArray<IABuffer *> *)extractAllPlanesAndReturnError:(NSError **)error;

- (nullable NSArray<NSValue *> *)extractSegmentsWithParameters:(NSDictionary<NSString *, id> *)parameters error:(NSError **)error;
- (nullable NSArray<NSValue *> *)extractRegionsWithParameters:(NSDictionary<NSString *, id> *)parameters error:(NSError **)error;

- (nullable CGImageRef)newCGImageAndReturnError:(NSError **)error;
- (BOOL)writePNGFileToURL:(NSURL *)url error:(NSError **)error;

- (void *)getRow:(NSUInteger)row NS_RETURNS_INNER_POINTER;

@end

NS_ASSUME_NONNULL_END
