//
//  IABase.hpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/12/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#ifndef IABase_hpp
#define IABase_hpp

#include <simd/simd.h>

#include "cf_util.hpp"

#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <string>

namespace IA {
    using vImage_Error = ssize_t;

    /*!
     * @abstract Status values for the pixels being analyzed.
     */
    enum class status_t : uint32_t {
        unset          = 0xff000000,  ///< Pixel is below threshold.
        pending        = 0xffff0000,  ///< Pixel is above threshold but is still in the queue.
        voted          = 0xff00ff00,  ///< Pixel has been processed.
        done           = 0xff0000ff,  ///< Pixel is part of a segment already returned.
        marked_pending = 0xffff00ff,  ///< Pixel is still in the queue but is part of a candidate segment.
        marked_voted   = 0xff00ffff   ///< Pixel has been processed but is part of a candidate segment.
    };

    using point_t   = simd::double2;
    using segment_t = simd::double4;

#define PARAMS(OP,...)  OP(sensitivity,int) __VA_ARGS__ \
                        OP(maxGap,int) __VA_ARGS__ \
                        OP(minSegmentLength,int) __VA_ARGS__ \
                        OP(channelWidth,short)

#define PARAM_NAME(X,T) CFSTR(#X)
#define PARAM_FIELD(X,T) const T X
#define PARAM_INIT(X,T) X(cf::get<T>(dictionary, CFSTR(#X)))

    struct UserParameters {
        PARAMS(PARAM_FIELD,;);
        UserParameters(CFDictionaryRef dictionary) : PARAMS(PARAM_INIT,,) { }
    };
}

#endif /* IABase_hpp */
