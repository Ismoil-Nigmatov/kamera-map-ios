import Foundation

struct APIError: LocalizedError, Equatable, Sendable {
    let status: Int
    let message: String

    var errorDescription: String? { message }

    static let offline = APIError(status: 0, message: "Нет связи с сервером. Проверьте интернет.")
}

struct EmptyResponse: Decodable, Sendable {}

private struct Envelope<Value: Decodable>: Decodable {
    let data: Value
}

private struct ErrorBody: Decodable {
    let message: String?
    let errors: [String: [String]]?
}

@MainActor
final class APIClient {
    let baseURL: URL
    var token: String?
    var onUnauthorized: (@MainActor () -> Void)?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        decoder = Self.makeDecoder()

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func send<Value: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        as type: Value.Type
    ) async throws -> (value: Value, status: Int) {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/\(path)"), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw APIError(status: 0, message: "Неверный адрес запроса.")
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.offline
        }

        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            throw failure(status: status, data: data)
        }

        if let empty = EmptyResponse() as? Value {
            return (empty, status)
        }

        do {
            return (try decoder.decode(Envelope<Value>.self, from: data).data, status)
        } catch {
            throw APIError(status: status, message: "Сервер ответил непонятно. Обновите приложение.")
        }
    }

    private func failure(status: Int, data: Data) -> APIError {
        if status == 401 {
            if token != nil {
                onUnauthorized?()
            }
            return APIError(status: 401, message: "Войдите, чтобы продолжить.")
        }

        let body = try? decoder.decode(ErrorBody.self, from: data)
        let fieldError = body?.errors?.values.compactMap(\.first).first

        if let message = fieldError ?? body?.message, !message.isEmpty {
            return APIError(status: status, message: message)
        }

        switch status {
        case 404:
            return APIError(status: status, message: "Не нашли — возможно, это уже удалили.")
        case 429:
            return APIError(status: status, message: "Слишком часто. Попробуйте чуть позже.")
        default:
            return APIError(status: status, message: "Что-то пошло не так. Попробуйте ещё раз.")
        }
    }
}
