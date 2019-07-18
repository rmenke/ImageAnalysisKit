//
//  IABufferAnalysis.h
//  ImageAnalysisKit
//
//  Created by Rob Menke on 4/18/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#import <CoreFoundation/CoreFoundation.h>
#import <Accelerate/Accelerate.h>

CF_ASSUME_NONNULL_BEGIN
CF_EXTERN_C_BEGIN

#ifndef __cplusplus
#define _NOEXCEPT
#endif

/*!
 * @abstract Attempt to create an alpha channel through flood fill.
 * @param buffer The vImage buffer to work on.  This should be a floating-point four-channel buffer in the L*a*b* color space, with the last channel as the alpha and the range of a* and b* being {-127 ... +127}.
 * @param x The x coordinate of the start of the flood fill.
 * @param y The y coordinate of the start of the flood fill.
 * @param fuzziness Colors within this distance from the initial pixel
 *   color will be made partially transparent.
 */
void IAAddAlphaToBuffer(const vImage_Buffer *buffer, vImagePixelCount x, vImagePixelCount y, float fuzziness) _NOEXCEPT;

/*!
 * @abstract Get the names of the known parameters.
 * @return A CFArrayRef of CFStringRef objects.
 */
CFArrayRef IACopyParameterNames() _NOEXCEPT;

/*!
 * @abstract Use PPHT to find line segments in an image.
 * @discussion The image is assumed to be in Planar8 format.
 * @param buffer The buffer to analyze.
 * @param parameters A @c CFDictionary of parameters. The keys should be @c CFStringRef objects and the values should be @c CFTypeRef objects. The key names returned by IACopyParameterNames() must be present or the function will fail.
 * @param error If not @c NULL and an error occurs, will be filled with the error information.
 * @return A CFArrayRef of CFArrayRefs of four CFNumberRefs.
 */
CFArrayRef _Nullable IACreateSegmentArray(const vImage_Buffer *buffer, CFDictionaryRef parameters, CFErrorRef *error) _NOEXCEPT;

/*!
 * @abstract Use PPHT to find convex regions in an image.
 * @discussion The image is assumed to be in Planar8 format.
 * @param buffer The buffer to analyze.
 * @param parameters A @c CFDictionary of parameters. The keys should be @c CFStringRef objects and the values should be @c CFTypeRef objects. The key names returned by IACopyParameterNames() must be present or the function will fail.
 * @param error If not @c NULL and an error occurs, will be filled with the error information.
 * @return A CFArrayRef of CFArrayRefs of four CFNumberRefs: x, y, width, height.
 */
CFArrayRef _Nullable IACreateRegionArray(const vImage_Buffer *buffer, CFDictionaryRef parameters, CFErrorRef *error) _NOEXCEPT;

CF_EXTERN_C_END
CF_ASSUME_NONNULL_END

