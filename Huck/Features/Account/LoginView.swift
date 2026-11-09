//
//  LoginView.swift
//  Huck
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
    /// Whether a sign-in request is in flight. Drives the button's spinner and
    /// locks the form, so a second tap can't send a second request.
    @State private var isSigningIn = false
    /// Why the last attempt failed, or `nil` if there hasn't been one. Taken
    /// from the error rather than assumed, since a rejected password and Hacker
    /// News' captcha wall call for different advice.
    @State private var failureMessage: String?
    /// Bumped on each failure, so the failure haptic fires even when the
    /// message repeats.
    @State private var failureCount = 0

    @FocusState private var focus: LoginFocus?

    /// Signing in updates the shared session, which is observable — so every view
    /// that reads it re-evaluates on its own. There is no completion to report.
    @Environment(UserSession.self) private var session

    /// Hacker News usernames can't contain spaces, so stray whitespace — easy to
    /// pick up from autofill or a paste — is never meant.
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSignIn: Bool {
        !trimmedName.isEmpty && !password.isEmpty && !isSigningIn
    }

    var body: some View {
        VStack(alignment: .center, spacing: 15) {
            Text("Login")
                .padding(.horizontal)
                .padding(.vertical, 80)
                .font(.largeTitle)
                .bold()

            TextField(
                "Username",
                text: $name,
                prompt: Text("Username").foregroundColor(.secondary)
            )
            .textContentType(.username)
            .submitLabel(.next)
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
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            ZStack(alignment: .trailing) {
                Group {
                    if hidePassword {
                        SecureField(
                            "Password",
                            text: $password,
                            prompt: Text("Password").foregroundColor(.secondary)
                        )
                    } else {
                        TextField(
                            "Password",
                            text: $password,
                            prompt: Text("Password").foregroundColor(.secondary)
                        )
                    }
                }
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(signIn)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                // Changes the size of the text box for password
                .padding(10)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.gray, lineWidth: focus == .password ? 2 : 1)
                }

                Button {
                    hidePassword.toggle()
                } label: {
                    Image(systemName: hidePassword ? "eye.slash" : "eye")
                }
                .padding(8)
                // Override the orange color here
                .tint(.secondary)
                .accessibilityLabel(hidePassword ? "Show password" : "Hide password")
            }
            .padding(.horizontal)
            .focused($focus, equals: .password)
            // Editing mid-request would leave the fields out of step with
            // what was actually sent.
            .disabled(isSigningIn)

            VStack {
                if let failureMessage {
                    Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // The frame goes on the label, not the button, so the whole
                // capsule is the tap target rather than just the word.
                Button(action: signIn) {
                    ZStack {
                        // Kept in the layout while hidden, so the button
                        // doesn't change size when the spinner swaps in.
                        Text("Sign In")
                            .opacity(isSigningIn ? 0 : 1)
                        if isSigningIn {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                // The page's one call to action, in the app's orange.
                .tint(.orange)
                .disabled(trimmedName.isEmpty || password.isEmpty)
                .accessibilityLabel(isSigningIn ? "Signing in" : "Sign In")
                .padding()

                Link("Create an account", destination: URL(string: "https://news.ycombinator.com/login?goto=news")!)
                    .padding(.horizontal)
                    .tint(.orange)
                    .disabled(isSigningIn)
                Spacer()
            }
        }
        .animation(.default, value: failureMessage)
        .sensoryFeedback(.error, trigger: failureCount)
        // Dismissing mid-request would hide whether it worked.
        .interactiveDismissDisabled(isSigningIn)
    }

    private func signIn() {
        guard canSignIn else { return }
        isSigningIn = true
        failureMessage = nil
        focus = nil
        Task {
            defer { isSigningIn = false }
            do {
                // Success needs no handling here: the session updates, and the
                // presenter dismisses this sheet when it sees an account.
                try await session.signIn(username: trimmedName, password: password)
            } catch is CancellationError {
                return
            } catch {
                failureMessage = Self.message(for: error)
                failureCount += 1
                // Only a rejected password means the password is the problem;
                // otherwise keep it, so retrying is one tap.
                if case APIError.loginFailed = error {
                    password = ""
                    focus = .password
                }
            }
        }
    }

    /// What to tell the reader about a failed sign-in. Hacker News' own
    /// rejections already carry a reader-facing description; transport failures
    /// don't, and their system descriptions are too technical to show as-is.
    private static func message(for error: any Error) -> String {
        if let error = error as? APIError {
            return error.localizedDescription
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .internationalRoamingOff:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "Hacker News took too long to respond. Try again in a moment."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Couldn't reach Hacker News. Try again in a moment."
            default:
                break
            }
        }
        return "Something went wrong signing in. Try again in a moment."
    }
}
