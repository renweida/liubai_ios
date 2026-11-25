import Foundation
import Observation

struct Article: Identifiable, Hashable, Codable {
    let id: String
    let category: String
    let theme: String
    let title: String
    let subtitle: String
    let excerpt: String
    let minutes: Int
    var source: String = "AI 生成"
    let markdown: String

    var displayTitle: String { subtitle.isEmpty ? title : title + subtitle }
}

@MainActor
@Observable final class ArticleFeed {
    enum State: Equatable {
        case idle, loading, ready, empty
        case failed(String)
    }

    private enum LoadError: LocalizedError {
        case missingEndpoint, invalidResponse, invalidArticles

        var errorDescription: String? {
            switch self {
            case .missingEndpoint: "请在 Xcode 的 ARTICLE_FEED_URL 中设置文章接口地址。"
            case .invalidResponse: "文章服务暂时无法使用，请稍后再试。"
            case .invalidArticles: "文章服务返回的数据无法读取，请稍后再试。"
            }
        }
    }

    private static let maximumResponseSize = 8_000_000
    private(set) var articles: [Article] = []
    private(set) var state = State.idle

    func article(_ id: String) -> Article? { articles.first { $0.id == id } }

    func refresh() async {
        guard state != .loading else { return }
        state = .loading

        do {
            let data = try await responseData()
            try Task.checkCancellation()
            let incoming = try JSONDecoder().decode([Article].self, from: data)
            var seen = Set<String>()
            let valid = incoming.filter {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.minutes > 0 && seen.insert($0.id).inserted
            }
            guard incoming.isEmpty || !valid.isEmpty else { throw LoadError.invalidArticles }
            articles = valid
            state = valid.isEmpty ? .empty : .ready
        } catch {
            if Task.isCancelled {
                state = articles.isEmpty ? .idle : .ready
            } else if !articles.isEmpty {
                state = .ready
            } else if let error = error as? LoadError {
                state = .failed(error.localizedDescription)
            } else if error is DecodingError {
                state = .failed(LoadError.invalidArticles.localizedDescription)
            } else {
                state = .failed("请检查网络连接后重试。")
            }
        }
    }

    private func responseData() async throws -> Data {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let library = environment["LIUBAI_UI_TEST_LIBRARY"], UUID(uuidString: library) != nil,
           let base64 = environment["LIUBAI_UI_TEST_ARTICLES"], let data = Data(base64Encoded: base64) {
            return data
        }
        #endif

        guard let value = Bundle.main.object(forInfoDictionaryKey: "ArticleFeedURL") as? String,
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else { throw LoadError.missingEndpoint }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              http.url?.scheme?.lowercased() == "https", data.count <= Self.maximumResponseSize else {
            throw LoadError.invalidResponse
        }
        return data
    }
}
