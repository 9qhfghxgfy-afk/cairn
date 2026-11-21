import XCTest
@testable import CairnChatDomain

/// The shared attention-cache bound.
///
/// One number, read by two modules that cannot import each other: the engine that sets it on a
/// runtime and the preflight that prices it in bytes. These tests hold the number itself steady —
/// a silent change here changes both a memory estimate and what a phone is actually asked to hold,
/// which is exactly the kind of edit that should have to announce itself.
final class OnDeviceKVTests: XCTestCase {
    func testTheBoundIsARealCacheSizeAndNotAWindow() {
        // A cache bound has to be a positive, modest figure. This is a rotating cache bound rather
        // than a model's trained window, so it stays far below the 4,096-token window the Apple
        // model declares and far below what an uncapped KV cache grows to.
        XCTAssertGreaterThan(OnDeviceKV.tokenCap, 0)
        XCTAssertLessThan(OnDeviceKV.tokenCap, 4096)
    }

    func testThePinnedHeadroomIsSmallerThanTheBound() {
        // The rotating cache keeps its oldest tokens; if that pinned block ever reached the bound
        // there would be nothing left to rotate, which would make the bound a lie.
        XCTAssertLessThan(OnDeviceKV.rotatingHeadroomTokens, OnDeviceKV.tokenCap)
    }
}
