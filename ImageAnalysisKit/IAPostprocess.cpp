//
//  IAPostprocess.cpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/16/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#include "IAPostprocess.hpp"

#include <simd/simd.h>

constexpr double channel_width = 5.0;
constexpr double channel_radius = (channel_width - 1) / 2.0;

namespace IA {
    bool in_channel(const point_t p1, const point_t p2, const simd::double2 cs, const double r) {
        const auto r_lo = r - channel_radius;
        const auto r_hi = r + channel_radius;

        const auto r1 = simd::dot(cs, p1);
        if (r1 < r_lo || r1 > r_hi) return false;

        const auto r2 = simd::dot(cs, p2);
        if (r2 < r_lo || r2 > r_hi) return false;

        return true;
    }

    bool fuse(segment_t &s, const segment_t &t) {
        using namespace std;

        const auto s0 = s.first;
        const auto s1 = s.second;
        const auto sv = s1 - s0;

        const auto t0 = t.first;
        const auto t1 = t.second;

        // z0 and z1 are the relative magnitudes of the projection of
        // t0 - s0, t1 - s0 onto s1 - s0.
        const auto z0 = simd::dot(sv, t0 - s0) / simd::dot(sv, sv);
        const auto z1 = simd::dot(sv, t1 - s0) / simd::dot(sv, sv);

        if ((z0 < 0.0 || z0 > 1.0) && (z1 < 0.0 || z1 > 1.0)) {
            return false;
        }

        double z_lo, z_hi;

        std::tie(z_lo, z_hi) = std::minmax({ 0.0, 1.0, z0, z1 });

        s.first  = s0 + sv * z_lo;
        s.second = s0 + sv * z_hi;

        return true;
    }
}
