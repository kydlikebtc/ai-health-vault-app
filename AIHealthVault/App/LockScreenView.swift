import SwiftUI

/// 锁定屏幕 — 应用启动时展示，认证通过后自动跳转
struct LockScreenView: View {
    @EnvironmentObject private var authService: AuthenticationService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "cross.case.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)

            VStack(spacing: 8) {
                Text("AI Health Vault")
                    .font(.largeTitle.bold())
                Text("家庭健康数据管家")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 16) {
                if let error = authService.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await authService.authenticate() }
                } label: {
                    Label(
                        "使用 \(authService.biometricTypeName) 解锁",
                        systemImage: authService.biometricTypeName == "Face ID" ? "faceid" : "touchid"
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 48)
        }
        .task {
            // 应用启动时自动尝试认证
            await authService.authenticate()
        }
    }
}

#Preview {
    LockScreenView()
        .environmentObject(AuthenticationService())
}
