//
//  IASegment.hpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 6/17/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#ifndef IASegment_hpp
#define IASegment_hpp

#include "IABase.hpp"

namespace IA {
    class Segment : public std::pair<point_t, point_t> {
    public:
        double length_squared() const {
            return simd::distance_squared(first, second);
        }

        simd::double2 norm() const {
            return simd::normalize((simd::double2) { second.y - first.y, first.x - second.x });
        }
    };
}

#endif /* IASegment_hpp */
