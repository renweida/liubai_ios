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
        case idle, loading, ready, end
        case failed(String)
    }

    private struct Page: Decodable {
        let article: Article
        let nextCursor: String?
    }

    private enum LoadError: LocalizedError {
        case missingEndpoint, invalidResponse, invalidArticle, missingArticle

        var errorDescription: String? {
            switch self {
            case .missingEndpoint: "请在 Xcode 的 ARTICLE_FEED_URL 中设置文章接口地址。"
            case .invalidResponse: "文章服务暂时无法使用，请稍后再试。"
            case .invalidArticle: "文章服务返回的数据无法读取，请稍后再试。"
            case .missingArticle: "这篇文章暂不可用。"
            }
        }
    }

    private static let maximumResponseSize = 8_000_000
    private(set) var articles: [Article] = []
    private(set) var state = State.idle
    private var articlesByID: [String: Article] = [:]
    private var style = ReadingStyle.balanced
    private var cursor: String?
    private var previousCursors: Set<String> = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        return URLSession(configuration: configuration)
    }()

    deinit { session.invalidateAndCancel() }

    func article(_ id: String) -> Article? { articlesByID[id] }

    func selectStyle(_ selection: ReadingStyle, keeping activeID: String?) {
        guard style != selection else { return }
        pending?.cancel()
        pending = nil
        let index = articles.firstIndex { $0.id == activeID } ?? 0
        articles = Array(articles.prefix(index + 1))
        style = selection
        cursor = nil
        previousCursors.removeAll()
        state = .idle
    }

    func prefetchNext() {
        guard pending == nil, state == .idle || state == .ready else { return }
        state = .loading
        pending = Task { [weak self] in
            guard let self else { return }
            await self.fetchNext()
        }
    }

    func retryNext() {
        if case .failed = state { state = .idle }
        if state == .end, articles.isEmpty { state = .idle }
        prefetchNext()
    }

    func loadArticle(_ id: String) async throws {
        if article(id) != nil { return }
        let url = try endpoint().appending(component: id)
        let (data, status) = try await response(from: url)
        try Task.checkCancellation()
        if status == 404 { throw LoadError.missingArticle }
        guard status == 200 else { throw LoadError.invalidResponse }
        let article = try JSONDecoder().decode(Article.self, from: data)
        guard article.id == id, isValid(article) else { throw LoadError.invalidArticle }
        articlesByID[id] = article
    }

    private func fetchNext() async {
        // 被切换风格取消的任务不能清除新风格的请求或覆盖其状态。
        defer { if !Task.isCancelled { pending = nil } }
        do {
            try Task.checkCancellation()
            let endpoint = try endpoint()
            let existingIDs = Set(articles.map(\.id))

            while true {
                let url = try pageURL(endpoint)
                let (data, status) = try await response(from: url)
                try Task.checkCancellation()
                if status == 204 {
                    state = .end
                    return
                }
                guard status == 200 else { throw LoadError.invalidResponse }
                let page = try JSONDecoder().decode(Page.self, from: data)
                guard isValid(page.article) else { throw LoadError.invalidArticle }
                if let next = page.nextCursor {
                    guard !next.isEmpty, previousCursors.insert(next).inserted else {
                        throw LoadError.invalidResponse
                    }
                }
                cursor = page.nextCursor

                if !existingIDs.contains(page.article.id) {
                    articlesByID[page.article.id] = page.article
                    articles.append(page.article)
                    state = cursor == nil ? .end : .ready
                    return
                }
                if cursor == nil {
                    state = .end
                    return
                }
            }
        } catch {
            if !Task.isCancelled { state = .failed(Self.message(for: error)) }
        }
    }

    static func message(for error: any Error) -> String {
        if let error = error as? LoadError { return error.localizedDescription }
        if error is DecodingError { return LoadError.invalidArticle.localizedDescription }
        return "请检查网络连接后重试。"
    }

    private func isValid(_ article: Article) -> Bool {
        !article.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !article.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !article.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && article.minutes > 0
    }

    private func pageURL(_ endpoint: URL) throws -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw LoadError.missingEndpoint
        }
        var items = (components.queryItems ?? []).filter { $0.name != "style" && $0.name != "cursor" }
        items.append(URLQueryItem(name: "style", value: style.rawValue))
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        guard let url = components.url else { throw LoadError.invalidResponse }
        return url
    }

    private func endpoint() throws -> URL {
        #if DEBUG
        if testResponses != nil, let url = URL(string: "https://liubai.test/api/v1/articles") { return url }
        #endif
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ArticleFeedURL") as? String,
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else { throw LoadError.missingEndpoint }
        return url
    }

    private func response(from url: URL) async throws -> (Data, Int) {
        #if DEBUG
        if let testResponses {
            let route = url.path + (url.query.map { "?" + $0 } ?? "")
            guard let response = testResponses[route] else { throw LoadError.invalidResponse }
            return (Data((response.body ?? "").utf8), response.status)
        }
        #endif

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.url?.scheme?.lowercased() == "https", data.count <= Self.maximumResponseSize else {
            throw LoadError.invalidResponse
        }
        return (data, http.statusCode)
    }

    #if DEBUG
    private struct TestResponse: Decodable {
        let status: Int
        let body: String?
    }

    private let testResponses: [String: TestResponse]? = {
        let environment = ProcessInfo.processInfo.environment
        guard let library = environment["LIUBAI_UI_TEST_LIBRARY"], UUID(uuidString: library) != nil,
              let base64 = environment["LIUBAI_UI_TEST_RESPONSES"], let data = Data(base64Encoded: base64)
        else { return nil }
        return try? JSONDecoder().decode([String: TestResponse].self, from: data)
    }()
    #endif
}

enum ReadingStyle: String, CaseIterable, Identifiable {
    case balanced, philosophy, psychology, comfort

    var id: Self { self }

    var title: String {
        switch self {
        case .balanced: "均衡阅读"
        case .philosophy: "哲学思辨"
        case .psychology: "心理觉察"
        case .comfort: "温柔疗愈"
        }
    }

    var detail: String {
        switch self {
        case .balanced: "按推荐顺序浏览全部主题"
        case .philosophy: "多读关于选择、意义与生活的思考"
        case .psychology: "多读关于情绪、关系与行为的知识"
        case .comfort: "多读自我关怀、正念与接纳类文章"
        }
    }

    var symbol: String {
        switch self {
        case .balanced: "square.grid.2x2"
        case .philosophy: "quote.opening"
        case .psychology: "brain.head.profile"
        case .comfort: "heart"
        }
    }
}
