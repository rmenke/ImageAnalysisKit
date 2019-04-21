//
//  vimage_buffer_util.h
//  ImageAnalysisKit
//
//  Created by Rob Menke on 4/18/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#ifndef vimage_buffer_util_h
#define vimage_buffer_util_h

#import <CoreFoundation/CoreFoundation.h>
#import <Accelerate/Accelerate.h>

CF_ASSUME_NONNULL_BEGIN
CF_EXTERN_C_BEGIN

/*!
 * @abstract Attempt to create an alpha channel through flood fill.
 *
 * @param buffer The vImage buffer to work on.  This should be a
 *   floating-point four-channel buffer in the L*a*b* color space,
 *   with the last channel as the alpha and the range of a* and b*
 *   being {-127 ... +127}.
 *
 * @param x The x coordinate of the start of the flood fill.
 *
 * @param y The y coordinate of the start of the flood fill.
 *
 * @param fuzziness Colors within this distance will be made partially
 *   transparent.
 */

void addAlpha(const vImage_Buffer * _Nonnull buffer, vImagePixelCount x, vImagePixelCount y, float fuzziness);

CF_EXTERN_C_END
CF_ASSUME_NONNULL_END

#endif
