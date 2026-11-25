import Observation
import StoreKit
import SwiftUI

@MainActor
@Observable final class TipStore {
    static let tiers = ["app.liubai.reader.tip.small", "app.liubai.reader.tip.medium", "app.liubai.reader.tip.large"]
    private(set) var products: [Product] = []
    private(set) var loading = false
    private(set) var purchasing: String?
    private(set) var loadError: String?

    func observeTransactions() async {
        let updates = StoreKit.Transaction.updates
        for await result in StoreKit.Transaction.unfinished { await finish(result) }
        for await result in updates { await finish(result) }
    }

    func load() async {
        guard !loading else { return }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            products = try await Product.products(for: Self.tiers).sorted { $0.price < $1.price }
            if products.isEmpty { loadError = "暂时无法获取打赏选项。" }
        } catch {
            loadError = "暂时无法获取打赏选项。"
        }
    }

    func purchase(_ product: Product) async throws -> String? {
        guard purchasing == nil else { return nil }
        purchasing = product.id
        defer { purchasing = nil }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result else { return "Apple 暂时无法验证这笔交易。" }
            await transaction.finish()
            return "谢谢你支持留白。"
        case .pending: return "这笔打赏正在等待 Apple 确认。"
        case .userCancelled: return nil
        @unknown default: return nil
        }
    }

    private func finish(_ result: VerificationResult<StoreKit.Transaction>) async {
        if case .verified(let transaction) = result, Self.tiers.contains(transaction.productID) {
            await transaction.finish()
        }
    }
}

struct TipView: View {
    @Environment(TipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var feedback: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BrandMark()
                    Text("支持留白")
                        .font(ReadingPalette.editorial(36, relativeTo: .largeTitle))
                        .accessibilityAddTraits(.isHeader)
                    Text("如果这些阅读时刻对你有意义，可以通过 App Store 支持留白的开发。")
                        .font(.subheadline)
                        .lineSpacing(4)
                        .foregroundStyle(ReadingPalette.muted)
                        .padding(.bottom, 3)
                    if store.loading {
                        ProgressView("正在加载打赏选项")
                    } else if let error = store.loadError {
                        Text(error).foregroundStyle(ReadingPalette.muted)
                        Button("重试") { Task { await store.load() } }
                            .buttonStyle(.glass)
                    } else {
                        ForEach(store.products) { product in
                            Button {
                                Task {
                                    do { feedback = try await store.purchase(product) }
                                    catch { feedback = "打赏未完成，请稍后重试。" }
                                }
                            } label: {
                                HStack {
                                    Text(title(for: product))
                                    Spacer()
                                    if store.purchasing == product.id { ProgressView() }
                                    else { Text(product.displayPrice).foregroundStyle(ReadingPalette.accent) }
                                }
                                .font(.body.weight(.medium))
                                .padding(13)
                                .frame(minHeight: 49)
                                .paperCard(radius: 14)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.purchasing != nil)
                            .accessibilityIdentifier(product.id)
                        }
                    }
                }
                .padding(24)
                .readingWidth()
            }
            .readingBackground()
            .navigationTitle("打赏开发者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .disabled(store.purchasing != nil)
                }
            }
            .task { await store.load() }
            .messageAlert($feedback, title: "打赏开发者")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(store.purchasing != nil)
    }

    private func title(for product: Product) -> String {
        switch product.id {
        case TipStore.tiers[0]: "小额打赏"
        case TipStore.tiers[1]: "中额打赏"
        default: "大额打赏"
        }
    }
}
