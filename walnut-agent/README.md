# Walnut Agent for macOS

This CLI connects a Mac MCP client to Walnut on an iPhone. Commands run in the open Walnut app and return results over an authenticated TLS connection. The CLI keeps one device connection across tool calls so they can share a test run.

## Connect over Wi-Fi

From the repository root, build the Mac CLI:

```sh
swift build --package-path walnut-agent -c release
agent="$(swift build --package-path walnut-agent -c release --show-bin-path)/walnut-agent"
```

1. Connect both devices to the same local network. In Walnut on the iPhone, start a Mac Agent session and copy the pairing token. Allow Local Network access when prompted.
2. Run `"$agent" pair` in a Mac terminal and paste the token into the hidden prompt. This saves the pairing in `~/.config/walnut-agent/pairing.json` with owner-only permissions. Paste the token directly into the terminal.
3. Register the CLI as a local stdio MCP server. For Codex, run:

   ```sh
   codex mcp add walnut -- "$agent" mcp
   ```

4. Keep Walnut open in the foreground and start a new MCP client session. The tool list comes from the connected iPhone. If the phone was unavailable at startup, reload the MCP client after starting Mac Agent.

You can ask the agent to open a test URL on the iPhone and report the errors captured in that run. For a site hosted on the Mac, use an address the iPhone can reach. `localhost` in a URL opened by Walnut points to the iPhone.

For a finished recording, `walnut_recording` with action `read` saves a private `.mov` file under `~/Library/Application Support/Walnut Agent/Recordings/` and returns its path. The transfer stays on the device connection and supports recordings up to 512 MiB.

If you start a new Mac Agent session and Walnut shows a new pairing token, run `"$agent" pair` again. If a connection drops mid-call, retry only after checking the run state. The CLI does not replay the interrupted call. A new connection can start a fresh run.

## Connect by USB

Install `iproxy` with `brew install libusbmuxd`, attach the unlocked iPhone by USB and trust the Mac when prompted. Start Mac Agent and pair as above, then register the MCP server with USB enabled:

```sh
codex mcp add walnut -- "$agent" mcp --usb
```

The CLI starts `iproxy` on `127.0.0.1` and forwards to the port in the pairing token. If that Mac port is in use, append `--local-port PORT`. If more than one phone is connected, append `--udid UDID` to select one. USB forwarding uses the same authenticated bridge as Wi-Fi. See the [iproxy documentation](https://github.com/libimobiledevice/libusbmuxd/blob/master/docs/iproxy.1).

## Configuration and tests

Set `WALNUT_AGENT_CONFIG` to use another absolute path for the pairing file. Set it for both the pairing command and the MCP process. Delete the file to forget the saved pairing, or run `pair` again to replace it.

```sh
swift test --package-path walnut-agent
```

The tests cover private pairing files, request and response validation, MCP discovery and image results, and an authenticated TLS connection reused for two calls.

Run the checkout diagnostic fixture from the repository root:

```sh
python3 walnut-agent/Tests/Fixtures/checkout.py
```

To reach it from the iPhone, pass the Mac’s LAN address with `--host` and open `/checkout-a` and `/checkout-b` on port `8874`. Both routes reproduce a blank checkout with different causes.

## App Review notes

Mac Agent starts only after a user opts in on the iPhone. It works while Walnut is in the foreground and can be stopped from the phone. Evaluating JavaScript, capturing a recording, reading raw sensitive data, and destructive operations require approval in Walnut. Tool definitions and sanitized evidence come from the connected device. The companion forwards calls from a local MCP client.

To reproduce, build and register the CLI, pair it with Walnut over Wi-Fi, then ask the MCP client to open a fixture such as `https://example.com`, report the current page, and capture a screenshot. Approve the capture on the phone. For a recording, approve start, stop it, then read the `.mov` on the Mac. Physical iPhone USB forwarding needs a separate device verification.
