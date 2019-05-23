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
        const auto s1 = s.first;
        const auto s2 = s.second;
        const auto t1 = t.first;
        const auto t2 = t.second;

        // Step 1: Verify that t is in the same channel as s.

        const auto d = s2 - s1;
        const auto n = d.yx * simd::double2 { 1.0, -1.0 } / simd::length(d);
        const auto r = simd::dot(n, s1);

        const auto r_lo = r - channel_radius;
        const auto r_hi = r + channel_radius;

        const auto r1 = simd::dot(n, t1);
        if (r1 < r_lo || r1 > r_hi) return false;

        const auto r2 = simd::dot(n, t2);
        if (r2 < r_lo || r2 > r_hi) return false;

        // Step 2: Verify that the projection of t onto s overlaps s.

        auto z0 = simd::dot(d, t1 - s1) / simd::dot(d, d);
        auto z1 = simd::dot(d, t2 - s1) / simd::dot(d, d);

        if (z0 > z1) std::swap(z0, z1);

        if (z1 >= 0 && z0 <= 1.0) {
            // Step 3: The projection overlaps.  Update s.

            if (z0 < 0.0) s.first  = s1 + d * z0;
            if (z1 > 1.0) s.second = s1 + d * z1;

            return true;
        }

        return false;
    }
}
