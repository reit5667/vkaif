# PROJECT SPECIFICATION: CleanFeedVK (iOS)

## 1. PRODUCT VISION
A high-performance, read-only VKontakte client for iOS focused on "Digital Hygiene".
**Core Philosophy:** Speed, Offline-first, Zero Ads, Chronological Order.
**Target Audience:** Users nostalgic for "Kate Mobile" and "Old VK" functionality.

## 2. TECH STACK & ARCHITECTURE
*   **Platform:** iOS 17+.
*   **Language:** Swift 6.
*   **UI Framework:** SwiftUI (Declarative).
*   **Architecture pattern:** MVVM+ (Model - View - ViewModel - Service Layer).
*   **Concurrency:** Swift Concurrency (async/await, Actors for data isolation).
*   **Persistence (Offline Mode):** SwiftData (preferred) or SQLite/GRDB.
*   **Networking:** Native `URLSession`. No Alamofire.

## 3. CORE FEATURES (MVP Scope)

### A. Authentication (Service Layer)
*   **Method:** OAuth 2.0 Implicit Flow via `WKWebView`.
*   **Strategy:** "Kate Mobile Spoofing".
    *   **App ID:** `2685278` (Kate Mobile) to bypass new API restrictions on Wall/Messages.
    *   **Scope:** `friends,photos,audio,video,wall,groups,offline`.
    *   **Secure Storage:** Store `access_token` in **Keychain** (not UserDefaults).

### B. Feed Engine (Data Engineering Layer)
*   **API Method:** `newsfeed.get`.
*   **Parameters:** `filters=post` (Strictly posts, exclude clips/stories).
*   **Client-Side Filtering (The "Clean" logic):**
    *   Drop posts where `marked_as_ads == 1`.
    *   Drop posts where `source_type == 'promo'`.
    *   Drop posts containing keywords from user-defined Blacklist.
*   **Polymorphism Handling:**
    *   VK API JSON is inconsistent. Implement robust `Codable` structs with `enum` based decoding for Attachments (Photo, Video, Link, Doc).
    *   *Fallback:* If attachment type is unknown, render "Unsupported Content" placeholder instead of crashing.

### C. User Interface (UI Layer)
*   **Main View:** Infinite Scroll `LazyVStack`.
*   **Performance:** Prefetching data logic.
*   **Post Cell:**
    *   Header: Author Avatar, Name, Relative Date (e.g., "2h ago").
    *   Body: Text with "Show more" expansion toggle.
    *   Media: Dynamic Grid for images (1 to 10 photos layout).
    *   Footer: Metric counters (Likes, Views) - Read-only stats.

## 4. CONSTRAINTS & RULES
1.  **No Music Streaming:** Do not attempt to implement Audio API (Legal/Technical blocker).
2.  **Read-Only MVP:** No liking, commenting, or posting capabilities in Phase 1.
3.  **Error Handling:** Graceful degradation. If network fails, show cached data from SwiftData.
4.  **Code Style:**
    *   Strict typing.
    *   No Force Unwrapping (`!`).
    *   Dependency Injection for Services (for future testing).

## 5. MILESTONES
1.  **Skeleton:** Project setup, DI Container, Network Layer base.
2.  **Auth:** Working Login Flow returning a valid Token.
3.  **Data Pipeline:** Fetch JSON -> Parse -> Filter -> Print to Console.
4.  **UI Integration:** Connect Data Pipeline to SwiftUI List.
5.  **Offline Cache:** Save feed to DB, load from DB on launch.
