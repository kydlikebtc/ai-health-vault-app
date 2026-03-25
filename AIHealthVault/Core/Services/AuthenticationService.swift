import Foundation
import LocalAuthentication

/// 本地生物认证服务（Face ID / Touch ID）
@MainActor
final class AuthenticationService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?

    /// 检查设备是否支持生物认证
    var isBiometricAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 生物认证类型名称（Face ID / Touch ID）
    var biometricTypeName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "生物认证"
        }
    }

    /// 执行生物认证（优先 Face ID / Touch ID，失败回退到设备密码）
    func authenticate() async {
        let ctx = LAContext()
        var error: NSError?

        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // 设备不支持生物认证（如模拟器），直接放行
            authError = nil
            isAuthenticated = true
            return
        }

        do {
            let success = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "请验证身份以访问您的健康数据"
            )
            isAuthenticated = success
            if success { authError = nil }
        } catch {
            authError = error.localizedDescription
            await authenticateWithPasscode()
        }
    }

    /// 设备密码认证（生物认证失败时的回退方案）
    private func authenticateWithPasscode() async {
        let ctx = LAContext()
        do {
            let success = try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "请输入设备密码以访问您的健康数据"
            )
            isAuthenticated = success
            if success { authError = nil }
        } catch {
            authError = error.localizedDescription
            isAuthenticated = false
        }
    }

    /// 锁定应用（退出登录）
    func lock() {
        isAuthenticated = false
        authError = nil
    }
}
