import SwiftUI

/// Ячейка поста в ленте. Вынесена в отдельный файл, чтобы избежать неоднозначности типа компилятора в ContentView.
struct FeedPostRowCell: View {
    let post: VKPost
    let authorName: String
    let authorAvatarURL: String?
    let relativeDate: String
    let profiles: [VKProfile]
    let groups: [VKGroup]
    let authService: AuthService
    let feedDestination: FeedDestination?
    let onTapComments: () -> Void
    let likesCountOverride: Int?
    let isLikedOverride: Bool?
    let likeInProgress: Bool
    let onLike: (() -> Void)?
    let onTapVideo: (VKVideo, Int, VKPost) async -> Void
    let pollVoteOverrides: [String: PollVoteOverride]?
    let onPollVote: ((VKPost, VKPoll, Int) -> Void)?
    let pollVoteInProgress: Set<String>
    let repostsCountOverride: Int?
    let onRepostToWall: (() -> Void)?
    let onRepostToDM: (() -> Void)?
    let repostInProgress: Bool
    let canDeletePost: Bool
    let onDelete: (() -> Void)?
    let deleteInProgress: Bool
    let onDeletePhoto: ((String, Int, Int) async -> Bool)?
    var onMakeProfilePhoto: ((String, Int, Int) async -> Bool)? = nil
    let onAddToSaved: (String, Int, Int, String?) async -> Bool
    let getAccessToken: () -> String

    var body: some View {
        PostCellView(
            post: post,
            authorName: authorName,
            authorAvatarURL: authorAvatarURL,
            relativeDate: relativeDate,
            profiles: profiles,
            groups: groups,
            authService: authService,
            feedDestination: feedDestination,
            onTapComments: onTapComments,
            likesCountOverride: likesCountOverride,
            isLikedOverride: isLikedOverride,
            onLike: onLike,
            likeInProgress: likeInProgress,
            onTapVideo: onTapVideo,
            pollVoteOverrides: pollVoteOverrides,
            onPollVote: onPollVote,
            pollVoteInProgress: pollVoteInProgress,
            repostsCountOverride: repostsCountOverride,
            onRepostToWall: onRepostToWall,
            onRepostToDM: onRepostToDM,
            repostInProgress: repostInProgress,
            canDeletePost: canDeletePost,
            onDelete: onDelete,
            deleteInProgress: deleteInProgress,
            onDeletePhoto: onDeletePhoto,
            onMakeProfilePhoto: onMakeProfilePhoto,
            onAddToSaved: onAddToSaved,
            getAccessToken: getAccessToken
        )
        .padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }
}
