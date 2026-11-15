import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class SessionStore {
    let api: APIClient
    private(set) var user: User?
    private(set) var hasToken: Bool

    init(api: APIClient = APIClient(baseURL: AppConfig.apiBaseURL)) {
        self.api = api
        let token = Keychain.token()
        api.token = token
        hasToken = token != nil
        api.onUnauthorized = { [weak self] in
            self?.forget()
        }
    }

    var isSignedIn: Bool { hasToken }

    var isAdmin: Bool { user?.isAdmin ?? false }

    func restore() async {
        guard hasToken else { return }
        if let me = try? await api.me() {
            user = me
        }
    }

    func requestCode(phone: String) async throws -> LoginCode {
        try await api.requestCode(phone: phone)
    }

    func signIn(phone: String, code: String, name: String?) async throws {
        let issued = try await api.issueToken(phone: phone, code: code, name: name, deviceName: UIDevice.current.model)
        Keychain.save(issued.token)
        api.token = issued.token
        hasToken = true
        user = issued.user
    }

    func rename(_ name: String) async throws {
        user = try await api.rename(name)
    }

    func signOut() async {
        try? await api.logout()
        forget()
    }

    func deleteAccount() async throws {
        try await api.deleteAccount()
        forget()
    }

    private func forget() {
        Keychain.delete()
        api.token = nil
        hasToken = false
        user = nil
    }
}
