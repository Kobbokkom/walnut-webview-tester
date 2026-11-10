---
name: walnut
description: Drive the paired Walnut app on an iPhone from a Mac to reproduce a web issue, inspect developer tools, interact with a WKWebView page, or capture test evidence. Use for tests explicitly targeting Walnut or an iPhone WebView through Walnut.
---

# Walnut

Use `walnut-agent session`. If the CLI or pairing is missing, follow the build and pairing steps in the [Walnut Agent guide](../../../walnut-agent/README.md). The user enters the pairing code in the Mac terminal's hidden prompt. Keep Walnut open in the iPhone foreground. Use `session --usb` when the connection is configured for USB.

Keep one process with stdin and stdout open for the full run. Send one JSON line and read one JSON response before choosing the next call. Use a here-document for independent requests or a fixed sequence whose steps do not depend on previous outcomes.

```jsonl
{"op":"tools"}
{"op":"call","name":"walnut_browser","arguments":{"action":"status"}}
```

- Read the phone's schemas in `result.data.tools` and mode restrictions in `result.data.unavailable`. For a Mac-hosted development site, use a URL the phone can reach, such as the Mac's LAN address. `localhost` resolves to the phone.
- For a blank or broken page, read the navigation state and use `network_list` and `console_list` to look for HTTP failures and script errors. Ensure capture is enabled, then reload if necessary. Use `documentId` to correlate observations to the failing document. Compare `runId`, navigation state, and any applied User-Agent override when changing settings between attempts.
- For page interaction, use `page_interact` with `observe` to get the current document ID, visible control references, and viewport coordinates. Use those for scroll, fill, click, pointer, or supported key actions. Observe again after each change before reusing a reference or claiming the action worked.
- Let the person at the iPhone review any approval prompt. Inspect `ok` and the returned evidence after each call. If a call fails or disconnects, recheck the run state before retrying a mutation. For an approved capture, use the Mac path in `result.data.path`.

Close stdin when done. Report the observed outcome and any step you could not verify.
