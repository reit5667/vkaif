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
    let onDelete: () -> Void
    let onDeletePhoto: (String, Int, Int) async -> Bool
    let onAddToSaved: (String, Int, Int, String?) async -> Bool
    let getAccessToken: () -> String

    var body: some View {
        makeCell().padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    private func makeCell() -> PostCellView {
        let tapVideo: (VKVideo, Int, VKPost) async -> Void = onTapVideo
        let deletePhoto: ((String, Int, Int) async -> Bool)? = isOwnProfile ? Optional(onDeletePhoto) : nil
        let addToSaved: (String, Int, Int, String?) async -> Bool = onAddToSaved
        let tokenProvider: () -> String = getAccessToken
        return PostCellView(
            post: post,
            authorName: user.displayName,
            authorAvatarURL: user.avatarURL,
            relativeDate: relativeDateString(from: post.date),
            profiles: profiles,
            groups: groups,
            authService: authService,
            feedDestination: nil,
            onTapComments: onTapComments,
            likesCountOverride: postLikeOverrides,
            isLikedOverride: postLikedOverrides,
            onLike: likeInProgress ? nil : onLike,
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
            onDelete: (isOwnProfile && onDeletePost != nil) ? onDelete : nil,
            deleteInProgress: deleteInProgress,
            onDeletePhoto: deletePhoto,
            onAddToSaved: addToSaved,
            getAccessToken: tokenProvider
        )
    }
}
