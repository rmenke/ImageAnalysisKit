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
    extern bool in_channel(const segment_t &, double theta, double r);
    extern bool fuse(segment_t &s, const segment_t &t);

    template <class Iterator>
    Iterator _postprocess(Iterator _first, Iterator _last, std::bidirectional_iterator_tag) {
        using namespace std;

        bool not_done = true;

        const auto start = _first;

        while (not_done) {
            not_done = false;

            for (auto i = _first; i != _last; ++i) {
                // This is not wrong -- arctan(-∆x/∆y) is the angle of inclination for the normal.
                const auto theta = atan2(get<0>(*i) - get<2>(*i), get<3>(*i) - get<1>(*i));
                const auto r = get<0>(*i) * cos(theta) + get<1>(*i) * sin(theta);

                for (auto j = i; j != _first; --j) {
                    auto &segment = *(j-1);

                    if (in_channel(segment, theta, r) && fuse(*i, segment)) {
                        *(j++) = std::move(*(_first++));
                        not_done = true;
                    }
                }

                for (auto j = i + 1; j != _last; ++j) {
                    auto &segment = *j;

                    if (in_channel(segment, theta, r) && fuse(*i, segment)) {
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
