//
//  UserPageView.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import SwiftUI

struct UserView: View {
    @State var username: String
    @State var user: User?
    
    @State private var title = ""
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading){
            Text(username)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Karma: \(user?.karma ?? 0)")
                .foregroundColor(.secondary)
            Text("")
            Text(user?.about ?? "")
            
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
            .tint(.primary)
            Divider()
            TabView {
                Tab("Account", systemImage: "person.circle") {
                    //AccountView()
                    Text("Okay")
                }
                Tab("Account", systemImage: "person.circle") {
                    //AccountView()
                    Text("Okay")
                }
                Tab("Account", systemImage: "person.circle") {
                    //AccountView()
                    Text("Okay")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic)) // Creates swipable pages
            .indexViewStyle(.page(backgroundDisplayMode: .never))
            Spacer()
            
        }
        /*
         .frame(
         minWidth: 0,
         maxWidth: .infinity,
         minHeight: 0,
         maxHeight: .infinity,
         alignment: .topLeading
         )
         */
        .padding(20)
        .task {
            await user = getUser(for: username)
        }
    }
}

#Preview {
    UserView(username: "zdw")
}
