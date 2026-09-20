//
//  LoginView.swift
//  HuckApp
//
//  Created by James Asbury on 12/29/25.
//

import SwiftUI

enum LoginFocus {
    case username
    case password
    case none
}

struct LoginView: View {
    
    @State private var name: String = ""
    @State private var password: String = ""
    @State private var hidePassword: Bool = true
    /// Why the last attempt failed, or `nil` if there hasn't been one. Taken
    /// from the error rather than assumed, since a rejected password and Hacker
    /// News' captcha wall call for different advice.
    @State private var failureMessage: String?
    
    @FocusState private var focus: LoginFocus?

    /// Signing in updates the shared session, which is observable — so every view
    /// that reads it re-evaluates on its own. There is no completion to report.
    @Environment(UserSession.self) private var session
    
    var signinButtonDisabled: Bool {
        [name, password].contains(where: \.isEmpty)
    }
    
    var body: some View {
        
        VStack(alignment: .center, spacing: 15) {
            Text("Login")
                .padding(.horizontal)
                .padding(.vertical, 80)
                .font(.largeTitle)
                .bold()
            
            TextField("Name",
                      text: $name ,
                      prompt: Text("Login").foregroundColor(.secondary)
            )
            // Changes the size of the text box
            .padding(10)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.gray, lineWidth: focus == .username ? 2 : 1)
            }
            .padding(.horizontal)
            .onSubmit {
                focus = .password
            }
            .focused($focus, equals: .username)
            .disableAutocorrection(true)
            .autocapitalization(.none)
            
            ZStack(alignment: .trailing) {
                Group {
                    if hidePassword {
                        SecureField("Password",
                                    text: $password,
                                    prompt: Text("Password").foregroundColor(.secondary))
                    } else {
                        TextField("Password",
                                  text: $password,
                                  prompt: Text("Password").foregroundColor(.secondary))
                    }
                }
                .disableAutocorrection(true)
                .autocapitalization(.none)
                // Changes the size of the text box for password
                .padding(10)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.gray, lineWidth: focus == .password ? 2 : 1)
                }
                
                Button(action: {
                    hidePassword.toggle()
                }) {
                    Image(systemName: self.hidePassword ? "eye.slash" : "eye")
                        .accentColor(.gray)
                }
                .padding(8)
                // Override the orange color here
                .tint(.secondary)
            }
            .padding(.horizontal)
            .focused($focus, equals: .password)
            VStack {
                if let failureMessage {
                    Text(failureMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button {
                    Task {
                        do {
                            failureMessage = nil
                            try await session.signIn(username: name, password: password)
                        }
                        catch {
                            password = ""
                            failureMessage = error.localizedDescription
                        }
                    }
                    
                } label: {
                    Text("Sign In")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .frame(height: 50)
                // Button fills all horizontal space
                .frame(maxWidth: .infinity)
                .background(
                    signinButtonDisabled ?
                    Color.secondary : Color.orange //Color(red: 40, green: 155, blue: 255)
                )
                .cornerRadius(40)
                .disabled(signinButtonDisabled)
                .padding()
                
                Link("Create an account", destination: URL(string: "https://news.ycombinator.com/login?goto=news")!)
                    .padding(.horizontal)
                    .tint(.orange)
                Spacer()
            }
        }
        .onAppear() {
            let cookies = readCookie(forURL: URL(string: "https://news.ycombinator.com/")!)
            print("Existing cookies: \(cookies)")
        }
    }
}
