# Walnut Agent for macOS

Use `walnut-agent` to drive Walnut on your iPhone from a Mac terminal, a script, or a coding agent. The [Walnut skill](../.agents/skills/walnut/SKILL.md) guides an agent through a test run. Both the direct CLI and the optional MCP adapter use the same tools and authenticated connection to Walnut.

## Install on Mac

On a Mac with Homebrew, install the CLI from the Kobbokkom tap:

```sh
brew tap kobbokkom/tap
brew install --cask kobbokkom/tap/walnut-agent
walnut-agent --version
```

For a manual install, download the macOS universal ZIP and its `.sha256` file from [GitHub Releases](https://github.com/Kobbokkom/walnut-webview-tester/releases). It supports Apple Silicon and Intel Macs running macOS 13 or later. Run this from the download folder, replacing `VERSION` with the version in the ZIP filename:

```sh
archive=walnut-agent-VERSION-macos-universal.zip
walnut_dir="$HOME/.local/share/walnut-agent"
shasum -a 256 -c "$archive.sha256" &&
  install -d "$HOME/.local/bin" "$walnut_dir" &&
  ditto -x -k "$archive" "$walnut_dir" &&
  ln -sf "$walnut_dir/Walnut Agent.app/Contents/MacOS/walnut-agent" "$HOME/.local/bin/walnut-agent" &&
  "$HOME/.local/bin/walnut-agent" --version
```

Keep the app bundle intact so macOS can verify its signature and notarization. Add `$HOME/.local/bin` to your shell's `PATH` for future terminals if needed. To build from source, clone this repository, run `swift build --package-path walnut-agent -c release` from its root, and add the path printed by `swift build --package-path walnut-agent -c release --show-bin-path` to `PATH`.

## Update the CLI

Run `walnut-agent update` in Terminal. Homebrew installations refresh the tap and upgrade the Walnut Agent cask. ZIP installations in the documented location download the latest stable CLI release, verify it, and replace the app bundle and bundled skill together. Start a new CLI session after updating. For a source build, pull the repository and rebuild.

## Connect over Wi-Fi

1. Put both devices on the same Wi-Fi network. In Walnut on the iPhone, tap the network icon to open **Mac Agent**, then tap **Start connection**. Allow Local Network access if prompted.
2. Run `walnut-agent pair` in a Mac terminal. If the CLI lists multiple iPhones, select the pairing name shown in Walnut. If the pairing window expires, tap **Start pairing again**.
3. Check that the confirmation number in Terminal matches the one on your iPhone, then tap **Numbers Match** on the iPhone and enter `y` in Terminal. The iPhone saves the pairing in its Keychain, and the CLI saves its copy in `~/.config/walnut-agent/pairing.json` with owner-only permissions. Keep Walnut in the foreground and start a CLI session or ask your agent to use it.

The pairing window lasts two minutes and accepts up to five attempts. Both devices independently display the six digits from their key exchange. The iPhone shares the connection credential only after you approve. Update both Walnut and the CLI to use this pairing flow. Previously saved Mac pairings work after both updates.

After pairing, turn on **Connect automatically** in **Mac Agent**. The next time you open Walnut, run `walnut-agent session` or `walnut-agent session --usb` on your Mac. If automatic connection is off, tap **Start connection** on the iPhone first. Leaving Walnut ends the active session. **Stop connection** also turns off automatic connection. Select **Forget Mac** to revoke access or pair a different Mac. Pairings saved before this feature require one new six-digit pairing.

On the Mac, allow Local Network access if macOS prompts for Walnut Agent or the app that starts it. If you dismissed the prompt, open **System Settings → Privacy & Security → Local Network**, check that app's access, then retry the connection. If Walnut Agent is missing from the list on macOS 27.2 or later, click **+** and select the installed `Walnut Agent.app`. You can also run the CLI directly in Terminal to check the connection. See [Apple's local network privacy notes](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

You can also open **Pair with a file or copied token**. Paste the copied token into the `walnut-agent pair --token` prompt, or AirDrop the file to your Mac and run `walnut-agent pair --file PATH`. The file and token grant access to the current session until you stop it or leave Walnut. Delete the received file after pairing.

## Use with an agent

Give your agent a prompt like “Use `walnut-agent session` to check the current Walnut page on my iPhone. Query `{"op":"tools"}` first, then report the page's status.” The agent can work directly through the CLI. Approve any requested action in Walnut on the iPhone.

The optional Walnut skill teaches agents how to investigate a page and verify changes. For an agent that loads project skills from `.agents/skills`, run this from the project root:

```sh
mkdir -p .agents/skills/walnut
cp -n "$(brew --prefix)/share/walnut-agent/skill/SKILL.md" .agents/skills/walnut/SKILL.md
```

For a manual install, the skill is at `$HOME/.local/share/walnut-agent/skill/SKILL.md`. You can also ask an agent to read that file directly.

## Run tools directly

Start `walnut-agent session` and enter one UTF-8 JSON object per line, up to 256 KiB per request. Read each response before choosing the next action. Press Control-D when finished. For a fixed batch, you can pass all requests together:

```sh
walnut-agent session <<'JSONL'
{"op":"tools"}
{"op":"call","name":"walnut_browser","arguments":{"action":"status"}}
JSONL
```

The `tools` response lists the connected phone's schemas in `result.data.tools` and current mode restrictions in `result.data.unavailable`. A response contains `{"ok":true,"result":{...}}` or `{"ok":false,"error":"..."}`. Inspect the result's `runId`, `documentId` when present, `navigation`, and tool data to verify the outcome. When a page is open, `configuredBrowserSettings` reports the configured options for its mode. For WKWebView, `webViewState` reads live view properties such as zoom, size and data-store persistence, and `userAgentOverride` reports the override set on the view. The session keeps processing lines after a failed request and exits with status 1 at end of input if any request failed. Keep one process open so temporary settings, capture, and page interactions share the connection.

Use `walnut_browser` with action `open` and a `url` the iPhone can reach. For a development server on the Mac, use the Mac's LAN address. `localhost` inside Walnut points to the iPhone.

Applying or resetting emulation can reload an open WKWebView in place and preserve its back and forward history. Inspect `browserReloadRequested` and the new document ID. When `emulationNeedsNavigation` is true, open the next test page to apply the change. Walnut defers automatic reloads on form-submission pages to avoid replaying the request. A patch that also changes WKWebView configuration can recreate the browser. Disconnecting restores the saved emulation for the next document without automatically reloading the current page.

Large `console_detail` and `accessibility_detail` responses return serialized JSON in `content` chunks. Text and JSON exports can return `records` chunks from `console_list` and `export` chunks from `network_list`. Pass `nextByteOffset` as `byteOffset` with `contentId` and the same tool arguments until there is no next offset. Concatenate the chunks in order before parsing JSON. If Walnut reports that the content changed, restart from the first chunk.

Use `preload` with `action: "logs"` to list the 50 newest startup bridge logs, or set `limit: 200` to list every retained entry. Use `offset` to skip newer entries. The list contains previews when you set `raw: true` and approve sharing on the iPhone. To read a complete retained body, pass the entry's `id` as `logId` with `raw: true`. For a large record, join its `content` chunks as described above. Each body read needs iPhone approval, including continuations.

In WKWebView, `page_interact` action `observe` returns a `documentId`, visible control references, and viewport CSS coordinates. Pass the current document ID and coordinates to `move` or `click_at`. Use `fill` for text fields and plain-text editing areas, `select` for observed select options, and `press` for supported keys such as `A` or `Backspace`. For a same-origin frame, pass its `framePath` and use the `frameDocumentId` returned by observation in subsequent actions. Observe again after each change. If scrolling the main page returns `settled: false`, WebKit did not confirm the requested offset. Observe the viewport before deciding whether to scroll again. Use the iPhone directly for native touch, keyboard, IME, or browser shortcuts. Review and approve requested interactions and page text sharing on the iPhone.

After approval, `walnut_screenshot` saves a private PNG to the Mac. If Mac storage fails after the iPhone returns the capture, the error response retains `result.data.savedToPhotos` so you can tell whether Walnut already saved it to Photos. For a completed recording, `walnut_recording` with action `read` saves a private `.mov` file to the Mac, up to 512 MiB. Successful captures return the local file in `result.data.path`.

For recording, approve the request in Walnut and the separate iOS screen-capture prompt if it appears. Set `waitForStart: false` on `walnut_recording` start to get `state: starting` after Walnut and any Photos approval. Poll status on the same connection for `state: recording` or an error. A stop while starting cancels the output but may leave the iOS prompt visible. Decline a pending prompt and wait for `state: idle` before retrying. The default start waits for ReplayKit to reply.

SafariVC opens full screen with Safari's native controls. On iOS 27 or later with a ScreenCaptureKit-enabled Walnut build, choose the display in the iOS capture picker. For an agent request, review the display image on the phone before sharing it with the Mac. Walnut reduces the image size before the preview if needed to fit the transfer limit. You can also choose **Save Screenshot** in Safari's Share menu to save the capture directly to Photos at its original size. On older versions, use the iPhone's screenshot buttons. Safari's Share menu also offers **Start Recording** and **Stop Recording** where iOS supports screen recording.

To test URL callbacks, open the test page with `walnut_browser` action `callback` and trigger a callback on the iPhone. Read the received result with `callbacks` action `get`, then use action `dismiss` before continuing navigation. Dismissing the sheet keeps the result available.

The `menus` tool configures the WKWebView toolbar and App Bar. Use `visibleOrder` to send just visible item identifiers, or `items` to place visible and hidden rows in a specific order. A row has `menuItem` and `isVisible`. `get` returns both views of the active layout. Session reset reveals the saved layout, while `reset` with `persist: true` restores Walnut's default layout after approval.

If Walnut was stopped, tap **Start connection** on the iPhone and reconnect using the saved pairing. Pair again if the iPhone no longer has the saved pairing. If the connection drops mid-call, check the page and run state before retrying. The interrupted action may already have taken effect.

## Connect by USB

Install `iproxy` with `brew install libusbmuxd`, attach the unlocked iPhone by USB and trust the Mac when prompted. Start Mac Agent, then use the same code and confirmation steps:

```sh
walnut-agent pair --usb
walnut-agent session --usb
```

The CLI starts `iproxy` on `127.0.0.1`. If the Mac port is in use, append `--local-port PORT`. If more than one phone is connected, append `--udid UDID` to both commands to select one. USB forwarding uses the same authenticated bridge as Wi-Fi. See the [iproxy documentation](https://github.com/libimobiledevice/libusbmuxd/blob/master/docs/iproxy.1).

## Use an MCP client

Register the same binary as a local stdio server with its absolute path as the command and `mcp` as the argument. Use `mcp --usb` for USB. MCP requests use UTF-8 JSON lines up to 512 KiB, including the JSON-RPC envelope. The tool list comes from the connected iPhone. If the phone was unavailable at startup, reload the client after starting Mac Agent.

## Inspect the WebKit engine

The connected iPhone app must advertise the `agent_engine_inspection` tool in its live catalog.

For engine-level debugging, enable **Settings → Apps → Safari → Advanced → Web Inspector** on the iPhone and connect it to a trusted Mac. Install `uv` with `brew install uv`. Start Mac Agent, pair as above, close other Walnut CLI sessions, then run `walnut-agent inspect --udid DEVICE_UDID`. The first run resolves the pinned `pymobiledevice3` adapter on the Mac. Add `--usb` to also route Walnut commands through the USB forwarder, or `--wifi` to use an Apple-trusted network connection for Web Inspector.

To set up Web Inspector over Wi-Fi, connect the unlocked iPhone by cable first and enable **Safari → Develop → [your iPhone] → Connect via Network** on the Mac. Then disconnect the cable and keep both devices on the same network. [Apple's device inspection guide](https://developer.apple.com/documentation/safari-developer-tools/inspecting-ios)

Approve engine access to the current WKWebView document on the iPhone. When the CLI emits `event: ready`, send one JSON command per line with a positive integer `id`, a CDP `method`, and optional `params`. Read the response with the same `id` and any asynchronous events. For example, enable `Debugger`, then set a breakpoint with `Debugger.setBreakpointByUrl`, observe `Debugger.paused`, inspect its call frames, and resume or step. The ready message lists accepted methods. WebKit returns an error when a method is unavailable for the attached target.

The inspector session ends on navigation, on disconnect, or when its input closes. Start a fresh session for a new document. Code execution and other sensitive actions require confirmation on the iPhone.

Inspector commands normally wait up to 60 seconds for a WebKit reply. A breakpoint or intercepted request can hold an evaluation for up to ten minutes. An uninterrupted ten-minute pause closes the inspector and releases the page.

For HTML, `sources_list` with `section: "html"` returns the current DOM serialized as HTML (`retrieval: "live-dom"`). To read WebKit's retained resource for the authorized HTTP(S) document, call `Page.getResourceTree` in the inspector session, then pass the top frame's `id` as `frameId` and its `url` to `Page.getResourceContent`. That response reports `retrieval: "webkit-resource"` and `base64Encoded`. WebKit may return decoded text from its retained buffer, so this result cannot establish byte-for-byte identity with the original HTTP response. The lookup makes no new HTTP request. Walnut reports an error if WebKit has no content or the authorized document resource changes.

## Configuration and tests

Set `WALNUT_AGENT_CONFIG` to use another absolute path for the pairing file. Use the same value for pairing and for the CLI or MCP process. Deleting this file removes the Mac's local copy. Select **Forget Mac** on the iPhone to revoke the pairing there.

```sh
swift test --package-path walnut-agent
```

The tests cover private pairing files, an authenticated TLS connection reused for two calls, CLI response order and private PNG output, and MCP discovery and results.

Run the checkout diagnostic fixture from the repository root:

```sh
python3 walnut-agent/Tests/Fixtures/checkout.py
```

To reach it from the iPhone, pass the Mac’s LAN address with `--host` and open `/checkout-a` and `/checkout-b` on port `8874`. Both routes reproduce a blank checkout with different causes.

For the WKWebView interaction test, give your agent a goal such as “Open `/checkout-interaction` on the iPhone, submit the test shipment with delivery reference `WK-417`, and report the receipt number.” The agent can use `page_interact` to inspect the viewport, scroll to the form, fill the field, activate the button, and inspect the receipt. Approve page text sharing, filling, and activation on the iPhone when prompted.

For a repeatable device check, use a dedicated QA installation of Walnut and run `python3 walnut-agent/Tests/Fixtures/verify-device.py http://MAC_LAN_IP:8874`. Keep the fixture running and approve each test action on the iPhone. The script exercises both browser modes, saves the capture paths, and reports which advertised tools it called successfully. For a Wi-Fi-off USB test, pass `--usb --udid DEVICE_UDID` and use a fixture URL reachable by the phone over its remaining connection.

Run `--suite settings` to check live emulation, retained back history, and both menu layouts. Run `--suite log_options --alternate-origin http://MAC_LAN_IP:8875` to check Console, Network, and Resources capture, filtering, preserve on reload, and navigation clear strategies. For `log_options`, start a second copy of `checkout.py` on port `8875` so the iPhone can navigate between two fixture origins.

Run `--suite auxiliary` for WKWebView configuration, viewport size, User-Agent, and device/browser diagnostics. Run `--suite documents` for accessibility filtering, report evidence, and snippet undo. Run `--suite storage_options` for storage encoding, rename, clearing, and exact cookie scopes. The storage checks use Walnut's nonpersistent data store. Run `--suite startup_options` for temporary document-start scripts, bridge logging, disable, and reset.

For the WebKit engine check, enable **Browse in private session** on Walnut's start screen and open `/agent-e2e` on the iPhone. Close any other CLI sessions and run `python3 walnut-agent/Tests/Fixtures/verify-device.py http://MAC_LAN_IP:8874 --suite engine --udid DEVICE_UDID`. Add `--wifi` for Apple-trusted Wi-Fi inspection or `--usb` to route the Walnut connection through the USB forwarder too. Approve inspector access and the requested commands on the iPhone. This check reads the retained HTML and confirms that a breakpoint can pause an evaluation, inspect a local argument, step, and resume it.

## Package a release

Run the release script on a Mac with Xcode and a Developer ID Application certificate. Set `WALNUT_NOTARY_PROFILE` to a `notarytool` Keychain profile for the distribution build.

```sh
WALNUT_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  WALNUT_NOTARY_PROFILE='walnut-release' \
  walnut-agent/scripts/package-release.sh ./release-artifacts
```

Upload the resulting ZIP and `.sha256` to the matching `walnut-agent-v<version>` GitHub release. Update the version and SHA-256 in `Casks/walnut-agent.rb` in the [Kobbokkom tap](https://github.com/Kobbokkom/homebrew-tap). Verify the public asset and run `brew install --cask kobbokkom/tap/walnut-agent` before announcing the release.

## App Review notes

Mac Agent starts after the user opts in on the iPhone. It works while Walnut is in the foreground and can be stopped from the phone. Evaluating JavaScript, capturing a recording, reading raw sensitive data, and destructive operations require approval in Walnut. Tool definitions and sanitized evidence come from the connected device.

To reproduce, install the CLI, pair over Wi-Fi, and use a session to open a page such as `https://example.com`, check its status, and request a screenshot. Approve the capture on the phone. In SafariVC on iOS 27 or later, choose the display in the system picker and approve the captured preview before Walnut shares it. For a recording, approve start, stop it, then read the `.mov` on the Mac. Physical iPhone USB forwarding needs a separate device verification.
