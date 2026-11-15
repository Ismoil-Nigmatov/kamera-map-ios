import Foundation
import Observation

@Observable
@MainActor
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    private(set) var current: Toast?
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    func show(_ message: String, isError: Bool = false) {
        current = Toast(message: message, isError: isError)
        if isError {
            Haptics.error()
        }
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 3.5 : 2.4))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    func show(_ error: Error) {
        if error is CancellationError {
            return
        }
        let message = (error as? LocalizedError)?.errorDescription ?? "Что-то пошло не так. Попробуйте ещё раз."
        show(message, isError: true)
    }

    func dismiss() {
        dismissal?.cancel()
        current = nil
    }
}
