//
//  SourcesManager.swift
//  wina
//
//  Sources panel data manager and models.
//

import Foundation

// MARK: - Models

struct DOMNode: Identifiable, Hashable {
    /// Path-based stable ID (e.g., "0.1.3" for root -> child 1 -> child 3)
    /// This ensures expand/collapse state is preserved across re-parses
    let path: [Int]
    let nodeType: Int
    let nodeName: String
    let attributes: [String: String]
    let textContent: String?
    var children: [DOMNode]
    var isExpanded: Bool = false

    /// Stable ID derived from path (e.g., "0.1.3")
    var id: String { path.map(String.init).joined(separator: ".") }

    var isElement: Bool { nodeType == 1 }
    var isText: Bool { nodeType == 3 }

    var displayName: String {
        if isText {
            return textContent ?? ""
        }
        var result = nodeName.lowercased()
        if let attrId = attributes["id"] {
            result += "#\(attrId)"
        }
        if let className = attributes["class"], !className.isEmpty {
            let classes = className.split(separator: " ").prefix(2).joined(separator: ".")
            result += ".\(classes)"
        }
        return result
    }
}

struct StylesheetInfo: Identifiable {
    let id = UUID()
    let index: Int
    let href: String?
    let rulesCount: Int
    let isExternal: Bool
    let mediaText: String?
    let cssContent: String? // For search - inline CSS or fetched rules
}

struct ScriptInfo: Identifiable {
    let id = UUID()
    let index: Int
    let src: String?
    let isExternal: Bool
    let isModule: Bool
    let isAsync: Bool
    let isDefer: Bool
    let content: String? // For search - inline script content only
}

// MARK: - Sources Manager

@MainActor
@Observable
class SourcesManager {
    var domTree: DOMNode?
    var rawHTML: String?
    var stylesheets: [StylesheetInfo] = []
    var scripts: [ScriptInfo] = []
    var isLoading: Bool = false
    var errorMessage: String?
    /// Incremented each time domTree is updated (for change detection)
    var domTreeRevision: Int = 0

    private weak var navigator: WebViewNavigator?

    func setNavigator(_ navigator: WebViewNavigator?) {
        self.navigator = navigator
    }

    // MARK: - DOM Tree

    static let domTreeScript = """
    (function() {
        function serializeNode(node, depth) {
            if (depth > 50) return null;
            const obj = {
                type: node.nodeType,
                name: node.nodeName,
                attrs: {},
                text: null,
                children: []
            };
            if (node.nodeType === 1) {
                for (const attr of node.attributes) {
                    obj.attrs[attr.name] = attr.value;
                }
            }
            if (node.nodeType === 3) {
                const text = node.textContent.trim();
                if (text.length === 0) return null;
                obj.text = text.substring(0, 200);
            }
            for (const child of node.childNodes) {
                const serialized = serializeNode(child, depth + 1);
                if (serialized) obj.children.push(serialized);
            }
            return obj;
        }
        return JSON.stringify(serializeNode(document.documentElement, 0));
    })();
    """

    static func nodeLookupScript(path: [Int]) -> String {
        """
        (function() {
            const path = [\(path.map(String.init).joined(separator: ","))];
            if (path[0] !== 0) return null;
            let node = document.documentElement;
            for (const index of path.slice(1)) {
                if (!node) return null;
                // Match serializeNode's omission of whitespace-only text nodes.
                const children = Array.from(node.childNodes).filter(child =>
                    child.nodeType !== 3 || child.textContent.trim().length > 0);
                node = children[index];
            }
            return node || null;
        })()
        """
    }

    func fetchDOMTree() async {
        guard let navigator else {
            errorMessage = "Navigator not available"
            return
        }

        isLoading = true
        errorMessage = nil

        if let result = await navigator.evaluateJavaScript(Self.domTreeScript) as? String,
           let data = result.data(using: .utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                domTree = parseNode(json, path: [0])
                domTreeRevision += 1
            } catch {
                errorMessage = "Failed to parse DOM: \(error.localizedDescription)"
            }
        } else {
            errorMessage = "Failed to fetch DOM tree"
        }

        isLoading = false
    }

    // MARK: - Raw HTML

    static let rawHTMLScript = """
    (function() {
        const doctype = document.doctype;
        let doctypeStr = '';
        if (doctype) {
            doctypeStr = '<!DOCTYPE ' + doctype.name;
            if (doctype.publicId) {
                doctypeStr += ' PUBLIC "' + doctype.publicId + '"';
            }
            if (doctype.systemId) {
                doctypeStr += ' "' + doctype.systemId + '"';
            }
            doctypeStr += '>\\n';
        }
        return doctypeStr + document.documentElement.outerHTML;
    })();
    """

    func fetchRawHTML() async {
        guard let navigator else {
            errorMessage = "Navigator not available"
            return
        }

        isLoading = true
        errorMessage = nil

        if let result = await navigator.evaluateJavaScript(Self.rawHTMLScript) as? String {
            rawHTML = result
        } else {
            errorMessage = "Failed to fetch HTML"
        }

        isLoading = false
    }

    private func parseNode(_ json: [String: Any]?, path: [Int]) -> DOMNode? {
        guard let json else { return nil }

        let nodeType = json["type"] as? Int ?? 0
        let nodeName = json["name"] as? String ?? ""
        let attrs = json["attrs"] as? [String: String] ?? [:]
        let text = json["text"] as? String
        let childrenJson = json["children"] as? [[String: Any]] ?? []

        // Build children with indexed paths
        var children: [DOMNode] = []
        for (index, childJson) in childrenJson.enumerated() {
            let childPath = path + [index]
            if let child = parseNode(childJson, path: childPath) {
                children.append(child)
            }
        }

        return DOMNode(
            path: path,
            nodeType: nodeType,
            nodeName: nodeName,
            attributes: attrs,
            textContent: text,
            children: children
        )
    }

    // MARK: - Stylesheets

    static let stylesheetsScript = """
    (function() {
        const sheets = [];
        for (const sheet of document.styleSheets) {
            let rulesCount = 0;
            let cssContent = null;
            try {
                if (sheet.cssRules) {
                    rulesCount = sheet.cssRules.length;
                    // Collect CSS content for search (selectors + properties)
                    const parts = [];
                    for (const rule of sheet.cssRules) {
                        if (rule.cssText) parts.push(rule.cssText);
                    }
                    cssContent = parts.join('\\n');
                }
            } catch(e) {
                // CORS: external stylesheets can't access cssRules
            }
            sheets.push({
                href: sheet.href,
                rulesCount: rulesCount,
                isExternal: !!sheet.href,
                media: sheet.media ? sheet.media.mediaText : null,
                cssContent: cssContent
            });
        }
        return JSON.stringify(sheets);
    })();
    """

    func fetchStylesheets() async {
        guard let navigator else {
            errorMessage = "Navigator not available"
            return
        }

        isLoading = true
        errorMessage = nil

        if let result = await navigator.evaluateJavaScript(Self.stylesheetsScript) as? String,
           let data = result.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            stylesheets = jsonArray.enumerated().map { idx, item in
                StylesheetInfo(
                    index: idx,
                    href: item["href"] as? String,
                    rulesCount: item["rulesCount"] as? Int ?? 0,
                    isExternal: item["isExternal"] as? Bool ?? false,
                    mediaText: item["media"] as? String,
                    cssContent: item["cssContent"] as? String
                )
            }
        } else {
            errorMessage = "Failed to fetch stylesheets"
        }

        isLoading = false
    }

    // MARK: - Scripts

    static let scriptsScript = """
    (function() {
        const scripts = [];
        for (const script of document.scripts) {
            // Only inline scripts have textContent (external scripts are empty)
            const content = script.src ? null : (script.textContent || null);
            scripts.push({
                src: script.src || null,
                isExternal: !!script.src,
                isModule: script.type === 'module',
                isAsync: script.async,
                isDefer: script.defer,
                content: content
            });
        }
        return JSON.stringify(scripts);
    })();
    """

    func fetchScripts() async {
        guard let navigator else {
            errorMessage = "Navigator not available"
            return
        }

        isLoading = true
        errorMessage = nil

        if let result = await navigator.evaluateJavaScript(Self.scriptsScript) as? String,
           let data = result.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            scripts = jsonArray.enumerated().map { idx, item in
                ScriptInfo(
                    index: idx,
                    src: item["src"] as? String,
                    isExternal: item["isExternal"] as? Bool ?? false,
                    isModule: item["isModule"] as? Bool ?? false,
                    isAsync: item["isAsync"] as? Bool ?? false,
                    isDefer: item["isDefer"] as? Bool ?? false,
                    content: item["content"] as? String
                )
            }
        } else {
            errorMessage = "Failed to fetch scripts"
        }

        isLoading = false
    }

    func clear() {
        domTree = nil
        rawHTML = nil
        stylesheets = []
        scripts = []
        errorMessage = nil
    }
}
