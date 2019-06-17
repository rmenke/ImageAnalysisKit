//
//  IABufferAnalysis.cpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 4/18/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#include "IABufferAnalysis.h"
#include "IAScoreboard.hpp"
#include "IAPostprocess.hpp"

#include "cf_util.hpp"

#include <simd/simd.h>

#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>

#include <array>
#include <iterator>
#include <queue>
#include <random>
#include <set>

#define RECORD_HOUGH 1

const CFStringRef kCFImageAnalysisKitErrorDomain = CFSTR("ImageAnalysisKitErrorDomain");

void IAAddAlphaToBuffer(const vImage_Buffer *buffer, vImagePixelCount x, vImagePixelCount y, float fuzziness) noexcept {
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

CFArrayRef IACopyParameterNames() noexcept {
    static CFTypeRef values[] = { PARAMS(PARAM_NAME,,) };
    constexpr CFIndex numValues = std::extent<decltype(values)>::value;
    return CFArrayCreate(kCFAllocatorDefault, values, numValues, &kCFTypeArrayCallBacks);
}

#define SET_ERROR(X) if (error) *error = (X)

CFArrayRef _Nullable IACreateSegmentArray(const vImage_Buffer *buffer, CFDictionaryRef parameters, CFErrorRef *error) noexcept {
    try {
        const IA::UserParameters param { parameters };

        CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

        IA::Scoreboard scoreboard{buffer, param};

        std::vector<IA::Segment> segments;
        std::copy(scoreboard.begin(), scoreboard.end(), std::back_inserter(segments));

        segments.erase(IA::postprocess(segments.begin(), segments.end()), segments.end());

        for (const auto &segment : segments) {
            auto x0 = cf::number(segment.first.x);
            auto y0 = cf::number(segment.first.y);
            auto x1 = cf::number(segment.second.x);
            auto y1 = cf::number(segment.second.y);

            auto s = cf::array(x0, y0, x1, y1);

            CFArrayAppendValue(result, s.get());
        }

        return result;
    }
    catch (const IA::VImageException &ex) {
        SET_ERROR(CFErrorCreate(kCFAllocatorDefault, kCFImageAnalysisKitErrorDomain, ex.code(), NULL));
        return nullptr;
    }
    catch (const std::system_error &ex) {
        SET_ERROR(cf::system_error(ex));
        return nullptr;
    }
    catch (const std::exception &ex) {
        SET_ERROR(cf::error(ex));
        return nullptr;
    }
    catch (...) {
        SET_ERROR(cf::error());
        return nullptr;
    }
}
