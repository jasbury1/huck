//
//  UserPageView.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

/*
 Credit: https://stackoverflow.com/a/79353832
 and https://bdewey.com/til/2023/03/01/swiftui-and-tabview-height/
 for height preserving tab view help
 */

import SwiftUI

struct UserView: View {
    @State var username: String
    @State var user: User?
    @Binding var path: NavigationPath

    @State private var currentTab: UserTab = .posts
    @State private var userStoryIds: [Int] = []
    @State private var currentPage = 0
    @State private var hasMorePages = false
    @State private var isLoadingMore = false

    @State private var userComments: [UserCommentResult] = []
    @State private var commentPage = 0
    @State private var hasMoreComments = false
    @State private var isLoadingMoreComments = false

    private let topId = "tab_bar_top"

    @Namespace private var namespace
    private let systemBackgroundColor = Color(UIColor.systemBackground)

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                userSummary
                Divider()
                Spacer().frame(height: 0).id(topId)
                LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                    Section {
                        tabViewContent
                            .frame(minHeight: 1, maxHeight: .infinity)
                            .padding(.top)
                    } header: {
                        tabBarButtons
                    }
                }
            }
            .onChange(of: currentTab) {
                scrollProxy.scrollTo(topId)
            }
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.large)
        .task {
            async let fetchedUser = getUser(for: username)
            async let firstPage = AlgoliaAPIService.getUserStoryIds(username: username, page: 0)
            async let firstCommentPage = AlgoliaAPIService.getUserComments(username: username, page: 0)
            let (u, storyResult, commentResult) = await (fetchedUser, firstPage, firstCommentPage)
            user = u
            userStoryIds = storyResult.ids
            hasMorePages = storyResult.hasMore
            userComments = commentResult.comments
            hasMoreComments = commentResult.hasMore
        }
    }

    var userSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Karma: \(user?.karma ?? 0)")
                .foregroundStyle(.secondary)
            if let about = user?.about, !about.isEmpty {
                Text(about)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
    }

    var tabViewContent: some View {
        HeightPreservingTabView(selection: $currentTab) {
            ForEach(UserTab.allCases, id: \.self) { tab in
                VStack(spacing: 0) {
                    switch tab {
                    case .posts:
                        homeTab
                    case .comments:
                        commentsTab
                    case .favorites:
                        favoritesTab
                    }
                    Spacer().frame(minHeight: 0)
                }
                .tag(tab)
            }
        }
        .frame(minHeight: 1) // `minHeight` must start as non-zero or `HeightPreservingTabView` won't measure the interior content height
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.default, value: currentTab)
        .transition(.slide)
    }

    var tabBarButtons: some View {
        HStack(spacing: 20) {
            ForEach(UserTab.allCases, id: \.self) { tab in
                let selected = currentTab == tab
                Text(tab.title)
                    .font(.body)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.vertical, 8)
                    .onTapGesture {
                        currentTab = tab
                    }
                    .background {
                        if selected {
                            Color.orange
                                .frame(height: 2)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .matchedGeometryEffect(id: "indicator", in: namespace)
                        }
                    }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .background(systemBackgroundColor)
    }

    // MARK: - Tab Content

    var homeTab: some View {
        LazyVStack(spacing: 0) {
            ForEach(userStoryIds, id: \.self) { storyId in
                StoryCellView(storyId: storyId, path: $path)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider()
            }
            if hasMorePages {
                ProgressView()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        Task { await loadMorePosts() }
                    }
            }
        }
    }

    var commentsTab: some View {
        LazyVStack(spacing: 0) {
            ForEach(userComments) { comment in
                UserCommentRow(comment: comment, path: $path)
                Divider()
            }
            if hasMoreComments {
                ProgressView()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        Task { await loadMoreComments() }
                    }
            }
        }
    }

    var favoritesTab: some View {
        Text("Favorites are not publicly available")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }

    private func loadMorePosts() async {
        guard !isLoadingMore && hasMorePages else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        let result = await AlgoliaAPIService.getUserStoryIds(username: username, page: nextPage)
        userStoryIds.append(contentsOf: result.ids)
        currentPage = nextPage
        hasMorePages = result.hasMore
        isLoadingMore = false
    }

    private func loadMoreComments() async {
        guard !isLoadingMoreComments && hasMoreComments else { return }
        isLoadingMoreComments = true
        let nextPage = commentPage + 1
        let result = await AlgoliaAPIService.getUserComments(username: username, page: nextPage)
        userComments.append(contentsOf: result.comments)
        commentPage = nextPage
        hasMoreComments = result.hasMore
        isLoadingMoreComments = false
    }
}

struct UserCommentRow: View {
    let comment: UserCommentResult
    @Binding var path: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = comment.storyTitle, let storyId = comment.storyId {
                Button {
                    path.append(ItemNavigation.textStory(id: storyId))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.up.left")
                            .font(.caption2)
                        Text(title)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            Text(comment.text)
                .font(.body)
                .lineLimit(4)
            Text(comment.timestamp.ageString())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        UserView(username: "zdw", path: .constant(NavigationPath()))
    }
}
