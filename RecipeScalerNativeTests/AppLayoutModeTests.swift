//
//  AppLayoutModeTests.swift
//
//  Spec 081 (T008) — the layout mode depends only on idiom and horizontal size class.
//

import SwiftUI
import UIKit
import XCTest
@testable import RecipeScalerNative

final class AppLayoutModeTests: XCTestCase {

    func testPhoneIdiomIsAlwaysPhone() {
        for sizeClass: UserInterfaceSizeClass? in [.regular, .compact, nil] {
            XCTAssertEqual(
                AppLayoutMode.resolve(idiom: .phone, horizontalSizeClass: sizeClass),
                .phone,
                "phone idiom, size class \(String(describing: sizeClass))"
            )
        }
    }

    func testPadCompactIsPhone() {
        XCTAssertEqual(AppLayoutMode.resolve(idiom: .pad, horizontalSizeClass: .compact), .phone)
        XCTAssertEqual(AppLayoutMode.resolve(idiom: .pad, horizontalSizeClass: nil), .phone)
    }

    func testPadRegularIsPadRegular() {
        XCTAssertEqual(AppLayoutMode.resolve(idiom: .pad, horizontalSizeClass: .regular), .padRegular)
    }

    /// Mac, Vision Pro and other idioms are out of scope and keep the phone layout.
    func testOtherIdiomsArePhone() {
        for idiom: UIUserInterfaceIdiom in [.unspecified, .tv, .carPlay, .mac, .vision] {
            XCTAssertEqual(AppLayoutMode.resolve(idiom: idiom, horizontalSizeClass: .regular), .phone, "\(idiom)")
        }
    }

    func testEnvironmentDefaultsToPhone() {
        XCTAssertEqual(EnvironmentValues().appLayoutMode, .phone)
    }
}
