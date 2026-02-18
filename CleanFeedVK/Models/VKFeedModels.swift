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

/// Ответ likes.add: VK возвращает response как число (новый count) или как объект {"likes": N}.
struct VKLikesAddResponse: Decodable {
    let likesCount: Int

    init(from decoder: Decoder) throws {
        do {
            let nested = try decoder.container(keyedBy: InnerKeys.self)
            likesCount = try nested.decode(Int.self, forKey: .likes)
            return
        } catch {
            let container = try decoder.singleValueContainer()
            likesCount = try container.decode(Int.self)
        }
    }

    private enum InnerKeys: String, CodingKey { case likes }
}

/// Ответ wall.createComment: VK возвращает объект с comment_id.
struct VKWallCreateCommentResponse: Decodable {
    let commentId: Int
    let parentsStack: [Int]?

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case parentsStack = "parents_stack"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commentId = try c.decode(Int.self, forKey: .commentId)
        parentsStack = try c.decodeIfPresent([Int].self, forKey: .parentsStack)
    }
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

/// Ответ wall.repost: success, post_id на стене пользователя, reposts_count (новый счётчик).
struct WallRepostResponse: Decodable {
    let success: Int
    let postId: Int?
    let repostsCount: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case postId = "post_id"
        case repostsCount = "reposts_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decode(Int.self, forKey: .success)
        postId = try c.decodeIfPresent(Int.self, forKey: .postId)
        repostsCount = try c.decodeIfPresent(Int.self, forKey: .repostsCount)
    }
}

// MARK: - wall.get — ответ (лента группы)

struct WallGetResponse: Decodable {
    let count: Int
    let items: [VKPost]
    /// При extended=1 — профили и группы для подстановки имён/аватаров (в т.ч. авторов репостов).
    let profiles: [VKProfile]?
    let groups: [VKGroup]?

    enum CodingKeys: String, CodingKey {
        case count
        case items
        case profiles
        case groups
    }
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

/// Ветка ответов к комментарию (wall.getComments, поле thread).
struct VKCommentThread: Decodable {
    let count: Int
    let items: [VKComment]?

    enum CodingKeys: String, CodingKey {
        case count
        case items
    }
}

/// Комментарий к посту (wall.getComments). thread — ответы на комментарий.
struct VKComment: Decodable {
    let id: Int
    let fromId: Int
    let date: Date
    let text: String
    let likes: VKCommentLikes?
    /// Ответы на этот комментарий (если есть).
    let thread: VKCommentThread?

    enum CodingKeys: String, CodingKey {
        case id
        case fromId = "from_id"
        case date
        case text
        case likes
        case thread
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        fromId = try c.decode(Int.self, forKey: .fromId)
        let timestamp = try c.decode(Int.self, forKey: .date)
        date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        likes = try c.decodeIfPresent(VKCommentLikes.self, forKey: .likes)
        thread = try c.decodeIfPresent(VKCommentThread.self, forKey: .thread)
    }
}

/// Лайки комментария. user_likes == 1 — текущий пользователь лайкнул.
struct VKCommentLikes: Decodable {
    let count: Int
    let userLikes: Int?

    enum CodingKeys: String, CodingKey {
        case count
        case userLikes = "user_likes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decode(Int.self, forKey: .count)
        userLikes = try c.decodeIfPresent(Int.self, forKey: .userLikes)
    }

    init(count: Int, userLikes: Int? = nil) {
        self.count = count
        self.userLikes = userLikes
    }
}

// MARK: - Пост (элемент ленты)

/// Лайки поста (newsfeed.get / wall.get). user_likes == 1 — текущий пользователь лайкнул.
struct VKPostLikes: Decodable {
    let count: Int
    /// 0 или 1 — поставил ли текущий пользователь лайк.
    let userLikes: Int?

    enum CodingKeys: String, CodingKey {
        case count
        case userLikes = "user_likes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decode(Int.self, forKey: .count)
        userLikes = try c.decodeIfPresent(Int.self, forKey: .userLikes)
    }

    init(count: Int, userLikes: Int? = nil) {
        self.count = count
        self.userLikes = userLikes
    }
}

/// Комментарии поста (newsfeed.get / wall.get).
struct VKPostComments: Decodable {
    let count: Int
}

/// Репосты поста (newsfeed.get / wall.get). user_reposted == 1 — текущий пользователь репостнул.
struct VKPostReposts: Decodable {
    let count: Int
    let userReposted: Int?

    enum CodingKeys: String, CodingKey {
        case count
        case userReposted = "user_reposted"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decode(Int.self, forKey: .count)
        userReposted = try c.decodeIfPresent(Int.self, forKey: .userReposted)
    }

    init(count: Int, userReposted: Int? = nil) {
        self.count = count
        self.userReposted = userReposted
    }
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
    /// Счётчик репостов (если вернул API).
    let reposts: VKPostReposts?
    /// 1 — пост закреплён на стене (wall.get, newsfeed.get).
    let isPinned: Int?

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
        case reposts
        case isPinned = "is_pinned"
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
        reposts = try c.decodeIfPresent(VKPostReposts.self, forKey: .reposts)
        isPinned = try c.decodeIfPresent(Int.self, forKey: .isPinned)
    }

    var likesCount: Int { likes?.count ?? 0 }
    var commentsCount: Int { comments?.count ?? 0 }
    var repostsCount: Int { reposts?.count ?? 0 }
}

// MARK: - Вложение (минимально: тип + опциональные поля)

struct VKAttachment: Decodable {
    let type: String
    let photo: VKPhoto?
    let video: VKVideo?
    let link: VKLink?
    let doc: VKDoc?
    let poll: VKPoll?

    enum CodingKeys: String, CodingKey {
        case type
        case photo
        case video
        case link
        case doc
        case poll
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        photo = try c.decodeIfPresent(VKPhoto.self, forKey: .photo)
        video = try c.decodeIfPresent(VKVideo.self, forKey: .video)
        link = try c.decodeIfPresent(VKLink.self, forKey: .link)
        doc = try c.decodeIfPresent(VKDoc.self, forKey: .doc)
        poll = try c.decodeIfPresent(VKPoll.self, forKey: .poll)
    }
}

/// Опрос во вложении поста (type=poll).
struct VKPoll: Decodable {
    let id: Int
    let ownerId: Int?
    let question: String?
    let created: Int?
    let votes: Int?
    let answers: [VKPollAnswer]?
    let anonymous: Bool?
    let multiple: Bool?
    let endDate: Int?
    let closed: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case question
        case created
        case votes
        case answers
        case anonymous
        case multiple
        case endDate = "end_date"
        case closed
    }
}

struct VKPollAnswer: Decodable {
    let id: Int
    let text: String?
    let votes: Int?
    let rate: Double?
}

/// Лайки фото (photos.get возвращает в каждом фото).
struct VKPhotoLikes: Decodable {
    let count: Int
    let userLikes: Int

    enum CodingKeys: String, CodingKey {
        case count
        case userLikes = "user_likes"
    }
}

/// Счётчик комментариев к фото (photos.get).
struct VKPhotoComments: Decodable {
    let count: Int
}

struct VKPhoto: Decodable {
    let id: Int
    /// Владелец фото (owner_id в ответе photos.get). Для альбома «Сохранённые» у каждого фото свой owner_id после copy.
    let ownerId: Int?
    let sizes: [VKPhotoSize]?
    let likes: VKPhotoLikes?
    let comments: VKPhotoComments?
    /// Для photos.copy у фото из приватных альбомов / чужих постов (если VK отдал).
    let accessKey: String?
    /// Legacy (VK может отдавать фото без sizes, но с photo_75, photo_604 и т.д.).
    let photo75: String?
    let photo130: String?
    let photo604: String?
    let photo807: String?
    let photo1280: String?
    let photo2560: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case sizes
        case likes
        case comments
        case accessKey = "access_key"
        case photo75 = "photo_75"
        case photo130 = "photo_130"
        case photo604 = "photo_604"
        case photo807 = "photo_807"
        case photo1280 = "photo_1280"
        case photo2560 = "photo_2560"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        ownerId = try c.decodeIfPresent(Int.self, forKey: .ownerId)
        sizes = try c.decodeIfPresent([VKPhotoSize].self, forKey: .sizes)
        likes = try c.decodeIfPresent(VKPhotoLikes.self, forKey: .likes)
        comments = try c.decodeIfPresent(VKPhotoComments.self, forKey: .comments)
        accessKey = try c.decodeIfPresent(String.self, forKey: .accessKey)
        photo75 = try c.decodeIfPresent(String.self, forKey: .photo75)
        photo130 = try c.decodeIfPresent(String.self, forKey: .photo130)
        photo604 = try c.decodeIfPresent(String.self, forKey: .photo604)
        photo807 = try c.decodeIfPresent(String.self, forKey: .photo807)
        photo1280 = try c.decodeIfPresent(String.self, forKey: .photo1280)
        photo2560 = try c.decodeIfPresent(String.self, forKey: .photo2560)
    }

    private func urlFromSizes(order: [String]) -> String? {
        guard let sizes = sizes, !sizes.isEmpty else { return nil }
        for type in order {
            if let url = sizes.first(where: { $0.type?.lowercased() == type })?.url, !url.isEmpty {
                return url
            }
        }
        return sizes.first(where: { $0.url != nil && !($0.url ?? "").isEmpty })?.url
    }

    private var legacyDisplayURL: String? {
        photo2560 ?? photo1280 ?? photo807 ?? photo604 ?? photo130 ?? photo75
    }

    /// URL для отображения: sizes (x→m→s…) или legacy (photo_604 → photo_130 → …).
    var displayURL: String? {
        urlFromSizes(order: ["x", "m", "s", "w", "z", "y", "r", "q", "p", "o"])
            ?? legacyDisplayURL
    }

    /// URL для превью (сетка/лента): приоритет мелких размеров; иначе legacy.
    var thumbnailDisplayURL: String? {
        urlFromSizes(order: ["s", "m", "q", "p", "x", "o", "r", "y", "z", "w"])
            ?? photo130 ?? photo75 ?? photo604 ?? photo807 ?? photo1280 ?? photo2560
    }

    /// URL для превью в ленте: приоритет крупных размеров (x 604px, w/z/y) для лучшего качества миниатюр; иначе legacy.
    var feedPreviewURL: String? {
        urlFromSizes(order: ["x", "w", "z", "y", "m", "r", "q", "p", "s", "o"])
            ?? photo604 ?? photo807 ?? photo130 ?? photo75 ?? photo1280 ?? photo2560
    }
}

struct VKPhotoSize: Decodable {
    let type: String?
    let width: Int?
    let height: Int?
    /// VK отдаёт "url"; в части ответов может быть "src".
    var url: String? { urlValue ?? srcValue }
    private let urlValue: String?
    private let srcValue: String?

    enum CodingKeys: String, CodingKey {
        case type
        case width
        case height
        case urlValue = "url"
        case srcValue = "src"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        urlValue = try c.decodeIfPresent(String.self, forKey: .urlValue)
        srcValue = try c.decodeIfPresent(String.self, forKey: .srcValue)
    }
}

/// Элемент превью видео (image): url или src, размеры.
struct VKVideoImage: Decodable {
    let width: Int?
    let height: Int?
    private let urlValue: String?
    private let srcValue: String?

    enum CodingKeys: String, CodingKey {
        case width
        case height
        case urlValue = "url"
        case srcValue = "src"
    }

    var imageURL: String? { (urlValue ?? srcValue).flatMap { $0.isEmpty ? nil : $0 } }
}

struct VKVideo: Decodable {
    let id: Int
    /// Владелец видео (положительный — пользователь, отрицательный — группа). Нужен для video.get и плеера.
    let ownerId: Int?
    let title: String?
    let duration: Int?
    /// Превью: массив размеров (в ленте VK может отдавать не всегда).
    let image: [VKVideoImage]?
    /// Превью: первый кадр 320px (часто есть во вложении).
    let firstFrame320: String?
    let firstFrame160: String?
    /// URL встраиваемого плеера (для WKWebView). Может отсутствовать в кратком вложении — тогда нужен video.get.
    let player: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case title
        case duration
        case image
        case firstFrame320 = "first_frame_320"
        case firstFrame160 = "first_frame_160"
        case player
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        ownerId = try c.decodeIfPresent(Int.self, forKey: .ownerId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        image = try c.decodeIfPresent([VKVideoImage].self, forKey: .image)
        firstFrame320 = try c.decodeIfPresent(String.self, forKey: .firstFrame320)
        firstFrame160 = try c.decodeIfPresent(String.self, forKey: .firstFrame160)
        player = try c.decodeIfPresent(String.self, forKey: .player)
    }

    /// URL превью для отображения в ленте: first_frame_320 → first_frame_160 → первый image → nil (тогда нужен video.get).
    var previewImageURL: String? {
        if let u = firstFrame320, !u.isEmpty { return u }
        if let u = firstFrame160, !u.isEmpty { return u }
        return image?.first(where: { ($0.imageURL ?? "").isEmpty == false })?.imageURL
    }

    /// Идентификатор для video.get: "owner_id+video_id" (плюс в VK — подчёркивание).
    func videoGetId(ownerFallback: Int) -> String {
        let oid = ownerId ?? ownerFallback
        return "\(oid)_\(id)"
    }
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

    /// URL аватара для экрана профиля: photo_200 или photo_50 (для списков и мелких мест).
    var avatarURL: String? { photo200 ?? photo50 }

    /// URL аватара в шапке профиля: по возможности крупнее (photo_400 → photo_200 → photo_50), чтобы не была «миниатюра».
    var headerAvatarURL: String? { photo400 ?? photo200 ?? photo50 }

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

/// Ответ photos.copy — новое фото в «Сохранённых». VK может вернуть response как число (id фото) или как объект { id, owner_id }.
struct PhotosCopyResponse: Decodable {
    let id: Int
    let ownerId: Int

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
    }

    init(from decoder: Decoder) throws {
        // VK иногда возвращает только число (новый photo_id)
        if let single = try? decoder.singleValueContainer().decode(Int.self) {
            self.id = single
            self.ownerId = 0
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try keyed.decode(Int.self, forKey: .id)
        self.ownerId = try keyed.decodeIfPresent(Int.self, forKey: .ownerId) ?? 0
    }
}

/// Ответ photos.getOwnerPhotoUploadServer.
struct OwnerPhotoUploadServerResponse: Decodable {
    let uploadUrl: String
    enum CodingKeys: String, CodingKey { case uploadUrl = "upload_url" }
}

/// Ответ POST на upload_url (фото профиля). Потом передать в photos.saveOwnerPhoto.
/// VK может вернуть server числом (Int) или строкой — принимаем оба варианта.
struct OwnerPhotoUploadResult: Decodable {
    let server: String?
    let photo: String?
    let hash: String?

    enum CodingKeys: String, CodingKey { case server, photo, hash }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decodeIfPresent(String.self, forKey: .server) {
            server = s
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .server) {
            server = String(n)
        } else {
            server = nil
        }
        photo = try c.decodeIfPresent(String.self, forKey: .photo)
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
    }
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

// MARK: - friends.getRequests (items — id пользователей)

struct FriendsGetRequestsResponse: Decodable {
    let count: Int
    let items: [Int]
}

// MARK: - friends.getSuggestions (items — id возможных друзей)

struct FriendsGetSuggestionsResponse: Decodable {
    let count: Int
    let items: [VKFriend]
}

// MARK: - groups.get

struct GroupsGetResponse: Decodable {
    let count: Int
    let items: [VKGroup]
}

// MARK: - video.get

struct VideoGetResponse: Decodable {
    let count: Int
    let items: [VKVideo]
}

// MARK: - messages.getConversations / messages.getHistory / messages.send

/// Peer диалога: id — user_id или 2000000000+chat_id для беседы; type: user, chat, group, email.
struct VKConversationPeer: Decodable {
    let id: Int
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
    }
}

/// Настройки беседы (название и т.д.), если есть.
struct VKConversationSettings: Decodable {
    let title: String?
}

/// Элемент conversation в getConversations.
struct VKConversation: Decodable {
    let peer: VKConversationPeer
    let chatSettings: VKConversationSettings?

    enum CodingKeys: String, CodingKey {
        case peer
        case chatSettings = "chat_settings"
    }
}

/// Последнее сообщение в диалоге (getConversations).
struct VKLastMessage: Decodable {
    let id: Int
    let date: Date
    let fromId: Int
    let text: String
    let out: Int?
    let readState: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case fromId = "from_id"
        case text
        case out
        case readState = "read_state"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        let ts = try c.decode(Int.self, forKey: .date)
        date = Date(timeIntervalSince1970: TimeInterval(ts))
        fromId = try c.decode(Int.self, forKey: .fromId)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        out = try c.decodeIfPresent(Int.self, forKey: .out)
        readState = try c.decodeIfPresent(Int.self, forKey: .readState)
    }
}

/// Элемент списка диалогов: conversation + last_message.
struct VKConversationItem: Decodable {
    let conversation: VKConversation
    let lastMessage: VKLastMessage

    enum CodingKeys: String, CodingKey {
        case conversation
        case lastMessage = "last_message"
    }
}

/// Ответ messages.getConversations (extended=1).
struct MessagesGetConversationsResponse: Decodable {
    let count: Int
    let items: [VKConversationItem]
    let profiles: [VKProfile]?
    let groups: [VKGroup]?

    enum CodingKeys: String, CodingKey {
        case count
        case items
        case profiles
        case groups
    }
}

/// Цитата (reply_message) внутри сообщения. Отдельный тип во избежание рекурсивного хранения struct.
struct VKReplyMessage: Decodable {
    let id: Int
    let fromId: Int
    let text: String

    enum CodingKeys: String, CodingKey {
        case id
        case fromId = "from_id"
        case text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        fromId = try c.decodeIfPresent(Int.self, forKey: .fromId) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

/// Сообщение в истории (messages.getHistory). Поля from_id/peer_id/date могут отсутствовать в action-сообщениях и др. — декодируем с дефолтами.
struct VKMessage: Decodable {
    let id: Int
    let fromId: Int
    let peerId: Int
    let date: Date
    let text: String
    let out: Int?
    let readState: Int?
    let replyMessage: VKReplyMessage?
    let attachments: [VKAttachment]?

    enum CodingKeys: String, CodingKey {
        case id
        case fromId = "from_id"
        case peerId = "peer_id"
        case date
        case text
        case out
        case readState = "read_state"
        case replyMessage = "reply_message"
        case attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        fromId = try c.decodeIfPresent(Int.self, forKey: .fromId) ?? 0
        peerId = try c.decodeIfPresent(Int.self, forKey: .peerId) ?? 0
        let ts = try c.decodeIfPresent(Int.self, forKey: .date) ?? 0
        date = Date(timeIntervalSince1970: TimeInterval(ts))
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        out = try c.decodeIfPresent(Int.self, forKey: .out)
        readState = try c.decodeIfPresent(Int.self, forKey: .readState)
        replyMessage = try c.decodeIfPresent(VKReplyMessage.self, forKey: .replyMessage)
        attachments = try c.decodeIfPresent([VKAttachment].self, forKey: .attachments)
    }

    /// Локальное сообщение после отправки (оптимистичное отображение).
    init(id: Int, fromId: Int, peerId: Int, date: Date, text: String, out: Int?, readState: Int?) {
        self.id = id
        self.fromId = fromId
        self.peerId = peerId
        self.date = date
        self.text = text
        self.out = out
        self.readState = readState
        self.replyMessage = nil
        self.attachments = nil
    }
}

/// Ответ messages.getHistory (extended=1). Элементы items, не прошедшие декод (вложения/репосты и т.д.), пропускаются.
struct MessagesGetHistoryResponse: Decodable {
    let count: Int
    let items: [VKMessage]
    let profiles: [VKProfile]?
    let groups: [VKGroup]?

    enum CodingKeys: String, CodingKey {
        case count
        case items
        case profiles
        case groups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decode(Int.self, forKey: .count)
        let rawItems = try c.decode([FailableDecode<VKMessage>].self, forKey: .items)
        items = rawItems.compactMap(\.value)
        profiles = try c.decodeIfPresent([VKProfile].self, forKey: .profiles)
        groups = try c.decodeIfPresent([VKGroup].self, forKey: .groups)
    }
}

/// Обёртка для элемента массива: при ошибке декода возвращает nil, не ломая весь массив.
private struct FailableDecode<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Ответ messages.send: response — одно число (message_id). Декодируем через singleValueContainer.
struct MessagesSendResponse: Decodable {
    let messageId: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        messageId = try c.decode(Int.self)
    }
}

/// Ответ photos.getMessagesUploadServer.
struct MessagesUploadServerResponse: Decodable {
    let uploadUrl: String
    enum CodingKeys: String, CodingKey { case uploadUrl = "upload_url" }
}

/// Один элемент ответа photos.saveMessagesPhoto (owner_id, id для вложения "photo{owner_id}_{id}").
struct SavedMessagesPhotoItem: Decodable {
    let id: Int
    let ownerId: Int
    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
    }
}
