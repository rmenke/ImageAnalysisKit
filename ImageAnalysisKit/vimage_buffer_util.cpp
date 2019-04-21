//
//  vimage_buffer_util.cpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 4/18/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#include "vimage_buffer_util.h"
#include "cf_util.hpp"

#include <simd/simd.h>

#include <array>
#include <queue>

using pixel_t = simd::float2;

void addAlpha(const vImage_Buffer *buffer, vImagePixelCount x, vImagePixelCount y, float fuzziness) {
    std::queue<std::pair<vImagePixelCount, vImagePixelCount>> queue;

    const auto referencePixel = reinterpret_cast<simd::float4 *>(static_cast<uint8_t *>(buffer->data) + (buffer->rowBytes * y))[x];

    queue.emplace(x, y);

    const auto x_max = buffer->width  - 1;
    const auto y_max = buffer->height - 1;

    auto differenceFromReferencePixel = [referencePixel, fuzziness] (simd::float4 pixel) -> float {
        if (simd::all(referencePixel.xyz == pixel.xyz)) return 0.0;
        if (fuzziness == 0.0) return 1.0;

        return simd::clamp(simd::distance(referencePixel.xyz, pixel.xyz) / fuzziness, 0.0f, 1.0f);
    };

    auto is_open = [&differenceFromReferencePixel] (simd::float4 pixel) -> bool {
        return pixel.w == 1.0f && differenceFromReferencePixel(pixel) < 1.0;
    };

    while (!queue.empty()) {
        std::tie(x, y) = queue.front();
        queue.pop();

        auto row = reinterpret_cast<simd::float4 *>(static_cast<uint8_t *>(buffer->data) + (buffer->rowBytes * y));

        if (!is_open(row[x])) continue;

        vImagePixelCount lo = x, hi = x;

        while (lo > 0 && is_open(row[lo - 1])) --lo;
        while (hi < x_max && is_open(row[hi + 1])) ++hi;

        for (vImagePixelCount i = lo; i <= hi; ++i) {
            row[i].w = differenceFromReferencePixel(row[i]);
        }

        if (y > 0) for (vImagePixelCount i = lo; i <= hi; ++i) {
            queue.emplace(i, y - 1);
        }
        if (y < y_max) for (vImagePixelCount i = lo; i <= hi; ++i) {
            queue.emplace(i, y + 1);
        }
    }
}

// Angles will be measured in binary fractions of brads. This can be adjusted by the constant below.
// Increasing this value increases the startup time and memory held by the trig tables.
// Must be a multiple of four, and preferably a power of two.

constexpr size_t max_theta = 2048;

class trig_data : public std::array<pixel_t, max_theta> {
public:
    trig_data() {
        constexpr float scale = 2.0f / static_cast<float>(max_theta);
        pixel_t * const value = this->data();

        for (auto i = 0; i < max_theta; ++i) {
            float s, c; __sincospif(scale * i, &s, &c);
            value[i] = pixel_t { c, s };
        }
    }
};

static const trig_data trig;
