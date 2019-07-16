//
//  IABufferAnalysisTests.m
//  ImageAnalysisKit
//
//  Created by Rob Menke on 5/5/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#import <XCTest/XCTest.h>

#import <simd/simd.h>

#import "IABufferAnalysis.h"
#import "IAPolyline.hpp"
#import "IAScoreboard.hpp"

#include <array>
#include <iostream>
#include <vector>
#include <random>
#include <unordered_set>

static auto urbg = std::default_random_engine{std::random_device{}()};

@interface IABufferAnalysisTests : XCTestCase

@end

@implementation IABufferAnalysisTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testParameters {
    NSArray<NSString *> *names = CFBridgingRelease(IACopyParameterNames());
    XCTAssertEqual(names.count, 4);
}

- (void)testExceptionNoParam {
    CFErrorRef cf_error = NULL;
    vImage_Buffer buffer;

    NSDictionary<NSString *, id> *param = @{};

    NSArray<NSArray<NSNumber *> *> *result = CFBridgingRelease(IACreateSegmentArray(&buffer, (__bridge CFDictionaryRef)param, &cf_error));
    NSError *error  = CFBridgingRelease(cf_error);

    XCTAssertNil(result, @"unexpected result");
    XCTAssertNotNil(error, @"error unset");
    XCTAssertEqualObjects(error.domain, @"GeneralErrorDomain");
}

- (void)testFindZRange {
    simd::double2 p0 { 160, 120 };
    simd::double2 delta { -1, 1 };

    auto z_range = IA::Scoreboard::find_range(320, 240, p0, delta);

    auto p1 = p0 + delta * z_range.first;
    auto p2 = p0 + delta * z_range.second;

    XCTAssertEqualWithAccuracy(p1.x, 280, 1E-6);
    XCTAssertEqualWithAccuracy(p1.y, 0, 1E-6);
    XCTAssertEqualWithAccuracy(p2.x, 40, 1E-6);
    XCTAssertEqualWithAccuracy(p2.y, 240, 1E-6);
}

- (void)testFindZRangeHorizontal {
    simd::double2 p0 { 160, 120 };
    simd::double2 delta { 1, 0 };

    auto z_range = IA::Scoreboard::find_range(320, 240, p0, delta);

    auto p1 = p0 + delta * z_range.first;
    auto p2 = p0 + delta * z_range.second;

    XCTAssertEqualWithAccuracy(p1.x, 0, 1E-6);
    XCTAssertEqualWithAccuracy(p1.y, 120, 1E-6);
    XCTAssertEqualWithAccuracy(p2.x, 320, 1E-6);
    XCTAssertEqualWithAccuracy(p2.y, 120, 1E-6);
}

- (void)testFindZRangeVertical {
    simd::double2 p0 { 160, 120 };
    simd::double2 delta { 0, 1 };

    auto z_range = IA::Scoreboard::find_range(320, 240, p0, delta);

    auto p1 = p0 + delta * z_range.first;
    auto p2 = p0 + delta * z_range.second;

    XCTAssertEqualWithAccuracy(p1.x, 160, 1E-6);
    XCTAssertEqualWithAccuracy(p1.y, 0, 1E-6);
    XCTAssertEqualWithAccuracy(p2.x, 160, 1E-6);
    XCTAssertEqualWithAccuracy(p2.y, 240, 1E-6);
}

- (void)testFindZRangeRandom {
    for (NSUInteger i = 0; i < 10; ++i) {
        simd::double2 p0 { drand48() * 280.0 + 20.0, drand48() * 200.0 + 20.0 };

        double angle = 2.0 * M_PI * drand48();
        simd::double2 delta { cos(angle), sin(angle) };
        delta /= simd::norm_inf(delta);

        auto z_range = IA::Scoreboard::find_range(320, 240, p0, delta);

        auto p1 = p0 + delta * z_range.first;
        auto p2 = p0 + delta * z_range.second;

        auto d1 = simd::min(simd::fabs(p1), simd::fabs(p1 - simd::double2 { 320, 240 }));
        auto d2 = simd::min(simd::fabs(p2), simd::fabs(p2 - simd::double2 { 320, 240 }));

        XCTAssert(d1.x < 1 || d1.y < 1);
        XCTAssert(d2.x < 1 || d2.y < 1);
    }
}

- (void)testHoughSimple1 {
    uint8_t data[16][16] = {
        { },
        { },
        { },
        { 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255 }
    };

    vImage_Buffer buffer = {
        data, 16, 16, 16
    };

    IA::UserParameters param { (__bridge CFDictionaryRef)(@{@"sensitivity":@12, @"maxGap":@3, @"minSegmentLength":@10, @"channelWidth":@3}) };

    for (__unused auto &segment : IA::Scoreboard(&buffer, param)) { }
}

- (void)testHoughSimple2 {
    uint8_t data[16][16] = { };

    for (int i = 0; i < 16; ++i) {
        data[i][i] = 0xff;
    }

    for (int i = 0; i < 7; ++i) {
        data[6-i][i] = 0xff;
        data[15-i][9+i] = 0xff;
    }

    vImage_Buffer buffer = {
        data, 16, 16, 16
    };

    IA::UserParameters param { (__bridge CFDictionaryRef)(@{@"sensitivity":@8, @"maxGap":@4, @"minSegmentLength":@5, @"channelWidth":@3}) };

    for (__unused auto &segment : IA::Scoreboard(&buffer, param)) { }
}

- (void)testHoughRandom {
    uint8_t data[1024][1024] = { };

    auto context = cf::make_managed(CGBitmapContextCreate(data, 1024, 1024, 8, 1024, NSColorSpace.genericGrayColorSpace.CGColorSpace, kCGBitmapByteOrderDefault|kCGImageAlphaNone));
    CGContextSetGrayStrokeColor(context.get(), 1.0, 1.0);

    std::vector<std::pair<CGPoint,CGPoint>> segments(5);

    auto segment_length = [] (const std::pair<CGPoint,CGPoint> &segment) -> double {
        auto a = reinterpret_cast<const simd::double2 &>(segment.first);
        auto b = reinterpret_cast<const simd::double2 &>(segment.second);
        return simd::distance(a, b);
    };

    srand48(time(0));

    for (auto &segment : segments) {
        do {
            std::get<0>(segment).x = drand48() * 1024;
            std::get<0>(segment).y = drand48() * 1024;
            std::get<1>(segment).x = drand48() * 1024;
            std::get<1>(segment).y = drand48() * 1024;
        } while (segment_length(segment) < 50.0);

        CGContextAddLines(context.get(), reinterpret_cast<CGPoint *>(&segment), 2);
    }

    CGContextStrokePath(context.get());
    CGContextFlush(context.get());

    vImage_Buffer buffer {
        .data = data, .height = 1024, .width = 1024, .rowBytes = 1024
    };

    NSDictionary<NSString *, id> *parameters = @{@"maxGap":@8, @"sensitivity":@12, @"minSegmentLength":@5, @"channelWidth":@3};

    CFErrorRef cf_error = nullptr;
    NSArray * _Nullable result = CFBridgingRelease(IACreateSegmentArray(&buffer, (__bridge CFDictionaryRef)(parameters), &cf_error));

    XCTAssertNotNil(result, @"error - %@", CFBridgingRelease(cf_error));

#ifdef TEST_IMAGE_DIR
    context = cf::make_managed(CGBitmapContextCreate(nullptr, 1024, 1024, 8, 0, NSColorSpace.sRGBColorSpace.CGColorSpace, kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedFirst));

    for (auto &segment : segments) {
        const CGPoint *points = reinterpret_cast<const CGPoint *>(&segment);

        CGContextAddLines(context.get(), points, 2);
    }

    CGContextSetLineCap(context.get(), kCGLineCapRound);

    CGContextSetLineWidth(context.get(), 3.0);
    CGContextSetRGBStrokeColor(context.get(), 1.00, 0.00, 0.00, 1.00);
    CGContextStrokePath(context.get());

    for (NSArray<NSNumber *> *seg in result) {
        auto x0 = cf::get<double>((__bridge CFNumberRef)seg[0]);
        auto y0 = 1023 - cf::get<double>((__bridge CFNumberRef)seg[1]);
        auto x1 = cf::get<double>((__bridge CFNumberRef)seg[2]);
        auto y1 = 1023 - cf::get<double>((__bridge CFNumberRef)seg[3]);

        CGContextMoveToPoint(context.get(), x0, y0);
        CGContextAddLineToPoint(context.get(), x1, y1);

        CGContextMoveToPoint(context.get(), x0 - 5.0, y0 - 5.0);
        CGContextAddLineToPoint(context.get(), x0 + 5.0, y0 + 5.0);
        CGContextMoveToPoint(context.get(), x0 - 5.0, y0 + 5.0);
        CGContextAddLineToPoint(context.get(), x0 + 5.0, y0 - 5.0);

        CGContextMoveToPoint(context.get(), x1 - 5.0, y1 - 5.0);
        CGContextAddLineToPoint(context.get(), x1 + 5.0, y1 + 5.0);
        CGContextMoveToPoint(context.get(), x1 - 5.0, y1 + 5.0);
        CGContextAddLineToPoint(context.get(), x1 + 5.0, y1 - 5.0);
    }

    CGContextSetLineWidth(context.get(), 1.0);
    CGContextSetRGBStrokeColor(context.get(), 0.00, 0.00, 1.00, 1.00);
    CGContextStrokePath(context.get());
    CGContextFlush(context.get());

    NSURL *dir = [NSURL fileURLWithPath:(TEST_IMAGE_DIR).stringByExpandingTildeInPath isDirectory:YES];
    NSURL *url = [NSURL fileURLWithPath:@"test-random.png" isDirectory:NO relativeToURL:dir];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL];

    auto image = cf::make_managed(CGBitmapContextCreateImage(context.get()));
    auto dest = cf::make_managed(CGImageDestinationCreateWithURL((CFURLRef)(url), kUTTypePNG, 1, nullptr));
    CGImageDestinationAddImage(dest.get(), image.get(), nullptr);
    CGImageDestinationFinalize(dest.get());
#endif
}

- (void)testFindCorners1 {
    IA::segment_t segments[] = {
        IA::segment_t{0, 0, 10, 0},
        IA::segment_t{0, 0, 0, 10},
        IA::segment_t{0, 10, 10, 10},
        IA::segment_t{10, 10, 10, 0}
    };

    using namespace std;

    shuffle(begin(segments), end(segments), urbg);

    vector<IA::Corner> corners;

    IA::find_corners(begin(segments), end(segments), back_inserter(corners), 1.0);

    XCTAssertEqual(corners.size(), 4);
}

- (void)testFindCorners2 {
    IA::segment_t segments[] = {
        IA::segment_t{0, 0, 10, 0},
        IA::segment_t{0, 0, 0, 10},
        IA::segment_t{10, 10, 10, 0}
    };

    using namespace std;

    shuffle(begin(segments), end(segments), urbg);

    vector<IA::Corner> corners;

    IA::find_corners(begin(segments), end(segments), back_inserter(corners), 1.0);

    XCTAssertEqual(corners.size(), 2);
}

- (void)testFindCorners3 {
    IA::segment_t segments[] = {
        IA::segment_t{0, 0, 10, 0},
        IA::segment_t{10, 0, 10, 5},
        IA::segment_t{0, 0, 0, 10},
        IA::segment_t{0, 10, 5, 10},
        IA::segment_t{5, 5, 5, 10},
        IA::segment_t{5, 5, 10, 5}
    };

    using namespace std;

    shuffle(begin(segments), end(segments), urbg);

    vector<IA::Corner> corners;

    IA::find_corners(begin(segments), end(segments), back_inserter(corners), 1.0);

    XCTAssertEqual(corners.size(), 6);
}

class eq_point {
    const IA::point_t p;

public:
    eq_point(IA::point_t p) : p(p) { }
    eq_point(double x, double y) : eq_point(IA::point_t{x, y}) { }

    bool operator ()(IA::point_t q) const {
        return simd::all(p == q);
    }
};

- (void)testFindPolylines1 {
    IA::segment_t segments[] = {
        IA::segment_t{0, 0, 9, 0},
        IA::segment_t{0, 0, 0, 9},
        IA::segment_t{0, 10, 9, 10},
        IA::segment_t{10, 0, 10, 9}
    };

    using namespace std;

    shuffle(begin(segments), end(segments), urbg);

    vector<IA::Region> regions;

    IA::find_regions(begin(segments), end(segments), back_inserter(regions), 1.0);

    XCTAssertEqual(regions.size(), 1);
    if (regions.size()) {
        XCTAssert(simd::all(regions.front() == simd::double4{0,0,10,10}));
    }
}

- (void)testFindPolylines2 {
    IA::segment_t segments[] = {
        IA::segment_t{0, 0, 10, 0},
        IA::segment_t{0, 0, 0, 10},
        IA::segment_t{10, 10, 10, 0}
    };

    using namespace std;

    shuffle(begin(segments), end(segments), urbg);

    vector<IA::Region> regions;

    IA::find_regions(begin(segments), end(segments), back_inserter(regions), 1.0);

    XCTAssertEqual(regions.size(), 1);
    if (regions.size()) {
        XCTAssert(simd::all(regions.front() == simd::double4{0,0,10,10}));
    }
}

- (void)testFindPolylines3 {
    IA::segment_t segments[] = {
        IA::segment_t{0, 0, 10, 0},
        IA::segment_t{10, 0, 10, 5},
        IA::segment_t{0, 0, 0, 10},
        IA::segment_t{0, 10, 5, 10},
        IA::segment_t{5, 5, 5, 10},
        IA::segment_t{5, 5, 10, 5}
    };

    using namespace std;

    shuffle(begin(segments), end(segments), urbg);

    vector<IA::Region> regions;

    IA::find_regions(begin(segments), end(segments), back_inserter(regions), 1.0);

    XCTAssertEqual(regions.size(), 1);
    if (regions.size()) {
        XCTAssert(simd::all(regions.front() == simd::double4{0,0,10,10}));
    }
}

- (void)testFindPolylines4 {
    IA::segment_t segments[] = {
        IA::segment_t{0, 0, 10, 0},
        IA::segment_t{10, 0, 10, 5},
        IA::segment_t{0, 0, 0, 10},
        IA::segment_t{0, 10, 5, 10},
        IA::segment_t{5, 5, 5, 20},
        IA::segment_t{5, 5, 20, 5},
        IA::segment_t{5, 20, 21, 20},
        IA::segment_t{20, 5, 20, 21}
    };

    using namespace std;

    shuffle(begin(segments), end(segments), urbg);

    vector<IA::Region> regions;

    IA::find_regions(begin(segments), end(segments), back_inserter(regions), 1.0);
    IA::sort_regions(regions.begin(), regions.end());

    XCTAssertEqual(regions.size(), 2);
    if (regions.empty()) return;

    XCTAssert(simd::all(regions[0] == simd::double4{0, 0, 10, 10}));
    XCTAssert(simd::all(regions[1] == simd::double4{5, 5, 15, 15}));
}

@end
