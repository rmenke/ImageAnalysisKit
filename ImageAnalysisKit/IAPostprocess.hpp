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
#include "IASegment.hpp"

namespace IA {
    extern bool fuse(Segment &s, const Segment &t);

    template <class Iterator>
    Iterator postprocess(Iterator _first, Iterator _last) {
        if (_first == _last) return _last;

        bool done = false;

        while (!done) {
            done = true;

            for (auto i = _first; i != _last; ++i) {
                for (auto j = i + 1; j != _last;) {
                    if (fuse(*i, *j)) {
                        --_last;
                        *j = std::move(*_last);
                        done = false;
                    }
                    else {
                        ++j;
                    }
                }

                for (auto j = i + 1; j != _last;) {
                    if (fuse(*j, *i)) {
                        --_last;
                        *i = std::move(*j);
                        *j = std::move(*_last);
                        done = false;
                    }
                    else {
                        ++j;
                    }
                }
            }
        }

        return _last;
    }
}

#endif /* IAPostprocess_hpp */
