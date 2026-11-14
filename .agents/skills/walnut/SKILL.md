---
name: walnut
description: Drive the paired Walnut app on an iPhone from a Mac to reproduce a web issue, inspect developer tools, interact with a WKWebView page, or capture test evidence. Use for tests explicitly targeting Walnut or an iPhone WebView through Walnut.
---

# Walnut

Use `walnut-agent session`. If the CLI or pairing is missing, follow the install and pairing steps in the [Walnut Agent guide](https://github.com/Kobbokkom/walnut-webview-tester/tree/walnut-agent-v0.1.4/walnut-agent#install-on-mac). Run `walnut-agent pair` (`pair --usb` for USB) in a terminal where the user can compare the six digits on both devices, approve on the phone, and answer the Terminal prompt. The user can also import a pairing file with `walnut-agent pair --file PATH`. Keep pairing credentials out of chat. Keep Walnut open in the iPhone foreground. Use `session --usb` when the connection is configured for USB.

If a saved Mac pairing cannot connect, keep Walnut open. The user can turn on **Connect automatically** in **Mac Agent** to accept future connections when Walnut opens, or tap **Start connection** to connect now.

Keep one process with stdin and stdout open for the full run. Send one JSON line and read one JSON response before choosing the next call. Use a here-document for independent requests or a fixed sequence whose steps do not depend on previous outcomes.

```jsonl
{"op":"tools"}
{"op":"call","name":"walnut_browser","arguments":{"action":"status"}}
```

- Read the phone's schemas in `result.data.tools` and mode restrictions in `result.data.unavailable`. For a Mac-hosted development site, use a URL the phone can reach, such as the Mac's LAN address. `localhost` resolves to the phone.
- For a blank or broken page, read the navigation state and use `network_list` and `console_list` to look for HTTP failures and script errors. Ensure capture is enabled, then reload if necessary. Use `documentId` to correlate observations to the failing document. Compare `runId`, navigation state, and any applied User-Agent override when changing settings between attempts.
- For page interaction, use `page_interact` with `observe` to get the current document ID, visible control references, and viewport coordinates. Use those for scroll, fill, click, pointer, or supported key actions. Use `select` with `optionIndexes` from observation, or `values` when the option values are unique. For an accessible same-origin frame, observe with its `framePath` and include the returned `frameDocumentId` in later actions. Observe again after each change before reusing a reference or claiming the action worked.
- Let the person at the iPhone review any approval prompt. Inspect `ok` and the returned evidence after each call. If a call fails or disconnects, recheck the run state before retrying a mutation. For an approved capture, use the Mac path in `result.data.path`.
- For recording, use `walnut_recording` start with `waitForStart: false` when the live schema supports it. Poll status on the same connection while the person responds to the separate iOS screen-capture prompt. Wait for `recording` before capturing activity, then stop and read when status reports `available: true`.

Close stdin when done. Report the observed outcome and any step you could not verify.

When the task needs engine breakpoints, stepping, profiling, or debugger scopes, use the separate `walnut-agent inspect --udid DEVICE_UDID` session with a trusted iPhone, Web Inspector enabled, and `uv` installed on the Mac. Close the ordinary Walnut session first. The phone user approves the current document. Read the inspector's ready event and accepted methods. Send one CDP JSON object per line with `id`, `method`, and optional `params`; match replies by `id` and observe actual events such as `Debugger.paused` before claiming a breakpoint worked. Resume the page and close stdin when done. Navigation ends the grant.
