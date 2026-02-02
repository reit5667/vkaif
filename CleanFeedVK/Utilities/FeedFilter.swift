import Foundation

// MARK: - Feed Filter

/// Клиентская фильтрация ленты: реклама, promo, чёрный список ключевых слов.
/// По спеке: отбрасываем marked_as_ads == 1, source_type == "promo", текст по blacklist.
struct FeedFilter {

    /// Ключевые слова: пост отбрасывается, если текст содержит любое из них (без учёта регистра).
    var blacklistKeywords: [String]

    init(blacklistKeywords: [String] = []) {
        self.blacklistKeywords = blacklistKeywords
    }

    /// Возвращает только посты, прошедшие фильтр.
    func filter(_ posts: [VKPost]) -> [VKPost] {
        posts.filter { post in
            !isFilteredOut(post)
        }
    }

    /// true = пост нужно отбросить
    private func isFilteredOut(_ post: VKPost) -> Bool {
        // Реклама
        if post.markedAsAds == 1 {
            return true
        }
        // Promo
        if post.sourceType?.lowercased() == "promo" {
            return true
        }
        // Чёрный список: текст содержит ключевое слово
        let textLower = post.text.lowercased()
        for keyword in blacklistKeywords where !keyword.isEmpty {
            if textLower.contains(keyword.lowercased()) {
                return true
            }
        }
        return false
    }
}
