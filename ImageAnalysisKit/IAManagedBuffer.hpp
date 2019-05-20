//
//  IAManagedBuffer.hpp
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/11/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#ifndef IAManagedBuffer_hpp
#define IAManagedBuffer_hpp

#include <Accelerate/Accelerate.h>

#include "IABase.hpp"

namespace IA {
    class VImageException : public std::runtime_error {
        vImage_Error error;

    public:
        VImageException(vImage_Error error) : runtime_error("vImage_Error = " + std::to_string(error)), error(error) { }

        vImage_Error code() const {
            return error;
        }
    };
    
    template <class Pixel>
    struct managed_buffer : vImage_Buffer {
        managed_buffer(vImagePixelCount height, vImagePixelCount width) {
            vImage_Error error = vImageBuffer_Init(this, height, width, sizeof(Pixel) * 8, kvImageNoFlags);
            if (error != kvImageNoError) throw VImageException(error);
        }

        managed_buffer(const managed_buffer &r) = delete;
        managed_buffer(managed_buffer &&r) = delete;

        managed_buffer &operator =(const managed_buffer &r) = delete;
        managed_buffer &operator =(managed_buffer &&r) = delete;

        ~managed_buffer() {
            free(data);
        }

        Pixel *operator [](vImagePixelCount y) const {
            return reinterpret_cast<Pixel *>(static_cast<uint8_t *>(data) + rowBytes * y);
        }
    };
}

#endif /* IAManagedBuffer_hpp */
