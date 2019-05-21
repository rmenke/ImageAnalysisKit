//
//  IAScoreboard.cpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/11/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#include "IAScoreboard.hpp"
#include "IASegment.hpp"

#include <array>
#include <set>

namespace IA {
    // Angles will be measured in binary fractions of brads. This can be
    // adjusted by the constant below.  Increasing this value increases
    // the startup time and memory held by the trig tables.  Must be a
    // power of two.

    constexpr vImagePixelCount max_theta = 2048;

    struct TrigData : std::array<simd::double2, max_theta> {
        TrigData() {
            constexpr double scale = 2.0f / static_cast<double>(max_theta);
            simd::double2 * const value = this->data();

            for (auto i = 0; i < max_theta; ++i) {
                double s, c;
                __sincospi(scale * i, &s, &c);
                value[i] = simd::double2 { c, s };
            }
        }
    };

    static const TrigData trig;

    Scoreboard::Scoreboard(const vImage_Buffer *image, const double threshold, const double seg_len_2, const double diagonal, const unsigned short max_gap, const unsigned short channel_radius)
    : image(image), rho_scale(std::exp2(std::round(std::log2(max_theta) - std::log2(diagonal)))), status(image->height, image->width), accumulator(std::ceil(rho_scale * diagonal), max_theta), threshold(threshold), seg_len_2(seg_len_2), max_gap(max_gap), channel_radius(channel_radius) {
        constexpr auto max = std::numeric_limits<uint16_t>::max();
        if (image->width > max || image->height > max) {
            throw VImageException(kvImageInvalidImageFormat);
        }

        for (vImagePixelCount y = 0; y < image->height; ++y) {
            const uint8_t * const src = static_cast<const uint8_t *>(image->data) + image->rowBytes * y;
            status_t * const dst = status[y];

            for (vImagePixelCount x = 0; x < image->width; ++x) {
                if (src[x] >= 128U) {
                    queue.emplace_back(x, y);
                    dst[x] = status_t::pending;
                }
                else {
                    dst[x] = status_t::unset;
                }
            }
        }

        memset(accumulator.data, 0, accumulator.height * accumulator.rowBytes);
    }

    bool Scoreboard::vote(const double x, const double y, vImagePixelCount &thetaOut, vImagePixelCount &rhoOut) {
        const simd::double2 point { x, y };

        vImagePixelCount theta, rho;

        // Use a fixed-size buffer rather than a vector
        // because we are going to be resizing it frequently
        // and we know the maximum capacity.

        std::array<std::pair<uint16_t, uint16_t>, max_theta> peaks;

        auto const begin = peaks.begin();
        auto end = begin;

        counter_t n = 0;

        for (theta = 0; theta < max_theta; ++theta) {
            assert(end < peaks.end());

            auto r = simd::dot(point, trig[theta]);
            if (r < 0) continue;

            rho = std::lround(r * rho_scale);
            if (rho >= accumulator.height) continue;

            auto &count = accumulator[rho][theta];

            ++count;

            if (n < count) {
                end = begin;
                n = count;
            }
            if (n == count) {
                *(end++) = std::make_pair(theta, rho);
            }
        }

        // There are maxTheta * maxRho cells in the register.
        // Each vote will increment maxTheta of these cells, one
        // per column.
        //
        // Assuming the null hypothesis (the image is random noise),
        // E[n] = votes/maxRho for all cells in the register.

        const double lambda = static_cast<double>(++voted) / accumulator.height;

        // For the null hypothesis, the cells are filled (roughly)
        // according to a Poisson model:
        //
        //    p(n) = λⁿ/n!·exp(-λ)
        //         = λⁿ/Γ(n+1)·exp(-λ)
        // ln p(n) = n·ln(λ) - lnΓ(n+1) - λ

        const double lnp = n * std::log(lambda) - std::lgamma(n + 1) - lambda;

        // lnp is the (log) probability that a bin that was filled
        // randomly would contain a count of n. If the probability
        // is above the significance threshold, we assume that the
        // bin was filled by noise and tell the caller we did not
        // find a segment.

        if (lnp >= threshold) return false;

        // We have rejected the null hypothesis.

        ptrdiff_t index = std::uniform_int_distribution<ptrdiff_t>(0, (end - begin) - 1)(rng);

        std::tie(thetaOut, rhoOut) = begin[index];

        return true;
    }

    void Scoreboard::unvote(const double x, const double y) {
        const simd::double2 point { x, y };

        vImagePixelCount theta, rho;

        for (theta = 0; theta < max_theta; ++theta) {
            auto r = simd::dot(point, trig[theta]);
            if (r < 0) continue;

            rho = std::lround(r * rho_scale);
            if (rho >= accumulator.height) continue;

            auto &count = accumulator[rho][theta];

            assert(count > 0);

            --count;
        }

        --voted;
    }

    std::pair<double, double> Scoreboard::find_range(vImagePixelCount width, vImagePixelCount height, simd::double2 p0, simd::double2 delta) {
        simd::double4 bounds { 0, 0, static_cast<double>(width), static_cast<double>(height) };

        // This calculates the intercepts in parallel.
        // Some of the z values may be infinite -- this means that the
        // channel is parallel to a boundary edge.

        auto z = (bounds - vector4(p0, p0)) / vector4(delta, delta);

        std::pair<double, double> range { +INFINITY, -INFINITY };

        for (int i = 0; i < 4; ++i) {
            if (isfinite(z[i])) {
                const auto p = p0 + delta * z[i];

                // If the intercept point is within the bounds of the
                // buffer, then update the range.

                if (simd::all(bounds.s01 <= p && p <= bounds.s23)) {
                    if (range.first  > z[i]) range.first  = z[i];
                    if (range.second < z[i]) range.second = z[i];
                }
            }
        }

        range.first = std::floor(range.first);
        range.second = std::ceil(range.second);

        return range;
    }
    
    std::vector<Segment> Scoreboard::scan_channel(vImagePixelCount theta, double rho) const {
        const simd::double2 norm  = trig[theta];
        const simd::double2 p0    = rho * trig[theta];
        const simd::double2 delta = simd::double2 { -1, +1 } * norm.yx / simd::norm_inf(norm);

        auto z_range = find_range(status.width, status.height, p0, delta);

        std::vector<Segment> segments;
        segments.emplace_back(status);

        long gap = std::numeric_limits<long>::min();

        struct __vec_less {
            bool operator ()(simd::double2 a, simd::double2 b) const {
                if (a.x < b.x) return true;
                if (a.x > b.x) return false;
                return a.y < b.y;
            }
        };

        std::set<simd::double2, __vec_less> points;

        for (int c = -channel_radius; c <= channel_radius; ++c) {
            points.insert(norm * c);
        }

        for (double z = z_range.first; z <= z_range.second; z += 1) {
            Segment &current = segments.back();

            const auto p = p0 + delta * z;

            bool hit = false;

            for (const auto &q : points) {
                const auto r = vector_long(simd::rint(p + q));
                if (current.add(r.x, r.y)) hit = true;
            }

            if (hit) {
                current.extend(p.x, p.y);
                gap = 0;
            }
            else {
                ++gap;

                if (gap >= max_gap && !current.empty()) {
                    segments.emplace_back(status);
                }
            }
        }

        if (segments.back().empty()) {
            segments.pop_back();
        }

        return segments;
    }

    bool Scoreboard::next_segment(segment_t &segment) {
        auto const q_begin = queue.begin();
        auto q_end         = queue.end();

        while (q_end != q_begin) {
            // Exchange a random element with the last element
            auto iter = q_begin + std::uniform_int_distribution<std::size_t>(0, (q_end - q_begin - 1))(rng);

            uint16_t x = iter->first;
            uint16_t y = iter->second;

            *iter = *(--q_end);

            status_t &cell = status[y][x];
            if (cell != status_t::pending) continue;

            cell = status_t::voted;

            vImagePixelCount theta, rho;

            if (vote(x, y, theta, rho)) {
                auto segments = scan_channel(theta, rho / rho_scale);
                if (segments.empty()) continue;

                auto shorter = [] (const Segment &a, const Segment &b) {
                    return length_squared(a) < length_squared(b);
                };

                auto longest = std::max_element(segments.begin(), segments.end(), shorter);

                longest->commit();

                for (const auto &p : *longest) {
                    unvote(p.first, p.second);
                }

                segment = *longest;

                if (length_squared(segment) >= seg_len_2) {
                    queue.erase(q_end, queue.end());
                    return true;
                }
            }
        }

        queue.clear();

        return false;
    }
}
