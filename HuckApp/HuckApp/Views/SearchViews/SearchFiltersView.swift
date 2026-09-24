//
//  SearchFiltersView.swift
//  HuckApp
//
//  Created by James Asbury on 9/23/26.
//

import SwiftUI

/// The search refinements sheet, presented from the search page's toolbar.
///
/// Edits are made against a draft copy and only committed on "Apply", so backing
/// out leaves the results on screen alone — a half-typed username shouldn't
/// re-run the query.
struct SearchFiltersView: View {
    @Binding var filters: SearchFilters

    /// The category being searched, which decides whether the comment-count
    /// filter applies at all.
    let tab: SearchTab

    @State private var draft: SearchFilters
    @Environment(\.dismiss) private var dismiss

    init(filters: Binding<SearchFilters>, tab: SearchTab) {
        self._filters = filters
        self.tab = tab
        self._draft = State(initialValue: filters.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                authorSection
                if tab.supportsCommentCountFilter {
                    commentsSection
                }
                dateRangePicker
                if draft.isActive {
                    clearSection
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filters = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var authorSection: some View {
        Section {
            TextField("Username", text: $draft.author)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
        } header: {
            Text("Author")
        } footer: {
            Text("Only show results submitted by this user.")
        }
    }

    private var commentsSection: some View {
        Section {
            LabeledContent("Minimum") {
                // `format: .number` keeps this an `Int?` rather than a string
                // the query builder would have to re-parse, and an emptied
                // field is how "no minimum" is spelled.
                TextField("Any", value: $draft.minimumComments, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Comments")
        } footer: {
            Text("Only show results with at least this many comments.")
        }
    }

    /// An inline picker so all five ranges are visible at once — the list is
    /// short, and a menu would hide the choice behind a tap.
    private var dateRangePicker: some View {
        Picker("Time Range", selection: $draft.dateRange) {
            ForEach(SearchDateRange.allCases) { range in
                Text(range.title)
                    .tag(range)
            }
        }
        .pickerStyle(.inline)
    }

    private var clearSection: some View {
        Section {
            Button("Clear Filters", role: .destructive) {
                draft = SearchFilters()
            }
        }
    }
}

#Preview("Stories") {
    @Previewable @State var filters = SearchFilters()
    SearchFiltersView(filters: $filters, tab: .stories)
}

#Preview("Comments") {
    @Previewable @State var filters = SearchFilters()
    SearchFiltersView(filters: $filters, tab: .comments)
}
