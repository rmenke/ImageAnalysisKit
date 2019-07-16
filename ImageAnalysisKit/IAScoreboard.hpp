//
//  IAScoreboard.hpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/11/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#ifndef IAScoreboard_hpp
#define IAScoreboard_hpp

#include <simd/simd.h>

#include "IABase.hpp"
#include "IAManagedBuffer.hpp"
#include "IAPointSet.hpp"

#include <cstdint>
#include <random>
#include <tuple>
#include <utility>
#include <vector>

namespace IA {
    class Scoreboard {
        using counter_t  = uint16_t;
        using coord_pair = std::pair<uint16_t, uint16_t>;

        const vImage_Buffer * const image;

        const double rho_scale;

        managed_buffer<status_t> status;
        managed_buffer<counter_t> accumulator;

        const double threshold;
        const double seg_len_2;
        const unsigned short max_gap;
        const unsigned short channel_radius;

        std::vector<coord_pair> queue;
        std::default_random_engine rng { std::random_device{}() };

        unsigned voted = 0;

        bool vote(const double x, const double y, vImagePixelCount &theta, vImagePixelCount &rho);
        void unvote(const double x, const double y);

        bool next_segment(segment_t &segment);

    public:
        Scoreboard(const vImage_Buffer *image, const double threshold, const double seg_len_2, const double diagonal, const unsigned short max_gap, const unsigned short channel_radius);

        Scoreboard(const vImage_Buffer *image, const UserParameters &param) : Scoreboard(image, param.sensitivity * -M_LN10, param.minSegmentLength * param.minSegmentLength, std::ceil(std::hypot(image->width, image->height)), std::max(param.maxGap, 0), ((std::max<short>(param.channelWidth, 3) - 1) >> 1)) { }

        static std::pair<double, double> find_range(vImagePixelCount width, vImagePixelCount height, simd::double2 p0, simd::double2 delta);

        std::vector<PointSet> scan_channel(vImagePixelCount theta, double rho) const;

        struct iterator {
            using difference_type   = std::ptrdiff_t;
            using value_type        = segment_t;
            using pointer           = const value_type *;
            using reference         = const value_type &;
            using iterator_category = std::input_iterator_tag;

        private:
            Scoreboard *sb;
            value_type current;

            std::default_random_engine rng { std::random_device{}() };

            void load_next() {
                if (!sb) return;
                if (!sb->next_segment(current)) sb = nullptr;
            }

        public:
            iterator(Scoreboard *sb = nullptr) : sb(sb) {
                load_next();
            }

            iterator(const iterator &) = default;
            iterator(iterator &&) = default;

            iterator &operator =(const iterator &) = default;
            iterator &operator =(iterator &&) = default;

            reference operator *() const {
                return current;
            }

            pointer operator ->() const {
                return &current;
            }

            bool operator ==(const iterator &rhs) const {
                return sb == rhs.sb;
            }

            bool operator !=(const iterator &rhs) const {
                return !operator ==(rhs);
            }

            iterator &operator ++() {
                load_next();
                return *this;
            }

            iterator operator ++(int) {
                iterator copy; copy.current = current;
                operator ++();
                return copy;
            }
        };

        iterator begin() {
            return iterator(this);
        }

        iterator end() {
            return iterator();
        }
    };
} // namespace IA

#endif /* IAScoreboard_hpp */
