//
//  CollectionsInfoView.swift
//  HuckApp
//
//  Created by James Asbury on 10/11/26.
//

import SwiftUI

/// A short explanation of where collections live, shown from the info button on
/// the home screen's "Your Collections" header: they're kept on the device rather
/// than the Hacker News account, and sync through iCloud when it's available.
/// The iCloud row is left out entirely while sync is switched off in the build.
struct CollectionsInfoView: View {
    /// Read once when the popover opens; it's only open briefly, so it needn't
    /// track iCloud sign-in changes live.
    private let isCloudAvailable = CollectionsCloudSync.isAvailable

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About Collections")
                .font(.headline)
            row(
                "No Account Needed",
                systemImage: "person.crop.circle.badge.checkmark",
                detail: "Collections are saved on this device, not to Hacker News, so they stay put when you sign in or out."
            )
            if CollectionsCloudSync.isEnabled {
                if isCloudAvailable {
                    row(
                        "Synced with iCloud",
                        systemImage: "icloud",
                        detail: "They stay up to date on your other devices signed in to the same iCloud account."
                    )
                } else {
                    row(
                        "iCloud Is Off",
                        systemImage: "icloud.slash",
                        detail: "Sign in to iCloud in Settings to keep collections in sync across your devices."
                    )
                }
            }
        }
        .padding()
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .presentationCompactAdaptation(.popover)
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    CollectionsInfoView()
}
