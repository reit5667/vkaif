import SwiftUI

/// Ячейка поста на стене профиля. Вынесена в отдельный файл, чтобы избежать сбоя компилятора на сложном выражении в ProfileTabsView.
struct ProfileWallPostCell: View {
    let post: VKPost
    let user: VKUserDetail
    let profiles: [VKProfile]
    let groups: [VKGroup]
    let authService: AuthService
    let ownerId: Int
    let isOwnProfile: Bool
    let onDeletePost: ((VKPost) -> Void)?
    @Binding var commentsContext: PostCommentsContext?
    let postLikeOverrides: Int?
    let postLikedOverrides: Bool?
    let likeInProgress: Bool
    let repostCount: Int?
    let repostLoading: Bool
    let deleteInProgress: Bool
    let onTapComments: () -> Void
    let onLike: () -> Void
    let onTapVideo: (VKVideo, Int, VKPost) async -> Void
    let onRepostToWall: () -> Void
    let onRepostDM: () -> Void
    /// После успешного репоста из fullscreen галереи.
    var onRepostSuccessFromGallery: ((Int) -> Void)? = nil
    let onDelete: () -> Void
    let onPin: (() -> Void)?
    let onUnpin: (() -> Void)?
    let isPinned: Bool
    let pinInProgress: Bool
    let onDeletePhoto: (String, Int, Int) async -> Bool
    /// Сделать фото главным в профиле (photos.makeCover). Возвращает (успех, сообщение об ошибке). nil = пункт не показывать.
    var onMakeProfilePhoto: ((String, Int, Int) async -> (Bool, String?))? = nil
    let vkApi: VKApiService?
    let getAccessToken: () -> String

    var body: some View {
        cellView.padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    private var cellView: PostCellView {
        let onLikeArg: (() -> Void)? = likeInProgress ? nil as (() -> Void)? : onLike
        let onDeleteArg: (() -> Void)? = (isOwnProfile && onDeletePost != nil) ? onDelete : nil as (() -> Void)?
        let onDeletePhotoArg: ((String, Int, Int) async -> Bool)? = isOwnProfile ? onDeletePhoto : nil as ((String, Int, Int) async -> Bool)?
        let feedDest: FeedDestination? = nil
        let tapVideo: (VKVideo, Int, VKPost) async -> Void = onTapVideo
        let tokenProvider: () -> String = getAccessToken
        let makeProfile: ((String, Int, Int) async -> (Bool, String?))? = isOwnProfile ? onMakeProfilePhoto : nil as ((String, Int, Int) async -> (Bool, String?))?
        return PostCellView(
            post: post,
            authorName: user.displayName,
            authorAvatarURL: user.avatarURL,
            relativeDate: relativeDateString(from: post.date),
            calendarDate: calendarDateString(from: post.date),
            profiles: profiles,
            groups: groups,
            authService: authService,
            feedDestination: feedDest,
            onTapComments: onTapComments,
            likesCountOverride: postLikeOverrides,
            isLikedOverride: postLikedOverrides,
            onLike: onLikeArg,
            likeInProgress: likeInProgress,
            onTapVideo: tapVideo,
            pollVoteOverrides: nil,
            onPollVote: nil,
            pollVoteInProgress: [],
            repostsCountOverride: repostCount,
            onRepostToWall: onRepostToWall,
            onRepostToDM: onRepostDM,
            repostInProgress: repostLoading,
            canDeletePost: isOwnProfile && onDeletePost != nil,
            onDelete: onDeleteArg,
            deleteInProgress: deleteInProgress,
            canPinPost: isOwnProfile,
            isPinned: isPinned,
            onPin: onPin,
            onUnpin: onUnpin,
            pinInProgress: pinInProgress,
            onDeletePhoto: onDeletePhotoArg,
            onMakeProfilePhoto: makeProfile,
            onRepostSuccessFromGallery: onRepostSuccessFromGallery,
            vkApi: vkApi,
            getAccessToken: tokenProvider
        )
    }
}
