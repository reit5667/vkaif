import SwiftUI

// MARK: - VKNavigationBar ViewModifier

/// Синяя навигационная шапка в стиле VK (#4A76A8).
/// Применяется ко всем экранам кроме ленты.
///
/// Использование:
///   .vkNavBar(title: "Сообщения")
///   .vkNavBar(title: "Чат") { backButton } trailing: { menuButton }
struct VKNavBarModifier<Leading: View, Trailing: View>: ViewModifier {
    let title: String
    let leading: Leading
    let trailing: Trailing

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(VKTheme.Colors.primary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { leading }
                ToolbarItem(placement: .navigationBarTrailing) { trailing }
            }
    }
}

extension View {
    /// Синяя шапка с произвольным leading и trailing содержимым.
    func vkNavBar<L: View, T: View>(
        title: String,
        @ViewBuilder leading: () -> L,
        @ViewBuilder trailing: () -> T
    ) -> some View {
        modifier(VKNavBarModifier(title: title, leading: leading(), trailing: trailing()))
    }

    /// Синяя шапка только с title (без кастомных кнопок).
    func vkNavBar(title: String) -> some View {
        modifier(VKNavBarModifier(title: title, leading: EmptyView(), trailing: EmptyView()))
    }

    /// Синяя шапка с кастомным leading (напр. кнопка drawer).
    func vkNavBar<L: View>(
        title: String,
        @ViewBuilder leading: () -> L
    ) -> some View {
        modifier(VKNavBarModifier(title: title, leading: leading(), trailing: EmptyView()))
    }
}
