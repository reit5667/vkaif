import SwiftUI

let drawerWidth: CGFloat = 280

struct DrawerMenuView: View {
    @ObservedObject var profileViewModel: ProfileViewModel
    @Binding var activeSection: AppSection
    @Binding var isOpen: Bool
    let unreadMessagesCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileBlock
            Divider()
                .overlay(Color.white.opacity(0.15))
                .padding(.bottom, 4)
            menuItems
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VKTheme.Colors.drawerBackground.ignoresSafeArea())
        .onAppear { profileViewModel.loadProfileIfNeeded() }
    }

    private var profileBlock: some View {
        HStack(spacing: 12) {
            avatarView
            Text(profileViewModel.user?.displayName ?? "")
                .font(VKTheme.TextStyle.navTitle)
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            activeSection = .profile
            withAnimation(.spring(duration: 0.28)) { isOpen = false }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        let size: CGFloat = 44
        if let urlStr = profileViewModel.user?.avatarURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.white.opacity(0.25)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 20))
                )
        }
    }

    private var menuItems: some View {
        VStack(alignment: .leading, spacing: 0) {
            DrawerItem(icon: "house.fill",       title: "Лента",         section: .feed,      activeSection: $activeSection, isOpen: $isOpen)
            drawerDivider
            DrawerItem(icon: "person.2.fill",    title: "Друзья",        section: .friends,   activeSection: $activeSection, isOpen: $isOpen)
            drawerDivider
            DrawerItem(icon: "message.fill",     title: "Сообщения",     section: .messages,  activeSection: $activeSection, isOpen: $isOpen, badge: unreadMessagesCount)
            drawerDivider
            DrawerItem(icon: "person.3.fill",    title: "Группы",        section: .groups,    activeSection: $activeSection, isOpen: $isOpen)
            drawerDivider
            DrawerItem(icon: "photo.on.rectangle", title: "Фотографии",  section: .photos,    activeSection: $activeSection, isOpen: $isOpen)
            drawerDivider
            DrawerItem(icon: "video",            title: "Видеозаписи",   section: .video,     activeSection: $activeSection, isOpen: $isOpen, isStub: true)
            drawerDivider
            DrawerItem(icon: "music.note",       title: "Аудиозаписи",   section: .audio,     activeSection: $activeSection, isOpen: $isOpen, isStub: true)
            drawerDivider
            DrawerItem(icon: "bell",             title: "Ответы",        section: .answers,   activeSection: $activeSection, isOpen: $isOpen, isStub: true)
            drawerDivider
            DrawerItem(icon: "bookmark",         title: "Закладки",      section: .bookmarks, activeSection: $activeSection, isOpen: $isOpen, isStub: true)
            drawerDivider
            DrawerItem(icon: "magnifyingglass",  title: "Поиск",         section: .search,    activeSection: $activeSection, isOpen: $isOpen)
            drawerDivider
            DrawerItem(icon: "gearshape.fill",   title: "Настройки",     section: .settings,  activeSection: $activeSection, isOpen: $isOpen)
        }
    }

    private var drawerDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.1))
            .padding(.leading, 16)
    }
}

private struct DrawerItem: View {
    let icon: String
    let title: String
    let section: AppSection
    @Binding var activeSection: AppSection
    @Binding var isOpen: Bool
    var badge: Int = 0
    var isStub: Bool = false

    private var isActive: Bool { activeSection == section }

    var body: some View {
        Button {
            activeSection = section
            withAnimation(.spring(duration: 0.28)) { isOpen = false }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundColor(itemColor)
                    .font(.system(size: 16))
                Text(title)
                    .font(isActive ? VKTheme.TextStyle.navTitle : VKTheme.TextStyle.drawerItem)
                    .foregroundColor(itemColor)
                Spacer()
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(VKTheme.TextStyle.badge)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VKTheme.Colors.badge)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(isActive ? Color.white.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var itemColor: Color {
        if isStub { return .white.opacity(0.35) }
        return isActive ? .white : .white.opacity(0.85)
    }
}
