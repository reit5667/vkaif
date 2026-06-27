import SwiftUI

/// Ключ окружения для замыкания «Сделать фото профиля» (галерея из поста на стене). Возвращает (успех, сообщение об ошибке).
struct MakeProfilePhotoForGalleryKey: EnvironmentKey {
    static let defaultValue: ((String, Int, Int) async -> (Bool, String?))? = nil
}

extension EnvironmentValues {
    var makeProfilePhotoForGallery: ((String, Int, Int) async -> (Bool, String?))? {
        get { self[MakeProfilePhotoForGalleryKey.self] }
        set { self[MakeProfilePhotoForGalleryKey.self] = newValue }
    }
}
