import Foundation

// MARK: - Обёртка ответа VK API

/// Стандартный ответ VK: все методы возвращают объект с ключом "response".
struct VKResponse<T: Decodable>: Decodable {
    let response: T
}

// MARK: - newsfeed.get — ответ

struct NewsfeedGetResponse: Decodable {
    let items: [VKPost]
    let nextFrom: String?
    let profiles: [VKProfile]?
    let groups: [VKGroup]?

    enum CodingKeys: String, CodingKey {
        case items
        case nextFrom = "next_from"
        case profiles
        case groups
    }
}

// MARK: - Пост (элемент ленты)

struct VKPost: Decodable {
    let id: Int
    let fromId: Int?
    let ownerId: Int?
    let date: Date

    /// Уникальный ключ поста для списков (owner_id + id).
    var postId: String { "\(ownerId ?? fromId ?? 0)_\(id)" }
    let text: String
    let markedAsAds: Int?
    let postType: String?
    let sourceType: String?
    let attachments: [VKAttachment]?
    let copyHistory: [VKPost]?

    enum CodingKeys: String, CodingKey {
        case id
        case fromId = "from_id"
        case ownerId = "owner_id"
        case date
        case text
        case markedAsAds = "marked_as_ads"
        case postType = "post_type"
        case sourceType = "source_type"
        case attachments
        case copyHistory = "copy_history"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        fromId = try c.decodeIfPresent(Int.self, forKey: .fromId)
        ownerId = try c.decodeIfPresent(Int.self, forKey: .ownerId)
        // VK возвращает date как Unix timestamp (Int)
        let timestamp = try c.decode(Int.self, forKey: .date)
        date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        markedAsAds = try c.decodeIfPresent(Int.self, forKey: .markedAsAds)
        postType = try c.decodeIfPresent(String.self, forKey: .postType)
        sourceType = try c.decodeIfPresent(String.self, forKey: .sourceType)
        attachments = try c.decodeIfPresent([VKAttachment].self, forKey: .attachments)
        copyHistory = try c.decodeIfPresent([VKPost].self, forKey: .copyHistory)
    }
}

// MARK: - Вложение (минимально: тип + опциональные поля)

struct VKAttachment: Decodable {
    let type: String
    let photo: VKPhoto?
    let video: VKVideo?
    let link: VKLink?
    let doc: VKDoc?

    enum CodingKeys: String, CodingKey {
        case type
        case photo
        case video
        case link
        case doc
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        photo = try c.decodeIfPresent(VKPhoto.self, forKey: .photo)
        video = try c.decodeIfPresent(VKVideo.self, forKey: .video)
        link = try c.decodeIfPresent(VKLink.self, forKey: .link)
        doc = try c.decodeIfPresent(VKDoc.self, forKey: .doc)
    }
}

struct VKPhoto: Decodable {
    let id: Int
    let sizes: [VKPhotoSize]?

    /// URL для отображения в ленте: приоритет x (604px) → m (130px) → s (75px) → первый доступный.
    var displayURL: String? {
        guard let sizes = sizes, !sizes.isEmpty else { return nil }
        let order = ["x", "m", "s"]
        for type in order {
            if let url = sizes.first(where: { $0.type?.lowercased() == type })?.url {
                return url
            }
        }
        return sizes.first?.url
    }
}

struct VKPhotoSize: Decodable {
    let type: String?
    let url: String
    let width: Int?
    let height: Int?
}

struct VKVideo: Decodable {
    let id: Int
    let title: String?
    let duration: Int?
}

struct VKLink: Decodable {
    let url: String
    let title: String?
}

struct VKDoc: Decodable {
    let id: Int
    let title: String?
    let ext: String?
}

// MARK: - Профиль пользователя / группа (для отображения имени)

struct VKProfile: Decodable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let photo50: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case photo50 = "photo_50"
    }
}

struct VKGroup: Decodable {
    let id: Int
    let name: String?
    let photo50: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case photo50 = "photo_50"
    }
}

// MARK: - users.get — профиль пользователя (экран профиля)

/// Ответ users.get — массив пользователей (response — массив, не объект).
struct UsersGetResponse: Decodable {
    let response: [VKUserDetail]
}

/// Профиль пользователя из users.get (аватар, имя, статус).
struct VKUserDetail: Decodable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let photo50: String?
    let photo200: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case photo50 = "photo_50"
        case photo200 = "photo_200"
        case status
    }

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "ID\(id)" : name
    }

    /// URL аватара для экрана профиля: photo_200 или photo_50.
    var avatarURL: String? { photo200 ?? photo50 }
}

// MARK: - photos.getAlbums

struct PhotosGetAlbumsResponse: Decodable {
    let count: Int
    let items: [VKAlbum]
}

struct VKAlbum: Decodable {
    let id: Int
    let title: String
    let size: Int
    let thumbId: Int?
    let thumbSrc: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case size
        case thumbId = "thumb_id"
        case thumbSrc = "thumb_src"
    }

    var thumbURL: String? { thumbSrc }
}

// MARK: - photos.get

struct PhotosGetResponse: Decodable {
    let count: Int
    let items: [VKPhoto]
}

// MARK: - friends.get

struct FriendsGetResponse: Decodable {
    let count: Int
    let items: [VKFriend]
}

struct VKFriend: Decodable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let photo50: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case photo50 = "photo_50"
    }

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "ID\(id)" : name
    }
}

// MARK: - groups.get

struct GroupsGetResponse: Decodable {
    let count: Int
    let items: [VKGroup]
}
