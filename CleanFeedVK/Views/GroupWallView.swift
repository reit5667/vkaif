import SwiftUI

/// Страница группы: инфо (groups.getById) + лента постов (wall.get).
struct GroupWallView: View {
    @ObservedObject var authService: AuthService
    /// ID группы (положительное число, например 12345).
    let groupId: Int

    @State private var group: VKGroup?
    @State private var posts: [VKPost] = []
    @State private var profiles: [VKProfile] = []
    @State private var groups: [VKGroup] = []
    @State private var loadState: GroupWallLoadState = .idle
    @State private var commentsContext: PostCommentsContext? = nil
    @State private var postLikeOverrides: [String: Int] = [:]
    @State private var postLikedOverrides: [String: Bool] = [:]
    @State private var likeInProgress: Set<String> = []
    @State private var postRepostOverrides: [String: Int] = [:]
    @State private var repostInProgress: Set<String> = []
    @State private var showRepostDMStub = false
    @State private var videoPlayerURL: URL? = nil
    @State private var videoPlayerPost: VKPost? = nil

    private let vkApi = VKApiService()
    private var ownerId: Int { -groupId }

    enum GroupWallLoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Загрузка…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let g = group {
                            groupHeader(group: g)
                        }
                        ForEach(posts, id: \.postId) { post in
                            groupWallPostRow(post)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .navigationTitle(group?.name ?? "Группа")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if case .loaded = loadState {
                    Button("Обновить") { load() }
                }
            }
        }
        .onAppear { load() }
        .sheet(item: $commentsContext) { ctx in
            PostCommentsView(context: ctx, authService: authService)
        }
        .fullScreenCover(isPresented: Binding(
            get: { videoPlayerURL != nil },
            set: { if !$0 { videoPlayerURL = nil; videoPlayerPost = nil } }
        )) {
            if let url = videoPlayerURL {
                groupWallVideoPlayerContent(url: url)
            }
        }
        .alert("Репост в личку", isPresented: $showRepostDMStub) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Скоро. Раздел сообщений в разработке.")
        }
    }

    @ViewBuilder
    private func groupWallVideoPlayerContent(url: URL) -> some View {
        let post = videoPlayerPost
        let ctx: VideoPlayerPostContext? = post.map { p in
            VideoPlayerPostContext(
                likesCount: postLikeOverrides[p.postId] ?? p.likesCount,
                commentsCount: p.commentsCount,
                isLiked: postLikedOverrides[p.postId] ?? (p.likes?.userLikes == 1),
                onLike: { likeToggle(p) },
                onTapComments: {
                    commentsContext = PostCommentsContext(
                        ownerId: p.ownerId ?? ownerId,
                        postId: p.id,
                        totalCount: p.commentsCount
                    )
                }
            )
        }
        VideoPlayerView(url: url, onDismiss: { videoPlayerURL = nil; videoPlayerPost = nil }, postContext: ctx)
    }

    private func groupHeader(group: VKGroup) -> some View {
        HStack(spacing: 12) {
            Group {
                if let urlString = group.photo50, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure, .empty: Image(systemName: "person.3.fill").resizable().foregroundStyle(.secondary)
                        @unknown default: EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "person.3.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            Text(group.name ?? "Группа \(group.id)")
                .font(.headline)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func groupWallPostRow(_ post: VKPost) -> some View {
        let repostCount = postRepostOverrides[post.postId]
        let repostLoading = repostInProgress.contains(post.postId)
        let repostToWallAction: (() -> Void)? = repostLoading ? nil : { repostToWall(post) }
        return Group {
            PostCellView(
                post: post,
                authorName: group?.name ?? "Группа",
                authorAvatarURL: group?.photo50,
                relativeDate: relativeDateString(from: post.date),
                profiles: profiles,
                groups: groups,
                authService: nil,
                feedDestination: nil,
                onTapComments: {
                    commentsContext = PostCommentsContext(
                        ownerId: post.ownerId ?? ownerId,
                        postId: post.id,
                        totalCount: post.commentsCount
                    )
                },
                likesCountOverride: postLikeOverrides[post.postId],
                isLikedOverride: postLikedOverrides[post.postId],
                onLike: likeInProgress.contains(post.postId) ? nil : { likeToggle(post) },
                likeInProgress: likeInProgress.contains(post.postId),
                onTapVideo: { video, ownerId, post in
                    var url: URL?
                    if let p = video.player, let u = URL(string: p) {
                        url = u
                    } else {
                        let token = await MainActor.run { authService.accessToken } ?? ""
                        if !token.isEmpty,
                           let res = try? await vkApi.getVideo(token: token, videos: video.videoGetId(ownerFallback: ownerId)),
                           let first = res.items.first,
                           let playerURL = first.player {
                            url = URL(string: playerURL)
                        }
                    }
                    await MainActor.run {
                        videoPlayerURL = url
                        videoPlayerPost = post
                    }
                },
                pollVoteOverrides: nil,
                onPollVote: nil,
                pollVoteInProgress: [],
                repostsCountOverride: repostCount,
                onRepostToWall: repostToWallAction,
                onRepostToDM: { showRepostDMStub = true },
                repostInProgress: repostLoading,
                onAddToSaved: { token, oid, pid, key in await addPhotoToSaved(token: token, ownerId: oid, photoId: pid, accessKey: key) },
                getAccessToken: { authService.accessToken ?? "" }
            )
        }
        .padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    private func load() {
        guard let token = authService.accessToken else { return }
        loadState = .loading
        Task {
            do {
                async let groupTask = vkApi.getGroupById(token: token, groupId: groupId)
                async let wallTask = vkApi.getWall(token: token, ownerId: ownerId)
                let g = try? await groupTask
                let wall = try await wallTask
                await MainActor.run {
                    group = g
                    posts = wall.items
                    profiles = wall.profiles ?? []
                    groups = wall.groups ?? []
                    loadState = .loaded
                }
            } catch {
                await MainActor.run { loadState = .failed(error) }
            }
        }
    }

    private func likeToggle(_ post: VKPost) {
        guard let token = authService.accessToken else { return }
        let ownerId = post.ownerId ?? self.ownerId
        let pid = post.postId
        if likeInProgress.contains(pid) { return }
        let isLiked = postLikedOverrides[pid] ?? (post.likes?.userLikes == 1)
        likeInProgress.insert(pid)
        Task {
            do {
                let newCount: Int
                if isLiked {
                    newCount = try await vkApi.likesDelete(
                        token: token,
                        type: "post",
                        ownerId: ownerId,
                        itemId: post.id
                    )
                    await MainActor.run {
                        postLikeOverrides[pid] = newCount
                        postLikedOverrides[pid] = false
                        likeInProgress.remove(pid)
                    }
                } else {
                    newCount = try await vkApi.likesAdd(
                        token: token,
                        type: "post",
                        ownerId: ownerId,
                        itemId: post.id
                    )
                    await MainActor.run {
                        postLikeOverrides[pid] = newCount
                        postLikedOverrides[pid] = true
                        likeInProgress.remove(pid)
                    }
                }
            } catch {
                await MainActor.run { likeInProgress.remove(pid) }
            }
        }
    }

    private func repostToWall(_ post: VKPost) {
        guard let token = authService.accessToken else { return }
        let oid = post.ownerId ?? ownerId
        guard oid != 0 else { return }
        let pid = post.postId
        if repostInProgress.contains(pid) { return }
        repostInProgress.insert(pid)
        let object = "wall\(oid)_\(post.id)"
        Task {
            do {
                let response = try await vkApi.wallRepost(token: token, object: object)
                await MainActor.run {
                    if let newCount = response.repostsCount {
                        postRepostOverrides[pid] = newCount
                    }
                    repostInProgress.remove(pid)
                }
            } catch {
                await MainActor.run { repostInProgress.remove(pid) }
            }
        }
    }

    private func addPhotoToSaved(token: String, ownerId: Int, photoId: Int, accessKey: String? = nil) async -> Bool {
        guard !token.isEmpty else {
            AppLogger.shared.error("Gallery", "addPhotoToSaved: empty token")
            return false
        }
        do {
            _ = try await vkApi.photosCopy(token: token, ownerId: ownerId, photoId: photoId, accessKey: accessKey)
            return true
        } catch {
            AppLogger.shared.error("Gallery", "addPhotoToSaved failed ownerId=\(ownerId) photoId=\(photoId)", error: error)
            return false
        }
    }
}
