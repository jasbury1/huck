//
//  WindowShape.swift
//  HuckApp
//
//  Created by James Asbury on 10/11/26.
//

import CoreGraphics

/// Questions about a window's shape, for layouts that adapt to an iPhone Duo.
///
/// There's no public way to ask for the device model, and a size class can't
/// tell a folded Duo from an iPhone — both are compact. What sets the Duo apart
/// is its proportions, open or closed, so these read the window's size instead.
extension CGSize {
    /// The short side over the long side, above which a window is squarer than
    /// any iPhone's. Face ID iPhones are about 0.46 and the SE 0.56 (375 × 667);
    /// the closed iPhone Duo is 0.59 (382 × 644), and it and iPads only get
    /// squarer from there. A ratio holds in either orientation.
    private static let minimumNonPhoneAspectRatio: CGFloat = 0.58

    /// Whether the window is squarer than any iPhone's — an iPhone Duo, folded
    /// or unfolded, or an iPad.
    var isSquarerThanPhone: Bool {
        let shortSide = min(width, height)
        let longSide = max(width, height)
        return longSide > 0 && shortSide / longSide > Self.minimumNonPhoneAspectRatio
    }
}
