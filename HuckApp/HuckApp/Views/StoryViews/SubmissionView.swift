//
//  SubmissionView.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import SwiftUI

/// What a post shares: a page elsewhere, or text written here — an Ask HN,
/// say. Hacker News's own form takes both fields at once and decides from
/// which are filled in; choosing up front shows only what applies.
enum SubmissionKind: CaseIterable, Identifiable {
    case link
    case text

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .link: "Link"
        case .text: "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .link: "link"
        case .text: "text.alignleft"
        }
    }

    /// The title prefixes that list a post of this kind on its own page —
    /// Show HN for something you made, Ask and Tell HN for discussions.
    var titlePrefixes: [String] {
        switch self {
        case .link: ["Show HN"]
        case .text: ["Ask HN", "Tell HN"]
        }
    }
}

/// The page for submitting a new post to Hacker News, presented full screen
/// from the home screen's compose button.
///
/// Mirrors HN's submit form — a title, then a URL or text — laid out as the
/// post will read: the title large, as it is atop a thread, and a preview of
/// the post's row in the feed beneath. Text is formatted as a comment is,
/// with the same keyboard controls. Once published, the post is handed to
/// `onPosted` to be opened.
struct SubmissionView: View {
    @Environment(\.dismiss) private var dismiss
    /// Names the author in the preview.
    @Environment(UserSession.self) private var session

    @State private var kind: SubmissionKind
    @State private var title: String
    @State private var url: String
    @State private var text = ""
    /// The text field's selection, which the formatting buttons act on.
    @State private var textSelection: TextSelection?
    /// The linked page's thumbnail, for the preview.
    @State private var thumbnail = ThumbnailType.loading
    @State private var isConfirmingDiscard = false
    /// True while the post is in flight; holds the Post button closed so one
    /// tap can't become two posts.
    @State private var isPosting = false
    /// Set when a post fails, presenting the error over the still-intact draft.
    @State private var postError: (any Error)?
    /// Set to the existing story when the link was already on Hacker News, so
    /// HN upvoted it rather than posting it again.
    @State private var repostID: Int?
    /// Played once the post is published.
    @State private var postedCount = 0
    @FocusState private var focusedField: Field?

    private enum Field {
        case title, url, text
    }

    /// Hacker News refuses titles longer than this.
    static let titleLimit = 80

    private static let fieldShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    /// Opens a published post — the new one, or the existing story a repost
    /// landed on.
    private let onPosted: (Int) -> Void

    /// Starts a post, optionally already filled in — a link shared into the
    /// app, say.
    init(
        kind: SubmissionKind = .link,
        title: String = "",
        url: String = "",
        onPosted: @escaping (Int) -> Void = { _ in }
    ) {
        self.onPosted = onPosted
        self.kind = kind
        self.title = title
        self.url = url
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    kindPicker
                    titleEditor
                    if kind == .link {
                        urlField
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    bodyField
                    if !trimmedTitle.isEmpty {
                        preview
                            .transition(.opacity)
                    }
                }
                .padding(20)
                .disabled(isPosting)
                .animation(.snappy, value: kind)
                .animation(.snappy, value: trimmedTitle.isEmpty)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Post")
            // Large at the top, shrinking into the bar once the form scrolls.
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close, action: cancel)
                        .disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submit) {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("Post")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    // The page's one call to action, in the app's orange.
                    .tint(.orange)
                    .disabled(!canSubmit || isPosting)
                    .accessibilityLabel(isPosting ? "Posting" : "Post")
                }
            }
            .alert("Discard this post?", isPresented: $isConfirmingDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your post will be lost.")
            }
            // On its own view so it never competes with the discard
            // confirmation above for the same presentation slot.
            .background {
                Color.clear
                    .alert("Already on Hacker News", isPresented: isShowingRepost) {
                        Button("View Post") {
                            if let repostID { finish(opening: repostID) }
                        }
                    } message: {
                        Text("This link has already been posted, so Hacker News counted your submission as an upvote instead.")
                    }
            }
            .sensoryFeedback(.success, trigger: postedCount)
            .onAppear { focusedField = .title }
            // Waits for typing to settle, so the thumbnail is fetched for the
            // finished address rather than for every keystroke along the way.
            .task(id: validURL) {
                await loadThumbnail()
            }
        }
        // Outside the stack, clear of the page's other alerts.
        .alert("Couldn't Post", item: $postError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    // MARK: - Kind

    private var kindPicker: some View {
        HStack(spacing: 12) {
            ForEach(SubmissionKind.allCases) { option in
                KindCard(kind: option, isSelected: kind == option) {
                    kind = option
                }
            }
        }
        .sensoryFeedback(.selection, trigger: kind)
    }

    // MARK: - Title

    /// The title, large as it will be atop the thread, with the prefixes that
    /// decide where the post is listed a tap away, and the characters left.
    private var titleEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title, axis: .vertical)
                .font(.title2)
                .fontWeight(.heavy)
                .focused($focusedField, equals: .title)
            HStack(spacing: 8) {
                ForEach(kind.titlePrefixes, id: \.self) { prefix in
                    PrefixChip(prefix: prefix, isApplied: hasPrefix(prefix)) {
                        togglePrefix(prefix)
                    }
                }
                Spacer()
                Text("\(trimmedTitle.count)/\(Self.titleLimit)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(isTitleTooLong ? .red : .secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: trimmedTitle.count)
            }
        }
    }

    // MARK: - URL and text

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                TextField("example.com/article", text: $url)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .url)
            }
            .padding(14)
            .background(Color(.tertiarySystemFill), in: Self.fieldShape)
            if isURLInvalid {
                Text("Enter a web address, like example.com/article.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var bodyField: some View {
        TextField(
            kind == .text ? "What would you like to discuss?" : "Add some context (optional)",
            text: $text,
            selection: $textSelection,
            axis: .vertical
        )
        .lineLimit(kind == .text ? 8... : 4...)
        .focused($focusedField, equals: .text)
        .formattingKeyboardToolbar(
            text: $text,
            selection: $textSelection,
            isEnabled: focusedField == .text
        )
        .padding(14)
        .background(Color(.tertiarySystemFill), in: Self.fieldShape)
    }

    // MARK: - Preview

    /// The post as its row in the feed will show it: title and domain, author,
    /// and the thumbnail for the link.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    previewTitle
                    Text(session.username ?? "you")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    HStack(spacing: 12) {
                        Label("1", systemImage: "arrow.up")
                        Label("0", systemImage: "bubble")
                        Label("now", systemImage: "clock")
                    }
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .labelStyle(PreviewStatLabelStyle())
                }
                Spacer(minLength: 0)
                StoryThumbnailView(status: kind == .text ? .text : thumbnail)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
            // A picture of the post, not the post: nothing in it does anything.
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preview of your post in the feed")
        }
    }

    /// The title with the domain after it, composed as `StoryCellView` does.
    private var previewTitle: Text {
        let titleText = Text(trimmedTitle)
        guard kind == .link, let domain = validURL.flatMap(Self.displayDomain) else {
            return titleText
        }
        let domainText = Text("(\(domain))")
            .font(.footnote)
            .foregroundStyle(.secondary)
        return Text("\(titleText)  \(domainText)")
    }

    private func loadThumbnail() async {
        guard let validURL else {
            thumbnail = .failed
            return
        }
        thumbnail = .loading
        do {
            try await Task.sleep(for: .milliseconds(600))
        } catch {
            return
        }
        if let image = await ThumbnailCache.shared.thumbnail(for: validURL) {
            thumbnail = .image(Image(uiImage: image))
        } else {
            thumbnail = .failed
        }
    }

    // MARK: - Title prefixes

    private func hasPrefix(_ prefix: String) -> Bool {
        title.hasPrefix("\(prefix):")
    }

    /// Adds the prefix, replacing any other one, or removes it if it's there.
    private func togglePrefix(_ prefix: String) {
        let allPrefixes = SubmissionKind.allCases.flatMap(\.titlePrefixes)
        var rest = title
        for existing in allPrefixes where rest.hasPrefix("\(existing):") {
            rest = String(rest.dropFirst(existing.count + 1))
                .trimmingCharacters(in: .whitespaces)
        }
        title = hasPrefix(prefix) ? rest : "\(prefix): \(rest)"
    }

    // MARK: - Validation

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTitleTooLong: Bool {
        trimmedTitle.count > Self.titleLimit
    }

    /// The address as a web URL, with `https://` assumed when it's left off,
    /// as it usually is when typed. `nil` unless it names a real-looking host.
    private var validURL: URL? {
        guard !trimmedURL.isEmpty else { return nil }
        let withScheme = trimmedURL.contains("://") ? trimmedURL : "https://\(trimmedURL)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), host.contains(".")
        else { return nil }
        return url
    }

    /// Only once the field has been left, so it doesn't scold mid-typing.
    private var isURLInvalid: Bool {
        !trimmedURL.isEmpty && validURL == nil && focusedField != .url
    }

    /// A post needs a title within the limit, and a link post a working URL.
    /// Text is optional either way: an Ask HN can be its title alone.
    private var canSubmit: Bool {
        guard !trimmedTitle.isEmpty, !isTitleTooLong else { return false }
        return kind == .text || validURL != nil
    }

    private var hasDraft: Bool {
        !trimmedTitle.isEmpty || !trimmedURL.isEmpty
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The host as the feed shows it, without a leading "www.". Matches
    /// `StoryModel.displayDomain`.
    private static func displayDomain(of url: URL) -> String? {
        guard let host = url.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Actions

    private func cancel() {
        if hasDraft {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    /// Posts the draft, closing the page only once Hacker News has accepted it.
    /// A failed post keeps everything as it was, so it can simply be sent again.
    private func submit() {
        guard canSubmit, !isPosting, let username = session.username else { return }
        let title = trimmedTitle
        let url = kind == .link ? validURL?.absoluteString ?? "" : ""
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        focusedField = nil
        isPosting = true
        Task {
            defer { isPosting = false }
            do {
                switch try await HackerNewsAPI.submitStory(
                    title: title, url: url, text: text, username: username
                ) {
                case .posted(let id):
                    postedCount += 1
                    if let id {
                        finish(opening: id)
                    } else {
                        dismiss()
                    }
                case .alreadySubmitted(let id):
                    repostID = id
                }
            } catch {
                postError = error
            }
        }
    }

    /// Closes the page and opens the post beneath it, so the thread is
    /// waiting as the page slides away.
    private func finish(opening id: Int) {
        dismiss()
        onPosted(id)
    }

    private var isShowingRepost: Binding<Bool> {
        Binding(get: { repostID != nil }, set: { if !$0 { repostID = nil } })
    }
}

// MARK: - Pieces

/// One choice of post type: an icon and its name. The chosen one is outlined
/// in orange, as a voted poll option is.
private struct KindCard: View {
    let kind: SubmissionKind
    let isSelected: Bool
    let action: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? .orange : .secondary)
                Text(kind.title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? Color.orange.opacity(0.1) : Color(.tertiarySystemFill), in: Self.shape)
            .overlay {
                Self.shape
                    .strokeBorder(.orange, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A title prefix — "Show HN", "Ask HN" — as a capsule that adds or removes it.
private struct PrefixChip: View {
    let prefix: String
    let isApplied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(prefix, systemImage: isApplied ? "checkmark" : "plus")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isApplied ? .white : .primary)
                .background(isApplied ? Color.orange : Color(.tertiarySystemFill), in: .capsule)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isApplied)
        .accessibilityLabel(isApplied ? "Remove \(prefix) prefix" : "Add \(prefix) prefix")
    }
}

/// The feed row's icon-and-count pairs, tightly spaced as they are there.
private struct PreviewStatLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview {
    SubmissionView()
        .environment(UserSession())
}

#Preview("Filled In") {
    SubmissionView(
        title: "Show HN: Huck, a native Hacker News client",
        url: "https://github.com/apple/swift"
    )
    .environment(UserSession())
}
