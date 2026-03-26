import SwiftUI
import StoreKit

// MARK: - PaywallView

/// Paywall 订阅墙 — 展示 Free vs Premium 功能对比，支持购买和恢复
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subManager = SubscriptionManager.shared
    @State private var selectedProduct: Product? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                    featureComparisonSection
                    planPickerSection
                    ctaSection
                    footerSection
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .accessibilityLabel(String(localized: "close"))
                }
            }
            .task {
                if subManager.products.isEmpty {
                    await subManager.loadProductsAndRefreshStatus()
                }
                // 默认选中年付（主推）
                if selectedProduct == nil {
                    selectedProduct = subManager.product(for: .premiumAnnual)
                        ?? subManager.products.first
                }
            }
            .alert(String(localized: "error"), isPresented: .constant(subManager.errorMessage != nil)) {
                Button(String(localized: "ok")) { subManager.errorMessage = nil }
            } message: {
                Text(subManager.errorMessage ?? "")
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
                .padding(.top, 32)

            Text(String(localized: "paywall_headline"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(String(localized: "paywall_subheadline"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Feature Comparison

    private var featureComparisonSection: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text(String(localized: "feature"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(localized: "free_tier"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .center)
                Text(String(localized: "premium_tier"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 80, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))

            Divider()

            ForEach(featureRows, id: \.title) { row in
                FeatureRow(row: row)
                if row.title != featureRows.last?.title {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    private struct FeatureRowData {
        let title: String
        let freeValue: String
        let premiumValue: String
        let isFreeAvailable: Bool
    }

    private var featureRows: [FeatureRowData] {
        [
            FeatureRowData(
                title: String(localized: "feature_health_records"),
                freeValue: String(localized: "unlimited"),
                premiumValue: String(localized: "unlimited"),
                isFreeAvailable: true
            ),
            FeatureRowData(
                title: String(localized: "feature_family_members_short"),
                freeValue: "2",
                premiumValue: "10",
                isFreeAvailable: true
            ),
            FeatureRowData(
                title: String(localized: "feature_ai_analysis"),
                freeValue: "—",
                premiumValue: "50 / " + String(localized: "month"),
                isFreeAvailable: false
            ),
            FeatureRowData(
                title: String(localized: "feature_visit_preparation"),
                freeValue: "—",
                premiumValue: "✓",
                isFreeAvailable: false
            ),
            FeatureRowData(
                title: String(localized: "feature_daily_plan"),
                freeValue: "—",
                premiumValue: "✓",
                isFreeAvailable: false
            ),
            FeatureRowData(
                title: String(localized: "feature_trend_analysis"),
                freeValue: "—",
                premiumValue: "✓",
                isFreeAvailable: false
            ),
            FeatureRowData(
                title: String(localized: "feature_pdf_export"),
                freeValue: "—",
                premiumValue: "✓",
                isFreeAvailable: false
            ),
            FeatureRowData(
                title: String(localized: "feature_follow_up_reminders"),
                freeValue: String(localized: "existing_only"),
                premiumValue: "✓",
                isFreeAvailable: true
            ),
        ]
    }

    // MARK: - Plan Picker

    private var planPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "choose_plan"))
                .font(.headline)
                .padding(.horizontal, 16)

            if subManager.products.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(subManager.products, id: \.id) { product in
                    PlanOptionCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id,
                        savingsText: product.id == SubscriptionProductID.premiumAnnual.rawValue
                            ? subManager.annualSavingsDisplay() : nil
                    ) {
                        selectedProduct = product
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - CTA Section

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                guard let product = selectedProduct else { return }
                Task { await subManager.purchase(product) }
            } label: {
                Group {
                    if subManager.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(String(localized: "start_free_trial"))
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(subManager.isPurchasing || selectedProduct == nil)
            .padding(.horizontal, 16)

            Button {
                Task { await subManager.restorePurchases() }
            } label: {
                Text(String(localized: "restore_purchases"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .disabled(subManager.isPurchasing)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 6) {
            Text(String(localized: "paywall_trial_disclaimer"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link(String(localized: "terms_of_service"), destination: URL(string: "https://aihealthvault.app/terms")!)
                Link(String(localized: "privacy_policy"), destination: URL(string: "https://aihealthvault.app/privacy")!)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let row: PaywallView.FeatureRowData

    var body: some View {
        HStack(spacing: 0) {
            Text(row.title)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.freeValue)
                .font(.subheadline)
                .foregroundStyle(row.isFreeAvailable ? .primary : .tertiary)
                .frame(width: 60, alignment: .center)

            Text(row.premiumValue)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
                .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - PlanOptionCard

private struct PlanOptionCard: View {
    let product: Product
    let isSelected: Bool
    let savingsText: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 选中指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(product.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if let savings = savingsText {
                            Text(String(format: String(localized: "save_amount"), savings))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                    }

                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.blue : Color(.separator), lineWidth: isSelected ? 2 : 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PaywallModifier

/// 在任何视图上添加 Paywall 检查的 ViewModifier
struct PaywallModifier: ViewModifier {
    let feature: PremiumFeature
    @State private var showPaywall = false
    @State private var subManager = SubscriptionManager.shared

    func body(content: Content) -> some View {
        content
            .disabled(!subManager.hasAccess(to: feature))
            .overlay {
                if !subManager.hasAccess(to: feature) {
                    paywallOverlay
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
    }

    private var paywallOverlay: some View {
        Button {
            showPaywall = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                Text(String(localized: "unlock_premium"))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

extension View {
    /// 为视图添加 Premium 功能门控，未订阅时展示 Paywall
    func requiresPremium(_ feature: PremiumFeature) -> some View {
        modifier(PaywallModifier(feature: feature))
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
}
