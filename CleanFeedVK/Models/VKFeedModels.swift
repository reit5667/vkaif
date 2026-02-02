import Foundation

// MARK: - Обёртка ответа VK API

/// Стандартный ответ VK: все методы возвращают объект с ключом "response".
struct VKResponse<T: Decodable>: Decodable {
    let response: T
}

/// Ошибка VK API: при 200 OK тело может быть { "error": { "error_code", "error_msg" } }.
struct VKErrorPayload: Decodable {
    let errorCode: Int
    let errorMsg: String?
    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMsg = "error_msg"
    }
}

struct VKErrorWrapper: Decodable {
    let error: VKErrorPayload
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

// MARK: - wall.get — ответ (лента группы)

struct WallGetResponse: Decodable {
    let count: Int
    let items: [VKPost]
}

// MARK: - wall.getComments — комментарии к посту

struct WallGetCommentsResponse: Decodable {
    let count: Int
    let items: [VKComment]
    let profiles: [VKProfile]?
    let groups: [VKGroup]?

    enum CodingKeys: String, CodingKey {
        case count
        case items
        case profiles
        case groups
    }
}

/// Комментарий к посту (wall.getComments).
struct VKComment: Decodable {
    let id: Int
    let fromId: Int
    let date: Date
    let text: String
    let likes: VKCommentLikes?

    enum CodingKeys: String, CodingKey {
        case id
        case fromId = "from_id"
        case date
        case text
        case likes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        fromId = try c.decode(Int.self, forKey: .fromId)
        let timestamp = try c.decode(Int.self, forKey: .date)
        date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        likes = try c.decodeIfPresent(VKCommentLikes.self, forKey: .likes)
    }
}

struct VKCommentLikes: Decodable {
    let count: Int
}

// MARK: - Пост (элемент ленты)

/// Лайки поста (newsfeed.get / wall.get).
struct VKPostLikes: Decodable {
    let count: Int
}

/// Комментарии поста (newsfeed.get / wall.get).
struct VKPostComments: Decodable {
    let count: Int
}

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
    /// Счётчик лайков (если вернул API).
    let likes: VKPostLikes?
    /// Счётчик комментариев (если вернул API).
    let comments: VKPostComments?

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
        case likes
        case comments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        fromId = try c.decodeIfPresent(Int.self, forKey: .fromId)
        ownerId = try c.decodeIfPresent(Int.self, forKey: .ownerId)
        let timestamp = try c.decode(Int.self, forKey: .date)
        date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        markedAsAds = try c.decodeIfPresent(Int.self, forKey: .markedAsAds)
        postType = try c.decodeIfPresent(String.self, forKey: .postType)
        sourceType = try c.decodeIfPresent(String.self, forKey: .sourceType)
        attachments = try c.decodeIfPresent([VKAttachment].self, forKey: .attachments)
        copyHistory = try c.decodeIfPresent([VKPost].self, forKey: .copyHistory)
        likes = try c.decodeIfPresent(VKPostLikes.self, forKey: .likes)
        // VK: comments приходит как объект { "count": N } или иногда как число; fallback для совместимости.
        if let commentsObj = try c.decodeIfPresent(VKPostComments.self, forKey: .comments) {
            comments = commentsObj
        } else if let commentsInt = try c.decodeIfPresent(Int.self, forKey: .comments) {
            comments = VKPostComments(count: commentsInt)
        } else {
            comments = nil
        }
    }

    var likesCount: Int { likes?.count ?? 0 }
    var commentsCount: Int { comments?.count ?? 0 }
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

    /// URL для отображения: приоритет размеров (x→m→s и w,z,y,r,q,p,o) → первый доступный.
    var displayURL: String? {
        guard let sizes = sizes, !sizes.isEmpty else { return nil }
        let order = ["x", "m", "s", "w", "z", "y", "r", "q", "p", "o"]
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
    let photo400: String?
    let photoMax: String?
    let photoMaxOrig: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case photo50 = "photo_50"
        case photo200 = "photo_200"
        case photo400 = "photo_400"
        case photoMax = "photo_max"
        case photoMaxOrig = "photo_max_orig"
        case status
    }

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "ID\(id)" : name
    }

    /// URL аватара для экрана профиля: photo_200 или photo_50.
    var avatarURL: String? { photo200 ?? photo50 }

    /// URL для полноэкранного просмотра: photo_max_orig → photo_max → photo_400 → photo_200. Качество зависит от того, что вернул VK.
    var fullScreenAvatarURL: String? { photoMaxOrig ?? photoMax ?? photo400 ?? photo200 ?? photo50 }
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
