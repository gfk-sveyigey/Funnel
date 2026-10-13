import SwiftUI

/// iOS 26 液态玻璃（Liquid Glass）的统一封装。
/// 通过 `useGlass` 开关与系统「降低透明度」辅助功能自动回退到毛玻璃。
private struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var useGlass: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if useGlass && !reduceTransparency {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    /// 给任意视图套一层液态玻璃卡片（可回退毛玻璃）。
    func glassCard(cornerRadius: CGFloat = 20, useGlass: Bool = true) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, useGlass: useGlass))
    }
}

/// 把相邻的玻璃元素分组，交给系统统一渲染 / 融合。
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}
