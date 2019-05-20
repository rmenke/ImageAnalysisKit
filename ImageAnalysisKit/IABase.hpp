//
//  IABase.hpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/12/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#ifndef IABase_hpp
#define IABase_hpp

#include <CoreFoundation/CoreFoundation.h>

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
     *
     * @field unset The corresponding pixel is below threshold.
     * @field pending The corresponding pixel is above threshold but is still in the queue.
     * @field voted The corresponding pixel has been processed.
     * @field done The corresponding pixel was part of a segment already returned.
     * @field marked_pending The corresponding pixel is still in the queue but is part of a candidate segment.
     * @field marked_voted The corresponding pixel has been processed but is part of a candidate segment.
     */
    enum class status_t : uint32_t {
        unset   = 0xff000000,
        pending = 0xffff0000,
        voted   = 0xff00ff00,
        done    = 0xff0000ff,

        marked_pending = 0xffff00ff,
        marked_voted   = 0xff00ffff
    };

    using segment_t = std::tuple<double, double, double, double>;

    static inline double length_squared(const segment_t &s) {
        double dx = std::get<2>(s) - std::get<0>(s);
        double dy = std::get<3>(s) - std::get<1>(s);
        return dx * dx + dy * dy;
    }

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
