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

    private let topId = "tab_bar_top"

    @Namespace private var namespace
    private let systemBackgroundColor = Color(UIColor.systemBackground)

    var body: some View {
        VStack(spacing: 0) {
            // No header, but provides a safe area to prevent seeing content scroll.
            // TODO: Eventually change this to show the username, but only when the summary disappears
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
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
        }
        .task {
            async let fetchedUser = getUser(for: username)
            async let firstPage = AlgoliaAPIService.getUserStoryIds(username: username, page: 0)
            let (u, result) = await (fetchedUser, firstPage)
            user = u
            userStoryIds = result.ids
            hasMorePages = result.hasMore
        }
    }
    
    var userSummary: some View {
        VStack(alignment: .leading){
            Text(username)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Karma: \(user?.karma ?? 0)")
                .foregroundColor(.secondary)
            Text("")
            Text(user?.about ?? "")
        }
        .frame(
              minWidth: 0,
              maxWidth: .infinity,
              minHeight: 0,
              maxHeight: .infinity,
              alignment: .topLeading
            )
        //.frame(minWidth: .infinity)
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
                        infoTab
                    case .favorites:
                        Color.clear // TBD
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

    var infoTab: some View {
        VStack {
            Text("You've got some info!")
            ForEach(0..<10) { i in
                Text("Info \(i)")
            }
        }
    }
}



struct UserNavigationTabView: View {
    var body: some View {
        VStack {
            Divider()
            HStack{
                Button(action: {
                }, label : {
                    VStack{
                        Text("Posts")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                        Rectangle()
                            .fill(.orange)
                            .frame(maxWidth: .infinity, maxHeight: 2)
                    }
                })
                Button(action: {
                }, label : {
                    VStack{
                        Text("Comments")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                        Rectangle()
                            .fill(.orange)
                            .frame(maxWidth: .infinity, maxHeight: 2)
                    }
                })
                Button(action: {
                }, label : {
                    VStack{
                        Text("Favorites")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                        Rectangle()
                            .fill(.orange)
                            .frame(maxWidth: .infinity, maxHeight: 2)
                    }
                })
            }
            Divider()
        }
        .tint(.primary)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        
    }
}

#Preview {
    UserView(username: "zdw", path: .constant(NavigationPath()))
}
