//
//  IAPolyline.hpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 6/23/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#ifndef IAPolyline_hpp
#define IAPolyline_hpp

#include "IASegment.hpp"

#include <deque>
#include <vector>

namespace IA {
    /*!
     * @abstract Find the intersection point of two line segments.
     *
     * @param s1 The first segment.
     * @param s2 The second segment.
     *
     * @return The intersection point of the lines coinciding with the segments.  If the segments are parallel, this solution will contain Infinity.
     */
    static inline point_t intersection(const Segment &s1, const Segment &s2) {
        auto a = s1.first;
        auto b = s1.second;
        auto c = s2.first;
        auto d = s2.second;

        const auto t = (b - a);
        const auto u = (d - c);

        const auto v = t.yx * u;

        if (v.x == v.y) {   // segments are parallel or coincident.
            return {INFINITY, INFINITY};
        }

        auto p = t.yx * a;
        p = (p.y - p.x) * u;

        auto q = u.yx * c;
        q = (q.y - q.x) * t;

        return (p - q) / (v.y - v.x);
    }

    static inline point_t farthest(point_t p, const Segment &s) {
        const auto d1 = simd::distance_squared(p, s.first);
        const auto d2 = simd::distance_squared(p, s.second);
        return d1 > d2 ? s.first : s.second;
    }

    class Corner {
    public:
        const Segment *s1, *s2;
        point_t a, b, c;

        Corner(const Segment *s1, point_t p, const Segment *s2) : s1(s1), s2(s2), a(farthest(p, *s1)), b(p), c(farthest(p, *s2)) { }

        bool operator ==(const Corner &rhs) const {
            return s1 == rhs.s1 && s2 == rhs.s2;
        }

        bool operator !=(const Corner &rhs) const {
            return !operator ==(rhs);
        }
    };

    using Region = simd::double4;

    static inline Region make_region(point_t min, point_t max) {
        Region region;

        region.lo = min;
        region.hi = max - min;

        return region;
    }

    template <class FwdIterator, class OutputIterator>
    void find_corners(FwdIterator _begin, FwdIterator _end, OutputIterator _out, double max_gap) {
        const double max_gap_squared = max_gap * max_gap;

        for (auto i = _begin; i != _end; ++i) {
            auto &s1 = *i;

            for (auto j = i + 1; j != _end; ++j) {
                auto &s2 = *j;

                const auto p = intersection(s1, s2);

                point_t a, b;

                double d1 = simd::distance_squared(p, s1.first);
                double d2 = simd::distance_squared(p, s1.second);

                if (d1 < d2) {
                    if (d1 > max_gap_squared) continue;
                    a = s1.second;
                }
                else {
                    if (d2 > max_gap_squared) continue;
                    a = s1.first;
                }

                d1 = simd::distance_squared(p, s2.first);
                d2 = simd::distance_squared(p, s2.second);

                if (d1 < d2) {
                    if (d1 > max_gap_squared) continue;
                    b = s2.second;
                }
                else {
                    if (d2 > max_gap_squared) continue;
                    b = s2.first;
                }

                // Determine the orientation of the corner by examining the cross product of the two vectors relative to their intersection.  If the sine is not positive, reverse the ordering.
                const auto sine_between = simd::cross(b - p, a - p).z;

                *_out = (sine_between > 0.0) ? Corner(&s1, p, &s2) : Corner(&s2, p, &s1);
                ++_out;
            }
        }
    }

    template <class FwdIterator, class OutputIterator>
    FwdIterator find_next_region(FwdIterator _begin, FwdIterator _end, OutputIterator _out) {
        using namespace std;

        if (_begin == _end) return _end;

        swap(*_begin, *(--_end));

        // A polyline is a sequence of Corner objects such that for all 0 < n < polyline.size(), std::get<0>(polyline[n-1]) == std::get<2>(polyline[n]).  Assuming that the corners are oriented the same way, the polyline is convex.

        deque<Corner> polyline;
        polyline.push_back(*_end);

        // Prepend corners to head (convex polygon)
        for (auto iter = _begin; iter != _end;) {
            auto *s1 = polyline.front().s1;
            auto *s2 = iter->s2;

            if (s1 == s2) {
                swap(*iter, *(--_end));
                polyline.push_front(*_end);
                iter = _begin;
            }
            else {
                ++iter;
            }
        }

        // Append corners to tail (convex polygon)
        for (auto iter = _begin; iter != _end;) {
            auto s1 = polyline.back().s2;
            auto s2 = iter->s1;

            if (s1 == s2) {
                swap(*iter, *(--_end));
                polyline.push_back(*_end);
                iter = _begin;
            }
            else {
                ++iter;
            }
        }

        if (polyline.size() == 1) {
            // Empty polyline, try again...
            return find_next_region(_begin, _end, _out);
        }

        // If the polyline is not a polygon, then we need to include the initial and terminal points from the initial and terminal segments.
        const bool is_open = (polyline.front().s1 != polyline.back().s2);

        Region r;

        if (is_open) {
            r.lo = r.hi = polyline.front().a;
        }
        else {
            r = Region{+INFINITY, +INFINITY, -INFINITY, -INFINITY};
        }

        for (const auto &corner : polyline) {
            r.lo = simd::min(corner.b, r.lo);
            r.hi = simd::max(corner.b, r.hi);
        }

        if (is_open) {
            const auto point = polyline.back().c;
            r.lo = simd::min(point, r.lo);
            r.hi = simd::max(point, r.hi);
        }

        r.hi -= r.lo;  // (x_min, y_min, x_max, y_max) => (x, y, w, h)

        *_out = r;
        ++_out;

        return _end;
    }

    template <class FwdIterator, class OutputIterator>
    void find_regions(FwdIterator _begin, FwdIterator _end, OutputIterator _out, double max_gap) {
        std::vector<Corner> corners;

        find_corners(_begin, _end, std::back_inserter(corners), max_gap);

        auto begin = corners.begin();
        auto end   = corners.end();

        while (begin != end) {
            end = find_next_region(begin, end, _out);
        }
    }

    static inline double vertical_overlap(Region a, Region b) {
        auto inter = simd::double2 {
            std::max(a.s0, b.s0),
            std::min(a.s0 + a.s2, b.s0 + b.s2)
        };

        inter.s1 -= inter.s0;

        return std::max(inter.s1 / a.s2, inter.s1 / b.s2);
    }

    static inline bool region_earlier(Region r1, Region r2) {
        const auto c1 = r1.lo + r1.hi / 2.0;
        const auto c2 = r2.lo + r2.hi / 2.0;

        if (vertical_overlap(r1, r2) >= 0.8) {
            return c1.x < c2.x;
        }
        else {
            return c1.y < c2.y;
        }
    }

    /*!
     * @abstract Sort the regions according to the usual reading order.
     *
     * @discussion This algorithm currently assumes a left-to-right, top-to-bottom reading order.  It works by partitioning the regions into logical rows, then sorting each row by its horizontal position, with special logic for regions that have the same horizontal coordinate.
     *
     * @tparam RandomAccessIterator A class representing a random-access iterator.  This class is not checked for conformance.
     *
     * @param _begin The starting iterator.
     *
     * @param _end The ending iterator.
     */
    template <class RandomAccessIterator>
    void sort_regions(RandomAccessIterator _begin, RandomAccessIterator _end) {
        while (_begin != _end) {
            // Find the region nearest to the top edge. If there is more than one with the same distance, find the one nearest to the left edge.
            auto min = std::min_element(_begin, _end, [] (Region a, Region b) {
                if (a.y < b.y) return true;
                if (a.y > b.y) return false;
                return a.x < b.x;
            });

            std::swap(*_begin, *min);

            // Separate the remaining regions by those that vertically overlap the first region by 50% and those that do not overlap.
            auto _mid = std::partition(_begin + 1, _end, [ry = _begin->y, rh = _begin->s3] (Region s) {
                const double sy = s.y;
                const double sh = s.s3;

                const auto min = std::max(ry, sy);
                const auto max = std::min(ry + rh, sy + sh);

                // (max - min) / rh is the fraction of vertical overlap between the two regions.  If this value is non-positive, there is no overlap.  Return true only if there is 50% or greater overlap.
                return (max - min) >= (0.5 * rh);
            });

            // Everything in [_begin, _mid) belongs to the same logical row.  Sort them by their horizontal position first, then if there are any ties, by the vertical position.  This usually (but not always) produces the correct reading order.
            std::sort(_begin, _mid, [] (Region a, Region b) {
                if (a.x < b.x) return true;
                if (a.x > b.x) return false;
                return a.y < b.y;
            });

            _begin = _mid;
        }
    }
}

#endif /* IAPolyline_hpp */
