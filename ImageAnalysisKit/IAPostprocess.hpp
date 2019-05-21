//
//  IAPostprocess.hpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/16/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#ifndef IAPostprocess_hpp
#define IAPostprocess_hpp

#include "IABase.hpp"

namespace IA {
    extern bool in_channel(point_t p1, point_t p2, simd::double2 cossin, double r);
    extern bool fuse(segment_t &s, const segment_t &t);

    template <class Iterator>
    Iterator _postprocess(Iterator _first, Iterator _last, std::bidirectional_iterator_tag) {
        using namespace std;

        bool not_done = true;

        const auto start = _first;

        while (not_done) {
            not_done = false;

            for (auto i = _first; i != _last; ++i) {
                auto delta = i->second - i->first;

                // Rather than calculating the angle then taking the cosine and sine of it, normalize the delta and rotate it.
                const auto cossin = delta.yx * simd::double2 { 1.0, -1.0 } / simd::length(delta);
                const auto r = simd::dot(cossin, i->first);

                for (auto j = i; j != _first; --j) {
                    auto &segment = *(j-1);

                    if (in_channel(segment.first, segment.second, cossin, r) && fuse(*i, segment)) {
                        *(j++) = std::move(*(_first++));
                        not_done = true;
                    }
                }

                for (auto j = i + 1; j != _last; ++j) {
                    auto &segment = *j;

                    if (in_channel(segment.first, segment.second, cossin, r) && fuse(*i, segment)) {
                        *(j--) = std::move(*(--_last));
                        not_done = true;
                    }
                }
            }
        }

        while (_first != start) {
            *(_first--) = std::move(*(--_last));
        }

        return _last;
    }

    template <class Iterator>
    Iterator postprocess(Iterator begin, Iterator end) {
        return _postprocess(begin, end, typename std::iterator_traits<Iterator>::iterator_category());
    }
}

#endif /* IAPostprocess_hpp */
