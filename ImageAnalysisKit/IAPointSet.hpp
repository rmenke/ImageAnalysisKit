//
//  IAPointSet.hpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/11/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#ifndef IAPointSet_hpp
#define IAPointSet_hpp

#include "IABase.hpp"
#include "IAManagedBuffer.hpp"

#include <vector>

namespace IA {
    class PointSet : public segment_t {
        const managed_buffer<status_t> &buffer;
        std::vector<std::pair<long, long>> points;

        bool valid = false;

    public:
        PointSet(const managed_buffer<status_t> &buffer) : buffer(buffer) { }
        PointSet(const PointSet &) = delete;
        PointSet(PointSet &&r) : segment_t(r), buffer(r.buffer), points(std::move(r.points)), valid(r.valid) {
            r.valid = false;
        }

        ~PointSet() {
            for (const auto &p : points) {
                auto &cell = buffer[p.second][p.first];

                if (cell == status_t::marked_pending) {
                    cell = status_t::pending;
                }
                else if (cell == status_t::marked_voted) {
                    cell = status_t::voted;
                }
            }
        }

        PointSet &operator =(const PointSet &) = delete;
        PointSet &operator =(PointSet &&r) = delete;

        void extend(double x, double y) {
            if (!valid) {
                valid = true;
                this->first = vector2(x, y);
            }
            this->second = vector2(x, y);
        }

        bool empty() const {
            return points.empty();
        }

        decltype(points)::iterator begin() {
            return points.begin();
        }

        decltype(points)::iterator end() {
            return points.end();
        }

        bool add(long x, long y) {
            if (x < 0 || x >= buffer.width) return false;
            if (y < 0 || y >= buffer.height) return false;

            auto &cell = buffer[y][x];

            if (cell == status_t::pending) {
                points.emplace_back(x, y);
                cell = status_t::marked_pending;
                return true;
            }
            if (cell == status_t::voted) {
                points.emplace_back(x, y);
                cell = status_t::marked_voted;
                return true;
            }

            return false;
        }

        void commit() {
            auto begin = points.begin();
            auto end   = points.end();

            while (begin != end) {
                auto &cell = buffer[begin->second][begin->first];

                if (cell == status_t::marked_pending) {
                    cell = status_t::done;
                    *begin = *(--end);
                }
                else if (cell == status_t::marked_voted) {
                    cell = status_t::done;
                    ++begin;
                }
            }
            
            points.erase(end, points.end());
        }
    };
}

#endif /* IAPointSet_hpp */
