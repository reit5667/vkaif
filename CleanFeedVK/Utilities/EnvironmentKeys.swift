import SwiftUI

/// Ключ окружения для замыкания «Сделать фото профиля» (галерея из поста на стене).
struct MakeProfilePhotoForGalleryKey: EnvironmentKey {
    static let defaultValue: ((String, Int, Int) async -> Bool)? = nil
}

extension EnvironmentValues {
    var makeProfilePhotoForGallery: ((String, Int, Int) async -> Bool)? {
        get { self[MakeProfilePhotoForGalleryKey.self] }
        set { self[MakeProfilePhotoForGalleryKey.self] = newValue }
    }
}
