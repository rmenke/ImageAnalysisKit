//
//  IAPostprocess.cpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/16/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#include "IAPostprocess.hpp"

constexpr double channel_width = 3.0;
constexpr double channel_radius = (channel_width - 1) / 2.0;

namespace IA {
    bool fuse(segment_t &s, const segment_t &t) {
        // Step 1: Verify that t is in the same channel as s.

        const auto v = s.second - s.first;
        const auto n = s.norm();
        const auto r = simd::dot(n, s.first);

        const auto r_lo = r - channel_radius;
        const auto r_hi = r + channel_radius;

        const auto r1 = simd::dot(n, t.first);
        if (r1 < r_lo || r1 > r_hi) return false;

        const auto r2 = simd::dot(n, t.second);
        if (r2 < r_lo || r2 > r_hi) return false;

        // Step 2: Verify that the projection of t onto s overlaps s.

        const auto l = s.length_squared();

        auto z0 = simd::dot(v, t.first - s.first) / l;
        auto z1 = simd::dot(v, t.second - s.first) / l;

        if (z0 > z1) std::swap(z0, z1);

        if (z1 >= 0 && z0 <= 1.0) {
            // Step 3: The projection overlaps.  Update s.

            if (z1 > 1.0) s.second = s.first + v * z1;
            if (z0 < 0.0) s.first  = s.first + v * z0;

            return true;
        }

        return false;
    }
}
