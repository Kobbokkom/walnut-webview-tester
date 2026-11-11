import Foundation

enum SourceResourceScript {
    enum Kind: String {
        case script, stylesheet

        var collection: String { self == .script ? "document.scripts" : "document.styleSheets" }
    }

    static let selection = """
    function sourceSelection(source, kind) {
        const selections = globalThis.__walnutSourceSelections ??= new WeakMap();
        const owner = kind === 'script' ? source : source.ownerNode;
        const current = {
            url: (kind === 'script' ? source.src : source.href) || '',
            credentials: owner?.crossOrigin === 'use-credentials' ? 'include' : 'same-origin',
            referrerPolicy: owner?.referrerPolicy || 'no-referrer'
        };
        const previous = selections.get(source);
        if (previous && Object.keys(current).every(key => current[key] === previous[key])) return previous;
        current.identity = crypto.getRandomValues(new Uint32Array(4)).join('-');
        selections.set(source, current);
        return current;
    }
    """

    static func capture(_ kind: Kind, index: Int) -> String {
        """
        (() => {
            \(selection)
            const source = \(kind.collection)[\(index)];
            if (!source) return JSON.stringify({error: 'Source not found.'});
            const selected = sourceSelection(source, '\(kind.rawValue)');
            let label = '';
            if (selected.url) {
                label = 'External source';
                try {
                    const url = new URL(selected.url);
                    if (['http:', 'https:'].includes(url.protocol)) label = (url.origin + url.pathname).slice(0, 512).toWellFormed();
                } catch (_) {}
            }
            return JSON.stringify({identity: selected.identity, label, credentials: selected.credentials});
        })()
        """
    }

    static func read(_ kind: Kind, index: Int, expected: String, body: String) -> String {
        """
        (async function() {
            \(selection)
            \(fetch)
            const source = \(kind.collection)[\(index)];
            const approved = source && sourceSelection(source, '\(kind.rawValue)');
            if (!approved || approved.identity !== \(JavaScriptLiteral.quoted(expected))) {
                return JSON.stringify({error: 'The selected source changed. Refresh Sources and select it again.'});
            }
            try {
                \(body)
            } catch (error) {
                return JSON.stringify({error: error.message});
            }
        })()
        """
    }

    private static let fetch = #"""
    async function fetchSource(rawURL, credentials, referrerPolicy) {
        const url = new URL(rawURL, document.baseURI);
        if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
            throw new Error('Source retrieval supports HTTP and HTTPS resources without URL credentials.');
        }
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 10000);
        const maximum = 8 * 1024 * 1024;
        try {
            const response = await fetch(url.href, {
                mode: 'cors', credentials, referrerPolicy,
                signal: controller.signal
            });
            if (!response.ok) throw new Error('Source request failed with HTTP ' + response.status + '.');
            if (Number(response.headers.get('Content-Length')) > maximum) {
                throw new Error('Source exceeds the 8 MiB retrieval limit.');
            }
            if (!response.body) throw new Error('Source response has no readable body.');
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            const parts = [];
            let bytes = 0;
            try {
                while (true) {
                    const {value, done} = await reader.read();
                    if (done) break;
                    bytes += value.byteLength;
                    if (bytes > maximum) throw new Error('Source exceeds the 8 MiB retrieval limit.');
                    parts.push(decoder.decode(value, {stream: true}));
                }
                parts.push(decoder.decode());
                return parts.join('');
            } finally {
                await reader.cancel().catch(() => {});
            }
        } catch (error) {
            if (controller.signal.aborted) throw new Error('Source request timed out.');
            if (error instanceof TypeError) throw new Error('Source is unavailable under this page\'s CORS or network policy.');
            throw error;
        } finally {
            clearTimeout(timeout);
        }
    }
    """#
}
