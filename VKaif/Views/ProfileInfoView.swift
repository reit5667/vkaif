import SwiftUI

struct ProfileInfoView: View {
    let user: VKUserDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let bdate = formattedBdate {
                    infoSection(header: "ДЕНЬ РОЖДЕНИЯ") {
                        Text(bdate)
                            .font(VKTheme.TextStyle.postBody)
                            .foregroundStyle(VKTheme.Colors.textPrimary)
                    }
                }

                if let hometown = homeTownText {
                    infoSection(header: "РОДНОЙ ГОРОД") {
                        Text(hometown)
                            .font(VKTheme.TextStyle.postBody)
                            .foregroundStyle(VKTheme.Colors.textPrimary)
                    }
                }

                if let rel = user.relationText {
                    infoSection(header: "СЕМЕЙНОЕ ПОЛОЖЕНИЕ") {
                        Text(rel)
                            .font(VKTheme.TextStyle.postBody)
                            .foregroundStyle(VKTheme.Colors.textPrimary)
                    }
                }

                if let relatives = user.relatives, !relatives.isEmpty {
                    infoSection(header: "РОДСТВЕННИКИ") {
                        VStack(spacing: 0) {
                            ForEach(Array(relatives.enumerated()), id: \.offset) { idx, relative in
                                relativeRow(relative)
                                if idx < relatives.count - 1 {
                                    Divider().padding(.leading, 16 + 36 + 10)
                                }
                            }
                        }
                    }
                }

                let hasContactInfo = user.city != nil || user.country != nil || !(user.site ?? "").isEmpty
                if hasContactInfo {
                    infoSection(header: "КОНТАКТНАЯ ИНФОРМАЦИЯ") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let city = user.city?.title {
                                contactRow(label: "Город", value: city)
                            }
                            if let country = user.country?.title {
                                contactRow(label: "Страна", value: country)
                            }
                            if let site = user.site, !site.isEmpty {
                                contactRow(label: "Сайт", value: site)
                            }
                        }
                    }
                }

                if let about = user.about, !about.isEmpty {
                    infoSection(header: "О СЕБЕ") {
                        Text(about)
                            .font(VKTheme.TextStyle.postBody)
                            .foregroundStyle(VKTheme.Colors.textPrimary)
                    }
                }
            }
        }
        .background(VKTheme.Colors.background)
        .navigationTitle("Подробная информация")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Section builder

    @ViewBuilder
    private func infoSection<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(VKTheme.TextStyle.sectionHeader)
                .foregroundStyle(VKTheme.Colors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            content()
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            Divider()
        }
    }

    // MARK: - Relative row

    private func relativeRow(_ relative: VKRelative) -> some View {
        HStack(spacing: 10) {
            relativePlaceholderAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(relative.name ?? "—")
                    .font(VKTheme.TextStyle.postBody)
                    .foregroundStyle(VKTheme.Colors.textPrimary)
                if let type = relative.type {
                    Text(relativeTypeText(type))
                        .font(VKTheme.TextStyle.commentTimestamp)
                        .foregroundStyle(VKTheme.Colors.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var relativePlaceholderAvatar: some View {
        RoundedRectangle(cornerRadius: VKTheme.Radius.avatarSquare)
            .fill(VKTheme.Colors.secondaryBackground)
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundStyle(VKTheme.Colors.textSecondary)
                    .font(.system(size: 16))
            )
    }

    // MARK: - Contact row

    private func contactRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(VKTheme.TextStyle.commentTimestamp)
                .foregroundStyle(VKTheme.Colors.textSecondary)
            Text(value)
                .font(VKTheme.TextStyle.postBody)
                .foregroundStyle(VKTheme.Colors.textPrimary)
        }
    }

    // MARK: - Helpers

    private var formattedBdate: String? {
        guard let bdate = user.bdate, !bdate.isEmpty else { return nil }
        let parts = bdate.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return bdate }
        let months = ["января","февраля","марта","апреля","мая","июня",
                      "июля","августа","сентября","октября","ноября","декабря"]
        let day = parts[0]
        let monthName = parts[1] >= 1 && parts[1] <= 12 ? months[parts[1] - 1] : "\(parts[1])"
        if parts.count >= 3 {
            return "\(day) \(monthName) \(parts[2])"
        }
        return "\(day) \(monthName)"
    }

    private var homeTownText: String? {
        if let ht = user.homeTown, !ht.isEmpty { return ht }
        return nil
    }

    private func relativeTypeText(_ type: String) -> String {
        switch type {
        case "parent":      return "Родитель"
        case "child":       return "Ребёнок"
        case "sibling":     return "Брат / Сестра"
        case "grandparent": return "Бабушка / Дедушка"
        case "grandchild":  return "Внук / Внучка"
        default:            return type.capitalized
        }
    }
}
