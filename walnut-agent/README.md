# Walnut Agent for macOS

Use `walnut-agent` to drive Walnut on your iPhone from a Mac terminal, a script, or a coding agent. The [Walnut skill](../.agents/skills/walnut/SKILL.md) guides an agent through a test run. Both the direct CLI and the optional MCP adapter use the same tools and authenticated connection to Walnut.

## Install on Mac

On a Mac with Homebrew, install the CLI from the Kobbokkom tap:

```sh
brew install kobbokkom/tap/walnut-agent
walnut-agent --version
```

For a manual install, download the macOS universal ZIP and its `.sha256` file from [GitHub Releases](https://github.com/Kobbokkom/walnut-webview-tester/releases). It supports Apple Silicon and Intel Macs running macOS 13 or later. For version 0.1.0, run this from the download folder:

```sh
archive=walnut-agent-0.1.0-macos-universal.zip
walnut_dir="$HOME/.local/share/walnut-agent"
shasum -a 256 -c "$archive.sha256" &&
  install -d "$HOME/.local/bin" "$walnut_dir" &&
  ditto -x -k "$archive" "$walnut_dir" &&
  ln -sf "$walnut_dir/Walnut Agent.app/Contents/MacOS/walnut-agent" "$HOME/.local/bin/walnut-agent" &&
  "$HOME/.local/bin/walnut-agent" --version
```

Keep the app bundle intact so macOS can verify its signature and notarization. Add `$HOME/.local/bin` to your shell's `PATH` for future terminals if needed. To build from source, clone this repository, run `swift build --package-path walnut-agent -c release` from its root, and add the path printed by `swift build --package-path walnut-agent -c release --show-bin-path` to `PATH`.

## Connect over Wi-Fi

1. Put both devices on the same Wi-Fi network. In Walnut on the iPhone, tap the network icon to open **Mac Agent**, select **Start connection**, and tap **Copy pairing code**. Allow Local Network access if prompted.
2. Run `walnut-agent pair` in a Mac terminal and paste the code into the hidden prompt. This saves the pairing in `~/.config/walnut-agent/pairing.json` with owner-only permissions. Keep the code out of agent chats.
3. Keep Walnut in the foreground and start a CLI session or ask your agent to use it.

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

The `tools` response lists the connected phone's schemas in `result.data.tools` and current mode restrictions in `result.data.unavailable`. A response contains `{"ok":true,"result":{...}}` or `{"ok":false,"error":"..."}`. Inspect the result's `runId`, `documentId` when present, `navigation`, and tool data to verify the outcome. The session keeps processing lines after a failed request and exits with status 1 at end of input if any request failed. Keep one process open so temporary settings, capture, and page interactions share the connection.

Use `walnut_browser` with action `open` and a `url` the iPhone can reach. For a development server on the Mac, use the Mac's LAN address. `localhost` inside Walnut points to the iPhone.

In WKWebView, `page_interact` action `observe` returns a `documentId`, visible control references, and viewport CSS coordinates. Pass the current document ID and coordinates to `move` or `click_at`. Walnut shows the pointer and sends page events. Use `press` for supported keys such as `A` or `Backspace`, and observe the result. Use the iPhone directly for native touch, focus, keyboard, IME, or browser shortcuts. Review and approve requested interactions and page text sharing on the iPhone.

After approval, `walnut_screenshot` saves a private PNG to the Mac. If Mac storage fails after the iPhone returns the capture, the error response retains `result.data.savedToPhotos` so you can tell whether Walnut already saved it to Photos. For a completed recording, `walnut_recording` with action `read` saves a private `.mov` file to the Mac, up to 512 MiB. Successful captures return the local file in `result.data.path`.

If the phone shows a new pairing code, run `walnut-agent pair` again. If the connection drops mid-call, check the page and run state before retrying. The interrupted action may already have taken effect.

## Connect by USB

Install `iproxy` with `brew install libusbmuxd`, attach the unlocked iPhone by USB and trust the Mac when prompted. Start Mac Agent and pair as above, then run:

```sh
walnut-agent session --usb
```

The CLI starts `iproxy` on `127.0.0.1` and forwards to the port in the pairing token. If that Mac port is in use, append `--local-port PORT`. If more than one phone is connected, append `--udid UDID` to select one. USB forwarding uses the same authenticated bridge as Wi-Fi. See the [iproxy documentation](https://github.com/libimobiledevice/libusbmuxd/blob/master/docs/iproxy.1).

## Use an MCP client

Register the same binary as a local stdio server with its absolute path as the command and `mcp` as the argument. Use `mcp --usb` for USB. The tool list comes from the connected iPhone. If the phone was unavailable at startup, reload the client after starting Mac Agent.

## Configuration and tests

Set `WALNUT_AGENT_CONFIG` to use another absolute path for the pairing file. Use the same value for pairing and for the CLI or MCP process. Delete the file to forget the saved pairing, or run `pair` again to replace it.

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

## Package a release

Run the release script on a Mac with Xcode and a Developer ID Application certificate. Set `WALNUT_NOTARY_PROFILE` to a `notarytool` Keychain profile for the distribution build.

```sh
WALNUT_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  WALNUT_NOTARY_PROFILE='walnut-release' \
  walnut-agent/scripts/package-release.sh ./release-artifacts
```

Upload the resulting ZIP and `.sha256` to the matching `walnut-agent-v<version>` GitHub release. Update the version and SHA-256 in `Casks/walnut-agent.rb` in the [Kobbokkom tap](https://github.com/Kobbokkom/homebrew-tap). Verify the public asset and run `brew install kobbokkom/tap/walnut-agent` before announcing the release.

## App Review notes

Mac Agent starts after the user opts in on the iPhone. It works while Walnut is in the foreground and can be stopped from the phone. Evaluating JavaScript, capturing a recording, reading raw sensitive data, and destructive operations require approval in Walnut. Tool definitions and sanitized evidence come from the connected device.

To reproduce, install the CLI, pair over Wi-Fi, and use a session to open a page such as `https://example.com`, check its status, and request a screenshot. Approve the capture on the phone. In SafariVC, also approve the captured preview before Walnut shares it. For a recording, approve start, stop it, then read the `.mov` on the Mac. Physical iPhone USB forwarding needs a separate device verification.
