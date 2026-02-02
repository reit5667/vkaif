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
    let text: String
    let markedAsAds: Int?
    let postType: String?
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
