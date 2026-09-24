# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Walnut (wina)** - WKWebView & SFSafariViewController 테스터 앱

WKWebView와 SFSafariViewController 설정을 실시간 테스트하는 개발자 도구. SwiftUI 기반, iOS 18.4+, ~130 Swift files

**주요 기능**:
- **WKWebView**: 설정 옵션 테스트, DevTools (Console/Network/Storage/Performance/Sources/Accessibility), 스크린샷/녹화
- **SFSafariViewController**: Safari 쿠키/세션 공유, Content Blocker, Reader Mode, Safari 확장 지원
- **공통**: URL 테스트, API Capability 감지, 북마크, 반응형 크기 조절

**Dependencies** (SPM):
- GoogleMobileAds - 광고
- UAParserSwift - User-Agent 파싱
- SwiftSoup - HTML 파싱
- Runestone + TreeSitterHTMLRunestone - 코드 하이라이팅
- SwiftUIBackports - iOS 하위 버전 호환성

## Quick Reference

### App Store Release Notes

- 2026-06-22: Walnut iOS App Store Connect app ID is `6755930250`, bundle ID is `com.kobbokkom.wina`; current API key material is read from `~/.private_keys/AuthKey_<KEY_ID>.p8`.
- For ASC REST calls on this machine, `xcrun altool --generate-jwt --verbose --apiKey ... --apiIssuer ... --p8-file-path ...` prints the JWT on stderr; parse it internally and do not log the token.
- App Review submission currently uses the modern `reviewSubmissions` flow: create/reuse review submission, create `reviewSubmissionItems` for the `appStoreVersion`, then patch the review submission with `submitted: true`. The older `appStoreVersionSubmissions` create endpoint can return a 403 that only allows DELETE.
- Newly created App Store versions may have empty `whatsNew`; copy `fastlane/metadata/*/release_notes.txt` into every `appStoreVersionLocalization` before adding the version to a review submission.
- Open (2026-09-24): `xcodebuild archive` fails under Xcode 26.6 inside the Runestone 0.5.1 SPM dependency: `UITextSearchingHelper.swift:170: protocol 'UIFindInteractionDelegate' requires 'findInteraction(_:sessionFor:)' to be available in iOS 14.0 and newer`. This is a compile error, not signing. Signing works headless: pass `-allowProvisioningUpdates` plus the App Store Connect key flags (`-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`) to both archive and `-exportArchive`, with export `signingStyle` automatic and `destination` export (the checked-in `ExportOptions.plist` uploads).

### Build & Run
```bash
# Fastest loop: boot sim + build + install + launch (Makefile)
make dev                          # default: iPhone 17 Pro, Debug, .build/DerivedData
make dev SIMULATOR="iPhone 16"    # override simulator
make dev DEVICE_ID=<udid>         # target a specific booted device
make build                        # build only
make devices                      # list available simulators
make clean-derived                # rm -rf .build/DerivedData

# Or open in Xcode
open wina.xcodeproj && Cmd+R

# Run on specific device (raw xcodebuild)
xcodebuild -project wina.xcodeproj -scheme wina -destination 'platform=iOS,name=iPhone 16,OS=latest'
```

### Code Quality (필수 - 커밋 전)
```bash
# Lint + auto-fix (필수)
swiftlint lint --fix && swiftlint lint

# Optional: Format (avoid with complex SwiftUI views - can cause regressions)
swift format format --in-place wina/SomeFile.swift

# Analyzer (separate, optional)
xcodebuild analyze -project wina.xcodeproj -scheme wina -destination generic/platform=iOS
```

**Workflow**:
1. Make changes
2. Run `swiftlint lint --fix` (auto-fixes most issues)
3. Run `swiftlint lint` again (verify all passed)
4. Commit with conventional format message
5. **DO NOT push** unless user explicitly asks

### Testing
```bash
# Run all tests
xcodebuild test -project wina.xcodeproj -scheme wina -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test file
xcodebuild test -project wina.xcodeproj -scheme wina -only-testing:winaTests/URLValidatorTests

# Run with coverage
xcodebuild test -project wina.xcodeproj -scheme wina -enableCodeCoverage YES
```

## Architecture

```
wina/
├── winaApp.swift                        # App entry point
├── ContentView.swift                    # Main view (split into extensions)
├── ContentView+URLInput.swift           # URL input handling
├── ContentViewSheets.swift              # Sheet presentations
├── Features/
│   ├── About/           # AboutView, StoreManager (IAP)
│   ├── Accessibility/   # AccessibilityAuditView (axe-core 기반)
│   ├── Ad/              # AdManager (Google AdMob interstitial + banner)
│   ├── AppBar/          # OverlayMenuBars, 버튼들
│   ├── Callback/        # URL scheme callback testing (walnut://)
│   ├── Console/         # ConsoleManager + UI (JS console 캡처 + %c styling + array chunking)
│   ├── Info/            # SharedInfoWebView, API Capability 감지, 벤치마크
│   ├── Network/         # NetworkManager + UI (fetch/XHR + scroll buttons + domain filtering)
│   ├── Performance/     # Web Vitals + Navigation Timing
│   ├── Preload/         # 시작 설정: 페이지 로드 전 주입할 쿠키/JS 프로필 (PreloadProfileStore + ScriptBuilder + CookieApplicator)
│   ├── Resources/       # Network 탭 리소스 타이밍 & 크기
│   ├── SearchText/      # SearchTextOverlay (in-page text search, Cmd+F style)
│   ├── Settings/        # SettingsView, ConfigurationSettingsView, SafariVCSettingsView, EmulationSettingsView
│   ├── Snippets/        # SnippetsView (JavaScript snippet execution)
│   ├── Sources/         # DOM Tree, Stylesheets, Scripts, CSS parsing/specificity, search
│   ├── Storage/         # Storage UI (localStorage/sessionStorage/cookies via WebViewNavigator)
│   ├── UserAgent/       # UA 커스터마이징
│   └── WebView/         # WebViewContainer, WebViewNavigator, WebViewScripts
├── Shared/
│   ├── Components/      # GlassIconButton, GlassActionButton, ChipButton, ScrollNavigationButtons, ShareSheet, JsonEditor/
│   ├── Constants/       # BarConstants (레이아웃 상수)
│   ├── Extensions/      # ColorExtensions, DeviceUtilities, URLValidator, SheetModifiers
│   └── URLStorageManager.swift  # Bookmarks & history (singleton)
└── Resources/Icons/
```

## Core Patterns

### WebView 인스턴스 관리

```swift
// URL 변경 → 히스토리 유지
navigator.loadURL(urlString)

// Configuration 변경 → 새 인스턴스 (현재 URL 기준)
webViewID = UUID()

// SafariVC → 항상 새 인스턴스 (최초 URL만 가능)
```

### Settings 패턴: Local State → Explicit Apply

```swift
@AppStorage("key") private var storedValue: Bool = false
@State private var localValue: Bool = false

private var hasChanges: Bool { localValue != storedValue }

func loadFromStorage() { localValue = storedValue }
func applyChanges() { storedValue = localValue; webViewID = UUID(); dismiss() }
func resetToDefaults() { localValue = false }  // 저장 X
```

### DevTools Overlay State 패턴 (2026.02.03)

**문제**: 여러 개의 `@State` Boolean으로 overlay 관리 시, 새 overlay 추가할 때 `onHome`에서 닫기 누락 위험

**해결**: `Set<DevToolsOverlay>` 기반 `DevToolsOverlayState` 클래스 사용

```swift
// Shared/DevToolsOverlayState.swift
enum DevToolsOverlay: String, Hashable, CaseIterable {
    case console, network, storage, performance
    case editor, accessibility, snippets, searchText
}

@Observable
final class DevToolsOverlayState {
    var active: Set<DevToolsOverlay> = []

    func open(_ overlay: DevToolsOverlay) { active.insert(overlay) }
    func close(_ overlay: DevToolsOverlay) { active.remove(overlay) }
    func toggle(_ overlay: DevToolsOverlay) { /* ... */ }
    func closeAll() { active.removeAll() }  // onHome에서 한 줄로 처리

    func binding(for overlay: DevToolsOverlay) -> Binding<Bool> {
        Binding(
            get: { self.active.contains(overlay) },
            set: { $0 ? self.open(overlay) : self.close(overlay) }
        )
    }
}

// 사용
@State private var devToolsState = DevToolsOverlayState()

// sheet에서 binding 사용
.sheet(isPresented: devToolsState.binding(for: .console)) { ... }

// onHome에서 모든 DevTools 닫기
devToolsState.closeAll()
```

### DevTools Log Clear 전략 패턴 (2026.02.25)

`Console`/`Network` 삭제 전략은 반드시 독립 키를 사용하고, 판정 시점은 `decidePolicyFor navigationAction`이 아니라 `didCommit`(실제 메인 문서 커밋 URL) 기준으로 처리한다.

```swift
// ✅ 키 분리
LogClearStrategy.consoleDefaultsKey
LogClearStrategy.networkDefaultsKey

// ✅ 커밋 URL 기준 비교
func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    applyClearStrategies(currentURL: lastCommittedMainFrameURL, newURL: webView.url)
    lastCommittedMainFrameURL = webView.url
}
```

이렇게 해야 리다이렉트/target=_blank/중간 URL 케이스에서 Same Origin 전략이 기대대로 동작한다.

### JavaScript Bridge Architecture

**Core Data Flow**:
- JavaScript hook injection → WKScriptMessageHandler → @Observable Manager → SwiftUI binding

**DevTools Managers** (`WebViewNavigator`에 포함):
- `ConsoleManager` - console.log/dir/time, %c formatting, array chunking
- `NetworkManager` - fetch/XHR interception, resource timing
- `StorageManager` - localStorage, sessionStorage, cookies (SWR pattern)

**Key Files** (WebViewScripts series):
- `WebViewScripts.swift` - Base hook injection
- `WebViewScripts+Console.swift` - console methods + %c CSS parsing
- `WebViewScripts+Network.swift` - fetch/XHR + timing API
- `WebViewScripts+Emulation.swift` - User agent, viewport
- `WebViewScripts+Resource.swift` - Static resource tracking

### JavaScript String Escape

Always use `JSONSerialization` for string safety:
```swift
// ❌ Breaks on special chars
let script = "storage.setItem('\(key)', '\(value)');"

// ✅ Safe escape
guard let keyData = try? JSONSerialization.data(withJSONObject: key, options: .fragmentsAllowed),
      let jsonKey = String(data: keyData, encoding: .utf8) else { return }
let script = "storage.setItem(\(jsonKey), ...);"  // quotes included
```

### Tree View Expand/Collapse

Use path-based stable IDs, not UUID:
```swift
// ✅ Stable ID (preserves expand state across renders)
var id: String { path.joined(separator: ".") }

// ❌ Unstable ID (loses state on re-render)
let id = UUID()  // new UUID every time
```

### Sheet Modifiers

Two styles (Shared/Extensions/SheetModifiers.swift):

| Modifier | Use | Behavior |
|----------|-----|----------|
| `.devToolsSheet()` | DevTools | Resizable (35%, medium, large), auto-expands to large on keyboard |
| `.fullSizeSheet()` | Settings/Info | Always large, `.page` sizing |

**Keyboard handling in sheets**:
```swift
// Auto-dismiss keyboard when tapping outside (use in sheet content)
.dismissKeyboardOnTap()

// DevToolsSheet auto-expands to .large when keyboard appears
```

### StoreKit 2 IAP (StoreManager)

Singleton initialized at app start:
- ✅ `Transaction.updates` listener (app start)
- ✅ `Transaction.unfinished` processing
- ✅ `transaction.finish()` always called
- ✅ `revocationDate` check (refunds)

### AdManager (Interstitial + Banner)

```swift
// Interstitial (per-session per-id, 30% probability)
await AdManager.shared.showInterstitialAd(
    options: AdOptions(id: "feature_name"),
    adUnitId: AdManager.interstitialAdUnitId
)

// Banner (non-premium only)
if !StoreManager.shared.isAdRemoved {
    BannerAdView().frame(height: 50)
}
```

---

## Design System

### Liquid Glass UI (iOS 26)

**Always use `.backport.glassEffect()` for iOS < 26 compatibility via SwiftUIBackports.**

```swift
.backport.glassEffect()                            // default
.backport.glassEffect(in: .capsule)                // capsule
.backport.glassEffect(in: .circle)                 // circle
.backport.glassEffect(in: .rect(cornerRadius: 16)) // rounded
```

**Critical: Apply to Button, not to label inside**
```swift
// ❌ WRONG - modifier on label
Button { action() } label: {
    Image(systemName: "chevron.up.circle.fill")
        .backport.glassEffect(in: .circle)  // Wrong!
}

// ✅ CORRECT - modifier on Button
Button { action() } label: {
    Image(systemName: "chevron.up.circle.fill")
}
.backport.glassEffect(in: .circle)  // Correct!
```

**State visualization pattern**:
```swift
.disabled(!canScroll)
.opacity(canScroll ? 1 : 0.3)  // Liquid Glass preserves subtle visibility
.animation(.easeInOut(duration: 0.2), value: canScroll)
```

### BarConstants (중앙화된 레이아웃)

```swift
enum BarConstants {
    static let barHeight: CGFloat = 64
    static let horizontalPadding: CGFloat = 8
    static let bottomBarSafeAreaRatio: CGFloat = 0.5
    static let webViewOffsetRatio: CGFloat = 0.375
    static let additionalSpacing: CGFloat = 64  // "App" preset
    static var totalUIHeight: CGFloat { barHeight * 2 + additionalSpacing }
    static let sheetDetents: Set<PresentationDetent> = [.fraction(0.35), .medium, .large]
    static let defaultSheetDetent: PresentationDetent = .medium
}
```

---

## Shared Components (Shared/Components/)

| Purpose | Component |
|---------|-----------|
| Circular icon button | `GlassIconButton` (.regular 44×44/18pt, .small 28×28/12pt) |
| Action button | `GlassActionButton` (.default, .destructive, .primary) |
| Copy button | `CopyButton` (text + feedback toast) |
| Type indicator | `TypeBadge` (colored label: JSON/Number/Bool/Text) |
| Chip/tag | `ChipButton`, `ToggleChipButton` |
| Info button | `InfoPopoverButton` |
| DevTools header | `DevToolsHeader` (title + button groups, String/LocalizedStringKey) |
| Scroll buttons | `ScrollNavigationButtons` + `.scrollNavigationOverlay()` |
| Settings row | `SettingToggleRow`, `ColorPickerRow` |
| WebView sizing | `WebViewSizeControl` |
| Layout | `FlowLayout` (tag/chip wrapping) |
| Security banner | `SecurityRestrictionBanner` (SafariVC warning) |
| Share sheet | `ShareSheet` (UIActivityViewController wrapper) |
| JSON editor | `JsonEditor/` (syntax-highlighted editing) |

---

## Code Conventions

| Target | Convention |
|--------|-----------|
| File names, types | PascalCase |
| Variables, functions | camelCase |
| Assets | kebab-case |
| Test files | `winaTests/[Feature]Tests.swift` |

- **Logging**: `os_log` or `Logger` (not `print()` - enforced by SwiftLint)
- 1 file 1 component, ~150 lines ideal
- Sections: `// MARK: -`
- **No barrel exports** (no index.swift)

---

## Localization (Korean)

**Settings 메뉴 번역 규칙**:
- **타이틀**: 영어 원문 유지 (App Settings, Configuration, Emulation 등)
- **설명**: 자연스러운 문장형 한국어

**LocalizedStringKey 패턴**:
- 컴포넌트 파라미터는 `LocalizedStringKey` 사용 (자동 로컬라이제이션)
- `Text(stringVariable)` where `stringVariable: String` → 로컬라이제이션 안됨
- `Text(localizedKey)` where `localizedKey: LocalizedStringKey` → 로컬라이제이션 됨

---

## SwiftLint Configuration

See `.swiftlint.yml` for full rules. Key settings:

**Disabled** (handled by swift-format):
- trailing_whitespace, trailing_comma, opening_brace, colon, comma, line_length

**Limits**:
| Rule | Warning | Error |
|------|---------|-------|
| cyclomatic_complexity | 15 | 25 |
| file_length | 1000 | 3000 |
| function_body_length | 100 | 300 |
| type_body_length | 500 | 800 |
| function_parameter_count | 6 | 8 |

**Custom rule**: `no_print_in_production` - use `os_log` or `Logger`

---

## Common Pitfalls

### 1. `.buttonStyle(.plain)` Touch Area
```swift
// ❌ Only touches icon/text pixels
Button { } label: {
    HStack { ... }
        .padding()
}
.buttonStyle(.plain)
.frame(maxWidth: .infinity)
.contentShape(Rectangle())  // WRONG: outside label

// ✅ Fix - frame + contentShape INSIDE label, after padding
Button { } label: {
    HStack { ... }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())  // CORRECT: inside label
}
.buttonStyle(.plain)
```

### 2. Compiler Type-Check Failure
```swift
// ✅ Extract complex views to @ViewBuilder
@ViewBuilder
private var complexPart: some View { ... }
```

### 3. @Observable Array Element Updates
```swift
// ❌ No update
requests[index].status = 200

// ✅ Replace entire struct
var updated = requests[index]
updated.status = 200
requests[index] = updated
```

### 4. Manager Class Missing @Observable
```swift
// ❌ UI 업데이트 안됨
class SomeManager { var isLoading = false }

// ✅ 정상 작동
@Observable
class SomeManager { var isLoading = false }
```

### 5. JSONSerialization Fragment Strings
```swift
// ✅ Option needed for top-level String
JSONSerialization.data(withJSONObject: "string", options: .fragmentsAllowed)
```

### 6. Sheet Internal Scroll Priority
```swift
.sheet(item: $item) {
    ScrollView { content }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)  // Enable scroll priority
}
```

### 7. Color.secondary/tertiary Type Mismatch
```swift
// These return ShapeStyle, not Color
// ✅ Use explicit Color for type requirements
var color: Color { .gray }

// ✅ But fine in foregroundStyle
.foregroundStyle(.secondary)
```

### 8. GeometryReader + Keyboard: Static Value Bug
```swift
// ❌ bottomPadding is let constant - won't update when keyboard appears
.overlay {
    GeometryReader { proxy in
        MyView(bottomPadding: calculatePadding(proxy.safeAreaInsets.bottom))
    }
}

// ✅ Move GeometryReader inside, or pass calculator closure
struct MyView: View {
    let paddingCalculator: (CGFloat) -> CGFloat

    var body: some View {
        GeometryReader { proxy in
            let padding = paddingCalculator(proxy.safeAreaInsets.bottom)
            // content uses dynamic padding
        }
    }
}
```

### 9. @MainActor Singleton Manager Pattern
```swift
// ✅ Correct pattern for UI-bound singleton managers
@Observable
@MainActor
final class SomeManager {
    static let shared = SomeManager()
    private init() {}

    // All properties automatically MainActor-isolated
    var someState: Bool = false
}

// Usage - no await needed when already on MainActor
func viewAction() {
    SomeManager.shared.someState = true
}
```

### 10. DevTools Clear Strategy Key 분리
```swift
// ❌ console/network가 같은 key("logClearStrategy")를 공유하면
// 한쪽 설정 변경이 다른 쪽에 즉시 반영됨

// ✅ console/network 각각 독립 key 사용
@AppStorage("consoleLogClearStrategy") var consoleStrategy = "keep"
@AppStorage("networkLogClearStrategy") var networkStrategy = "keep"

// ✅ legacy key는 1회만 마이그레이션 후 제거
// (runtime fallback을 남기면 legacy 값이 다시 주입되어 동기화 문제가 재발)

// ✅ Same Origin 비교는 host만이 아니라 scheme+host+port 기준으로 처리

// ✅ WKUIDelegate target="_blank" 경로(createWebViewWith)에서도
// navigation 전 clear 전략 적용 + snippet reset 필요
```

### 11. fetch(Request) Body Backfill 덮어쓰기 회귀
```swift
// ❌ add/start에서 placeholder("ReadableStream")가 저장된 뒤
// requestBody backfill(실제 본문) 완료 후 complete/error에서 placeholder가 다시 오면
// 실제 본문이 덮어써져 "No Request Body"처럼 보일 수 있음

// ✅ request body 갱신 시 "품질 비교" 적용
// - 실제 텍스트/JSON > placeholder(ReadablStream/Blob/File/TypedArray)
// - 낮은 품질(placeholder)은 높은 품질(실제 본문)을 덮어쓰지 않음

// ✅ 공백만 있는 본문("   \n")도 유효 요청으로 취급
// trim 후 empty 판정하면 회귀가 발생하므로 raw string 기준으로 empty 체크
```

### 12. NetworkBodyStorage 비동기 큐 경합(간헐적 nil 로드)
```swift
// ❌ save/clearAll은 queue.async인데 load가 큐 밖에서 즉시 파일을 읽으면
// 이전 작업이 끝나기 전에 읽어 간헐적으로 nil이 반환될 수 있음(테스트 플래키)

// ✅ load도 같은 직렬 큐에서 순서를 보장하도록 queue.sync로 동기화
// 단, loadAsync 내부(queue.async)에서 load 호출 시 sync 재진입 데드락 방지를 위해
// DispatchSpecificKey로 "현재 같은 큐인지" 확인 후 direct read 경로를 사용
```

---

## Troubleshooting

### Xcode Build Failures
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/*
xcodebuild clean -project wina.xcodeproj
```

### SwiftLint "Unable to Read File"
```bash
brew uninstall swiftlint && brew install swiftlint
```

### WebView JavaScript Injection Fails
- Only inline scripts work (external fetch blocked by CORS)
- Use `evaluateJavaScript()` only

### Eruda Refresh Icon Missing (WKWebView)
- Header `Refresh` (`navigationType == .reload`) 경로에서는 `didFinish`에서 Eruda를 강제 재초기화해야 아이콘 누락을 막을 수 있음.
- `didFinish` sync task 취소 시 force-init 플래그가 유실되지 않도록, 성공 완료 시점에만 플래그를 해제하고 `didFail`/`didFailProvisionalNavigation`에서 플래그 정리 필요.
- Eruda 전역 존재 여부만 체크하지 말고 `.eruda-entry-btn` 존재 여부까지 확인해 `script loaded but init not completed` 케이스를 복구할 것.

### Network Monitoring Missing
- Enable "Preserve Network Log" toggle
- SafariVC: network data unavailable (security)

---

## Version Requirements

| Tool | Version | Required |
|------|---------|----------|
| Xcode | 16.0+ | ✅ |
| iOS Target | 18.4+ | ✅ |
| SwiftLint | 0.62.2+ | ✅ (pre-commit) |
| swift-format | 6.2.1+ | 🟡 (optional) |
| Google Mobile Ads | 11.0+ | ✅ |
| Runestone | latest | ✅ |
