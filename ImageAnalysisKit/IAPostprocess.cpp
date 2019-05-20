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
    bool in_channel(const segment_t &seg, double theta, double r) {
        const double c = cos(theta), s = sin(theta);

        const double r1 = std::get<0>(seg) * c + std::get<1>(seg) * s;
        if (r1 < r - channel_radius || r1 > r + channel_radius) return false;

        const double r2 = std::get<2>(seg) * c + std::get<3>(seg) * s;
        if (r2 < r - channel_radius || r2 > r + channel_radius) return false;

        return true;
    }

    bool fuse(segment_t &s, const segment_t &t) {
        using namespace std;

        const auto s0 = simd::double2 { get<0>(s), get<1>(s) };
        const auto s1 = simd::double2 { get<2>(s), get<3>(s) };
        const auto sv = s1 - s0;

        const auto t0 = simd::double2 { get<0>(t), get<1>(t) };
        const auto t1 = simd::double2 { get<2>(t), get<3>(t) };

        const auto z0 = simd::dot(sv, t0 - s0) / simd::dot(sv, sv);
        const auto z1 = simd::dot(sv, t1 - s0) / simd::dot(sv, sv);

        if (!(0.0 <= z0 && z0 <= 1.0) && !(0.0 <= z1 && z1 <= 1.0)) {
            // No overlap
            return false;
        }

        double z_lo, z_hi;

        std::tie(z_lo, z_hi) = std::minmax({ 0.0, 1.0, z0, z1 });

        get<0>(s) = (s0 + sv * z_lo).x;
        get<1>(s) = (s0 + sv * z_lo).y;
        get<2>(s) = (s0 + sv * z_hi).x;
        get<3>(s) = (s0 + sv * z_hi).y;

        return true;
    }
}
