//
//  DryRunBadge.swift
//  HuckApp
//
//  Created by James Asbury on 11/1/26.
//

import SwiftUI

/// A small "Dry Run" label for anywhere something is written to Hacker News,
/// shown only while `PostingMode` is withholding writes — so a test post is
/// never mistaken for a real one. Draws nothing otherwise.
struct DryRunBadge: View {
    @AppStorage(PostingMode.dryRunKey) private var dryRunSetting = false
    @AppStorage(PostingMode.simulatesFailureKey) private var simulatesFailure = false

    var body: some View {
        if PostingMode.isDryRun(dryRunSetting: dryRunSetting) {
            Label(
                simulatesFailure ? "Dry Run · Fails" : "Dry Run",
                systemImage: "testtube.2"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .accessibilityLabel(simulatesFailure ? "Dry run: posting will fail" : "Dry run: nothing will be posted")
        }
    }
}

#Preview {
    DryRunBadge()
        .defaultAppStorage({
            let defaults = UserDefaults(suiteName: "DryRunBadgePreview") ?? .standard
            defaults.set(true, forKey: PostingMode.dryRunKey)
            return defaults
        }())
}
