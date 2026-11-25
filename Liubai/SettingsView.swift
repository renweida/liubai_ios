import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ReadingStore.self) private var library
    @Binding var appearance: Appearance
    @State private var showingTips = false
    @State private var importing = false
    @State private var exporting = false
    @State private var export: BackupDocument?
    @State private var feedback: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                Text("设置")
                    .font(ReadingPalette.editorial(44, relativeTo: .largeTitle))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 3)

                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("阅读外观")
                    Picker("阅读外观", selection: $appearance) {
                        ForEach(Appearance.allCases) { mode in Text(mode.label).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("本地资料")
                    VStack(spacing: 0) {
                        setting("导出备份", icon: "square.and.arrow.up", id: "settings.export") {
                            if let error = library.storageError {
                                self.error = error
                            } else {
                                export = BackupDocument(backup: library.data)
                                exporting = true
                            }
                        }
                        SectionRule().padding(.leading, 47)
                        setting("导入备份", icon: "square.and.arrow.down", id: "settings.import") { importing = true }
                    }
                    .paperCard(radius: 17)
                    Text("喜欢、收藏和笔记保存在此设备。导入会合并资料，同一篇文章的笔记保留修改时间较新的一份。")
                        .font(.footnote)
                        .foregroundStyle(ReadingPalette.muted)
                        .lineSpacing(4)
                        .padding(.horizontal, 3)
                }

                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("支持留白")
                    setting("打赏开发者", icon: "heart.circle", id: "settings.tip") { showingTips = true }
                        .paperCard(radius: 17)
                }
            }
            .padding(24)
            .readingWidth()
        }
        .readingBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingTips) { TipView() }
        .fileExporter(isPresented: $exporting, document: export, contentType: .json,
                      defaultFilename: "留白备份") { result in
            export = nil
            switch result {
            case .success: feedback = "备份已导出。"
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { try importFile(result.get()) }
            catch { self.error = error.localizedDescription }
        }
        .messageAlert($feedback, title: "已完成")
        .messageAlert($error, title: "操作未完成")
    }

    private func importFile(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > 20_000_000 { throw ReadingStoreError.backupTooLarge }
        try library.importBackup(BackupDocument.read(Data(contentsOf: url, options: [.mappedIfSafe])))
        feedback = "备份已导入，喜欢、收藏和笔记已合并。"
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.footnote.weight(.semibold))
            .foregroundStyle(ReadingPalette.muted)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, 3)
    }

    private func setting(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ReadingPalette.accent)
                    .accessibilityHidden(true)
                Text(title).font(.body.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ReadingPalette.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
