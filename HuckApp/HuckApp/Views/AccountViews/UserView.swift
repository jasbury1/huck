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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20){
            Text(username)
                .font(.largeTitle)
            Text("Karma: \(user?.karma ?? 0)")
                .   foregroundColor(.secondary)
            Text(user?.about ?? "")
            
            Divider()
            
            HStack{
                Button(action: {
                }, label : {
                    Text("Posts")
                        .frame(maxWidth: .infinity)    // << !!
                })
                Button(action: {
                }, label : {
                    Text("Comments")
                        .frame(maxWidth: .infinity)    // << !!
                })
                Button(action: {
                }, label : {
                    Text("Favorites")
                        .frame(maxWidth: .infinity)    // << !!
                })
            }
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
            .indexViewStyle(.page(backgroundDisplayMode: .always))
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
