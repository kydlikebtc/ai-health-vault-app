import SwiftUI
import SwiftData

// MARK: - 术语查询弹出框

struct TermLookupView: View {
    let term: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var explanation: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("正在查询「\(term)」…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                    } else if let err = errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("通俗解读", systemImage: "text.bubble")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(explanation)
                                .font(.body)
                        }
                        .padding(14)
                        .background(.blue.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle(term)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            await loadExplanation()
        }
    }

    private func loadExplanation() async {
        let service = TermExplanationService.shared
        service.setModelContext(modelContext)
        do {
            explanation = try await service.explain(term: term)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - ViewModifier：长按任意 Text 弹出术语解读

struct TermExplainableModifier: ViewModifier {
    let term: String
    @State private var showingSheet = false

    func body(content: Content) -> some View {
        content
            .onLongPressGesture {
                showingSheet = true
            }
            .sheet(isPresented: $showingSheet) {
                TermLookupView(term: term)
            }
    }
}

extension View {
    /// 为任何视图添加长按触发的术语解读弹窗
    func termExplanable(_ term: String) -> some View {
        modifier(TermExplainableModifier(term: term))
    }
}

// MARK: - 独立术语查询入口（从搜索栏输入）

struct TermSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedTerm: String?

    @Query(sort: \TermCacheItem.hitCount, order: .reverse) private var cachedTerms: [TermCacheItem]

    var body: some View {
        NavigationStack {
            List {
                if !searchText.isEmpty {
                    Button {
                        selectedTerm = searchText
                    } label: {
                        Label("查询「\(searchText)」", systemImage: "magnifyingglass")
                            .foregroundStyle(.blue)
                    }
                }

                if !cachedTerms.isEmpty {
                    Section("最近查询") {
                        ForEach(cachedTerms.prefix(10), id: \.term) { item in
                            Button {
                                selectedTerm = item.term
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.term)
                                            .font(.body.bold())
                                        Spacer()
                                        Text("查询 \(item.hitCount) 次")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(item.explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("术语解读")
            .searchable(text: $searchText, prompt: "输入医学术语…")
            .sheet(item: $selectedTerm) { term in
                TermLookupView(term: term)
            }
        }
    }
}
