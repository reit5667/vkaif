import SwiftUI

// MARK: - Design tokens (PRD-VKaif-UI-Redesign-2026-06-28)

enum VKTheme {

    // MARK: Colors

    enum Colors {
        /// Основной синий VK (#4A76A8) — шапки, кнопки, ссылки
        static let primary = Color(hex: "#4A76A8")
        /// Тёмный синий для нажатых состояний
        static let primaryDark = Color(hex: "#3D6491")
        /// Фон контента
        static let background = Color.white
        /// Разделители и рамки карточек
        static let separator = Color(hex: "#E0E0E0")
        /// Вторичный фон (секции, плейсхолдеры)
        static let secondaryBackground = Color(hex: "#F5F5F5")
        /// Основной текст
        static let textPrimary = Color(hex: "#222222")
        /// Вторичный текст (время, подписи)
        static let textSecondary = Color(hex: "#828282")
        /// Текст поверх синего фона
        static let textOnPrimary = Color.white
        /// Фон входящих пузырей
        static let incomingBubble = Color(hex: "#D9E8F5")
        /// Фон drawer-меню
        static let drawerBackground = Color(hex: "#2D4F72")
        /// Бейджи непрочитанных
        static let badge = Color(hex: "#E64646")
        /// Индикатор онлайн
        static let online = Color(hex: "#4BB34B")
        /// Фон экрана чата (классический VK — голубовато-серый)
        static let chatBackground = Color(hex: "#D5DDE5")
        /// Фон кнопки-бургера в шапке ленты
        static let profileHeaderBackground = Color.clear
    }

    // MARK: Geometry

    enum Radius {
        /// Кнопки — почти прямой угол
        static let button: CGFloat = 4
        /// Аватарки в постах и профиле — квадратные
        static let avatarSquare: CGFloat = 2
        /// Аватарки в диалогах — круглые (задаётся через .clipShape(Circle()))
        static let avatarCircle: CGFloat = 0
        /// Пузыри сообщений
        static let bubble: CGFloat = 12
    }

    enum Border {
        /// Толщина рамки карточек и разделителей
        static let card: CGFloat = 1
    }

    // MARK: Avatar sizes

    enum AvatarSize {
        /// В карточке поста
        static let post: CGFloat = 40
        /// В ячейке диалога
        static let dialog: CGFloat = 48
        /// В шапке чата
        static let chatHeader: CGFloat = 32
        /// В шапке профиля
        static let profile: CGFloat = 72
    }

    // MARK: Typography helpers

    enum TextStyle {
        // Feed / posts
        static let postAuthorName        = Font.system(size: 15, weight: .semibold)
        static let postBody              = Font.system(size: 15, weight: .regular)
        static let timestamp             = Font.system(size: 13, weight: .regular)
        // Messages list
        static let dialogName            = Font.system(size: 17, weight: .semibold)
        static let dialogNameUnread      = Font.system(size: 17, weight: .bold)
        static let dialogPreview         = Font.system(size: 15, weight: .regular)
        // Comments
        static let commentBody           = Font.system(size: 14, weight: .regular)
        static let commentTimestamp      = Font.system(size: 12, weight: .regular)
        // Profile
        static let profileName           = Font.system(size: 18, weight: .bold)
        static let profileCity           = Font.system(size: 13, weight: .medium)
        static let profileAction         = Font.system(size: 15, weight: .medium)
        static let profileActionSecondary = Font.system(size: 14, weight: .medium)
        // Drawer
        static let drawerItem            = Font.system(size: 17, weight: .regular)
        // Shared UI
        static let navTitle              = Font.system(size: 17, weight: .semibold)
        static let badge                 = Font.system(size: 12, weight: .semibold)
        static let statNumber            = Font.system(size: 17, weight: .bold)
        static let statLabel             = Font.system(size: 12, weight: .regular)
        static let sectionHeader         = Font.system(size: 13, weight: .semibold)
    }
}

// MARK: - Blue navigation bar style

#if os(iOS)
extension View {
    func vkBlueNavBar() -> some View {
        self
            .toolbarBackground(VKTheme.Colors.primary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
#endif

// MARK: - Color hex initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8)  & 0xFF) / 255
            b = Double(int         & 0xFF) / 255
            a = 1
        case 8:
            r = Double((int >> 24) & 0xFF) / 255
            g = Double((int >> 16) & 0xFF) / 255
            b = Double((int >> 8)  & 0xFF) / 255
            a = Double(int         & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
