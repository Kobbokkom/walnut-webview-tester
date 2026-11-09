//
//  SourceDetailViews.swift
//  wina
//
//  Element detail view for DOM inspection - Chrome DevTools style.
//

import SwiftUI

// MARK: - CSS Property

/// Represents a single CSS property with override and importance info
struct CSSProperty: Identifiable {
    let id: String  // "ruleId-propertyName" for uniqueness
    let property: String
    let value: String
    let isImportant: Bool  // Has !important flag
    var isOverridden: Bool  // Overridden by higher specificity rule

    init(property: String, value: String, isImportant: Bool = false, isOverridden: Bool = false, ruleId: Int = 0) {
        self.id = "\(ruleId)-\(property)"
        self.property = property
        self.value = value
        self.isImportant = isImportant
        self.isOverridden = isOverridden
    }
}

// MARK: - Matched CSS Rule

/// Represents a matched CSS rule with its source
struct MatchedCSSRule: Identifiable {
    let id: Int
    let selector: String
    let source: CSSSource
    let layer: String?  // CSS @layer name (e.g., "base", "utilities")
    var properties: [CSSProperty]  // Changed to CSSProperty with override info
    let specificity: Int  // For sorting
    let isCORSBlocked: Bool  // True if stylesheet couldn't be accessed due to CORS

    init(
        id: Int,
        selector: String,
        source: CSSSource,
        layer: String? = nil,
        properties: [CSSProperty],
        specificity: Int,
        isCORSBlocked: Bool = false
    ) {
        self.id = id
        self.selector = selector
        self.source = source
        self.layer = layer
        self.properties = properties
        self.specificity = specificity
        self.isCORSBlocked = isCORSBlocked
    }

    /// Display name combining source and layer
    var displaySource: String {
        if let layer {
            return "\(source.displayName) @layer \(layer)"
        }
        return source.displayName
    }

    enum CSSSource: Equatable {
        case inline              // element.style
        case styleTag(Int)       // <style> tag (index)
        case stylesheet(String)  // External file (href)
        case unknown

        var displayName: String {
            switch self {
            case .inline: return "element.style"
            case .styleTag(let idx): return "<style> #\(idx + 1)"
            case .stylesheet(let href):
                if let url = URL(string: href) {
                    // Show host + filename for external
                    if let host = url.host, host != url.lastPathComponent {
                        return "\(host)/\(url.lastPathComponent)"
                    }
                    return url.lastPathComponent
                }
                return href
            case .unknown: return "unknown"
            }
        }

        var sortOrder: Int {
            switch self {
            case .inline: return 0
            case .styleTag: return 1
            case .stylesheet: return 2
            case .unknown: return 3
            }
        }
    }
}

// MARK: - Element Detail View

struct ElementDetailView: View {
    let node: DOMNode
    let navigator: WebViewNavigator?

    @Environment(\.dismiss) private var dismiss
    @State private var computedStyles: [String: String] = [:]
    @State private var matchedRules: [MatchedCSSRule] = []
    @State private var innerHTML: String = ""
    @State private var outerHTML: String = ""
    @State private var isLoading: Bool = true
    @State private var selectedSection: ElementSection = .attributes
    @State private var showMatchedRules: Bool = true  // Toggle between matched/computed
    @State private var computedStylesFilter: String = ""
    @State private var showAllComputedStyles: Bool = false  // Show all vs non-default only
    @State private var groupComputedStyles: Bool = false  // Group by property category
    @State private var allComputedStyles: [String: String] = [:]  // All styles (for Show all)
    @State private var feedbackState = CopiedFeedbackState()
    @State private var corsBlockedCount: Int = 0

    enum ElementSection: String, CaseIterable {
        case attributes = "Attributes"
        case styles = "Styles"
        case html = "HTML"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            limitationDisclaimer
            sectionPicker
            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    content
                        .padding()
                }
                .background(Color(uiColor: .systemBackground))
            }
        }
        .copiedFeedbackOverlay($feedbackState.message)
        .dismissKeyboardOnTap()
        .task {
            await fetchDetails()
        }
    }

    private var header: some View {
        DevToolsHeader(
            title: node.displayName,
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {
                    dismiss()
                }
            ],
            rightButtons: [
                .init(icon: "doc.on.doc") {
                    copyToClipboard()
                }
            ]
        )
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(ElementSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedSection = section
                    }
                } label: {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selectedSection == section ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selectedSection == section {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .attributes:
            attributesContent
        case .styles:
            stylesContent
        case .html:
            htmlContent
        }
    }

    private var limitationDisclaimer: some View {
        Label("May be incomplete or inaccurate", systemImage: "info.circle")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
    }

    private var attributesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tag name
            SourceInfoRow(label: "Tag", value: node.nodeName.lowercased())

            // Attributes
            if node.attributes.isEmpty {
                Text("No attributes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(node.attributes.keys.sorted()), id: \.self) { key in
                    if let value = node.attributes[key] {
                        AttributeRow(name: key, value: value)
                    }
                }
            }
        }
    }

    private var stylesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Toggle between matched rules and computed styles
            stylesModeToggle

            if showMatchedRules {
                matchedRulesContent
            } else {
                computedStylesContent
            }
        }
    }

    private var stylesModeToggle: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    showMatchedRules = true
                }
            } label: {
                Text("Matched")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(showMatchedRules ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if showMatchedRules {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    showMatchedRules = false
                }
            } label: {
                Text(verbatim: "Computed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(!showMatchedRules ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if !showMatchedRules {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var matchedRulesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // CORS warning banner if applicable
            if corsBlockedCount > 0 {
                SecurityRestrictionBanner(type: .crossOriginStylesheet(count: corsBlockedCount))
            }

            // Rules content
            if accessibleMatchedRules.isEmpty {
                VStack(spacing: 8) {
                    Text("No matched rules found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if corsBlockedCount > 0 {
                        Text("Styles from CDN (Tailwind, Bootstrap, etc.) cannot be inspected due to browser security")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedMatchedRules, id: \.groupKey) { group in
                        MatchedRulesGroupView(
                            source: group.source,
                            layer: group.layer,
                            rules: group.rules
                        )
                    }
                }
            }
        }
    }

    /// Matched rules excluding CORS-blocked entries
    private var accessibleMatchedRules: [MatchedCSSRule] {
        matchedRules.filter { !$0.isCORSBlocked }
    }

    /// Group matched rules by layer for display (Chrome DevTools style)
    private var groupedMatchedRules: [(groupKey: String, source: MatchedCSSRule.CSSSource, layer: String?, rules: [MatchedCSSRule])] {
        let accessible = accessibleMatchedRules
        // Group by displaySource (source + layer combination)
        let grouped = Dictionary(grouping: accessible) { $0.displaySource }
        return grouped
            .compactMap { key, rules -> (groupKey: String, source: MatchedCSSRule.CSSSource, layer: String?, rules: [MatchedCSSRule])? in
                guard let firstRule = rules.first else { return nil }
                return (key, firstRule.source, firstRule.layer, rules)
            }
            .sorted { lhs, rhs in
                // Sort order: inline > styleTag > stylesheet, then by layer name
                if lhs.source.sortOrder != rhs.source.sortOrder {
                    return lhs.source.sortOrder < rhs.source.sortOrder
                }
                // Within same source, sort by layer (nil first, then alphabetically)
                let lhsLayer = lhs.layer ?? ""
                let rhsLayer = rhs.layer ?? ""
                return lhsLayer < rhsLayer
            }
    }

    /// Source styles based on Show all toggle
    private var activeComputedStyles: [String: String] {
        showAllComputedStyles ? allComputedStyles : computedStyles
    }

    private var filteredComputedStyles: [(key: String, value: String)] {
        let sorted = activeComputedStyles.sorted { $0.key < $1.key }
        if computedStylesFilter.isEmpty {
            return sorted.map { (key: $0.key, value: $0.value) }
        }
        let filter = computedStylesFilter.lowercased()
        return sorted
            .filter { $0.key.lowercased().contains(filter) || $0.value.lowercased().contains(filter) }
            .map { (key: $0.key, value: $0.value) }
    }

    /// Grouped computed styles by CSS property category
    private var groupedComputedStyles: [(category: String, properties: [(key: String, value: String)])] {
        let styles = filteredComputedStyles
        var groups: [String: [(key: String, value: String)]] = [:]

        for style in styles {
            let category = CSSPropertyCategory.category(for: style.key)
            groups[category, default: []].append(style)
        }

        return CSSPropertyCategory.allCategories
            .compactMap { category in
                guard let props = groups[category], !props.isEmpty else { return nil }
                return (category: category, properties: props)
            }
    }

    private var computedStylesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Filter and options row
            HStack(spacing: 12) {
                // Search filter
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Filter", text: $computedStylesFilter)
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                    if !computedStylesFilter.isEmpty {
                        Button {
                            computedStylesFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                // Show all checkbox
                Button {
                    showAllComputedStyles.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAllComputedStyles ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundStyle(showAllComputedStyles ? .blue : .secondary)
                        Text("Show all")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // Group checkbox
                Button {
                    groupComputedStyles.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: groupComputedStyles ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundStyle(groupComputedStyles ? .blue : .secondary)
                        Text("Group")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            // Count indicator
            HStack {
                Text("\(filteredComputedStyles.count) properties")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Properties list
            if activeComputedStyles.isEmpty {
                Text("No computed styles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if filteredComputedStyles.isEmpty {
                Text("No matching properties")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if groupComputedStyles {
                // Grouped view
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedComputedStyles, id: \.category) { group in
                        ComputedStylesGroupView(category: group.category, properties: group.properties)
                    }
                }
            } else {
                // Flat list view
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredComputedStyles, id: \.key) { item in
                        CSSPropertyRow(property: item.key, value: item.value)
                    }
                }
            }
        }
    }

    private var htmlContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // outerHTML (collapsed by default)
            CollapsibleHTMLBlock(
                title: "outerHTML",
                content: outerHTML,
                charCount: outerHTML.count
            ) {
                feedbackState.showCopied("outerHTML")
            }

            // innerHTML (collapsed by default)
            CollapsibleHTMLBlock(
                title: "innerHTML",
                content: innerHTML,
                charCount: innerHTML.count
            ) {
                feedbackState.showCopied("innerHTML")
            }
        }
    }

    // MARK: - Data Fetching

    private func fetchDetails() async {
        guard let navigator else {
            isLoading = false
            return
        }

        let path = node.path

        // Execute all JavaScript fetches concurrently
        async let stylesResult = navigator.evaluateJavaScript(ElementDetailScripts.computedStyles(path: path))
        async let allStylesResult = navigator.evaluateJavaScript(ElementDetailScripts.allComputedStyles(path: path))
        async let htmlResult = navigator.evaluateJavaScript(ElementDetailScripts.htmlContent(path: path))
        async let matchedResult = navigator.evaluateJavaScript(ElementDetailScripts.matchedRules(path: path))

        // Parse computed styles (non-default)
        if let stylesJSON = await stylesResult as? String,
           let data = stylesJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            computedStyles = parsed
        }

        // Parse ALL computed styles
        if let allStylesJSON = await allStylesResult as? String,
           let data = allStylesJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            allComputedStyles = parsed
        }

        // Parse HTML content
        if let htmlJSON = await htmlResult as? String,
           let data = htmlJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            outerHTML = parsed["outer"] ?? ""
            innerHTML = parsed["inner"] ?? ""
        }

        // Parse matched CSS rules
        if let matchedJSON = await matchedResult as? String,
           let data = matchedJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let rules = parseMatchedRules(from: parsed)
            matchedRules = rules
            corsBlockedCount = rules.filter { $0.isCORSBlocked }.count
        }

        isLoading = false
    }

    /// Parse matched rules from JavaScript result
    private func parseMatchedRules(from jsonArray: [[String: Any]]) -> [MatchedCSSRule] {
        return jsonArray.compactMap { item -> MatchedCSSRule? in
            guard let id = item["id"] as? Int,
                  let sourceDict = item["source"] as? [String: Any] else {
                return nil
            }

            let selector = item["selector"] as? String ?? ""
            let propsArray = item["properties"] as? [[String: Any]] ?? []
            let specificity = item["specificity"] as? Int ?? 0
            let corsBlocked = item["corsBlocked"] as? Bool ?? false
            let layer = item["layer"] as? String  // CSS @layer name

            // Parse source
            let source: MatchedCSSRule.CSSSource
            if let type = sourceDict["type"] as? String {
                switch type {
                case "inline":
                    source = .inline
                case "styleTag":
                    let index = sourceDict["index"] as? Int ?? 0
                    source = .styleTag(index)
                case "external":
                    let href = sourceDict["href"] as? String ?? ""
                    source = .stylesheet(href)
                default:
                    source = .unknown
                }
            } else {
                source = .unknown
            }

            // Parse properties with !important and override info
            let properties = propsArray.compactMap { propDict -> CSSProperty? in
                guard let prop = propDict["p"] as? String,
                      let val = propDict["v"] as? String else { return nil }
                let isImportant = propDict["i"] as? Bool ?? false
                let isOverridden = propDict["o"] as? Bool ?? false
                return CSSProperty(
                    property: prop,
                    value: val,
                    isImportant: isImportant,
                    isOverridden: isOverridden,
                    ruleId: id
                )
            }

            return MatchedCSSRule(
                id: id,
                selector: selector,
                source: source,
                layer: layer,
                properties: properties,
                specificity: specificity,
                isCORSBlocked: corsBlocked
            )
        }
    }

    private func copyToClipboard() {
        switch selectedSection {
        case .attributes:
            let text = node.attributes.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: "\n")
            UIPasteboard.general.string = text
            feedbackState.showCopied("Attributes")
        case .styles:
            let text = computedStyles.map { "\($0.key): \($0.value);" }.joined(separator: "\n")
            UIPasteboard.general.string = text
            feedbackState.showCopied("Styles")
        case .html:
            UIPasteboard.general.string = outerHTML
            feedbackState.showCopied("HTML")
        }
    }
}

// MARK: - Element Detail Scripts

/// JavaScript scripts for element detail fetching
enum ElementDetailScripts {
    /// Script to fetch computed styles that differ from defaults (Chrome DevTools style)
    /// Uses isolated iframe to get true initial values without inheritance
    static func computedStyles(path: [Int]) -> String {
        """
        (function() {
            const el = \(SourcesManager.nodeLookupScript(path: path));
            if (!el) return '{}';

            const tagName = el.tagName.toLowerCase();
            const styles = window.getComputedStyle(el);
            const result = {};

            // Create isolated iframe to get true CSS initial values (no inheritance)
            const iframe = document.createElement('iframe');
            iframe.style.cssText = 'position:absolute;width:0;height:0;border:0;visibility:hidden;';
            document.body.appendChild(iframe);

            try {
                const iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
                iframeDoc.open();
                iframeDoc.write('<!DOCTYPE html><html><head></head><body></body></html>');
                iframeDoc.close();

                // Create reference element in isolated environment (no inherited styles)
                const ref = iframeDoc.createElement(tagName);
                iframeDoc.body.appendChild(ref);
                const refStyles = iframe.contentWindow.getComputedStyle(ref);

                // Compare: element's computed vs isolated initial values
                for (let i = 0; i < styles.length; i++) {
                    const prop = styles[i];
                    // Skip CSS custom properties (shown only in "Show all" mode)
                    if (prop.startsWith('--')) continue;

                    const val = styles.getPropertyValue(prop);
                    const refVal = refStyles.getPropertyValue(prop);

                    // Keep if different from initial value
                    if (val !== refVal && val && val.trim()) {
                        result[prop] = val;
                    }
                }
            } finally {
                // Cleanup
                document.body.removeChild(iframe);
            }

            return JSON.stringify(result);
        })();
        """
    }

    /// Script to fetch ALL computed styles (for "Show all" mode)
    static func allComputedStyles(path: [Int]) -> String {
        """
        (function() {
            const el = \(SourcesManager.nodeLookupScript(path: path));
            if (!el) return '{}';
            const styles = window.getComputedStyle(el);
            const result = {};
            for (let i = 0; i < styles.length; i++) {
                const prop = styles[i];
                const val = styles.getPropertyValue(prop);
                if (val && val.trim()) { result[prop] = val; }
            }
            return JSON.stringify(result);
        })();
        """
    }

    /// Script to fetch HTML content
    static func htmlContent(path: [Int], maxLength: Int? = 5000) -> String {
        let truncation = maxLength.map { ".substring(0, \($0))" } ?? ""
        return """
        (function() {
            const el = \(SourcesManager.nodeLookupScript(path: path));
            if (!el) return '{}';
            return JSON.stringify({
                outer: el.outerHTML\(truncation),
                inner: el.innerHTML\(truncation)
            });
        })();
        """
    }

    /// Script to fetch matched CSS rules (with @layer support)
    static func matchedRules(path: [Int]) -> String {
        "(function() { \(matchedRulesSetup(path: path)) \(matchedRulesProcessing) })();"
    }

    /// Setup part of matchedRules script
    private static func matchedRulesSetup(path: [Int]) -> String {
        """
        const el = \(SourcesManager.nodeLookupScript(path: path));
        if (!el) return '[]';
        const rules = []; let ruleId = 0;
        function calcSpecificity(sel) {
            if (!sel) return 0;
            const ids = (sel.match(/#/g) || []).length;
            const classes = (sel.match(/\\./g) || []).length + (sel.match(/\\[/g) || []).length;
            const tags = (sel.match(/^[a-z]/gi) || []).length;
            return ids * 100 + classes * 10 + tags;
        }
        function parseProps(style) {
            const props = [];
            for (let i = 0; i < style.length; i++) {
                const prop = style[i];
                const val = style.getPropertyValue(prop);
                const priority = style.getPropertyPriority(prop);
                if (val) props.push({p: prop, v: val, i: priority === 'important'});
            }
            return props;
        }
        if (el.style.length > 0) {
            const inlineProps = parseProps(el.style);
            if (inlineProps.length > 0) {
                rules.push({ id: ruleId++, selector: 'element.style', source: {type: 'inline'}, properties: inlineProps, specificity: 1000 });
            }
        }
        """
    }

    /// Processing part of matchedRules script (handles @layer, @media, @container, etc.)
    private static var matchedRulesProcessing: String {
        """
        function processRules(cssRules, sourceInfo, layerName = null) {
            for (const rule of cssRules) {
                const ruleType = rule.constructor.name;
                if (ruleType === 'CSSLayerBlockRule' && rule.cssRules) { processRules(rule.cssRules, sourceInfo, rule.name); }
                else if (ruleType === 'CSSMediaRule' && rule.cssRules) { if (window.matchMedia(rule.conditionText).matches) { processRules(rule.cssRules, sourceInfo, layerName); } }
                else if (ruleType === 'CSSSupportsRule' && rule.cssRules) { if (CSS.supports(rule.conditionText)) { processRules(rule.cssRules, sourceInfo, layerName); } }
                else if (ruleType === 'CSSContainerRule' && rule.cssRules) { processRules(rule.cssRules, sourceInfo, layerName); }
                else if (ruleType === 'CSSScopeRule' && rule.cssRules) { processRules(rule.cssRules, sourceInfo, layerName); }
                else if (ruleType === 'CSSStartingStyleRule' && rule.cssRules) { processRules(rule.cssRules, sourceInfo, layerName); }
                else if (rule.type === 1) {
                    try { if (el.matches(rule.selectorText)) { const props = parseProps(rule.style); if (props.length > 0) { rules.push({ id: ruleId++, selector: rule.selectorText, source: sourceInfo, layer: layerName, properties: props, specificity: calcSpecificity(rule.selectorText) }); } } } catch(e) {}
                }
            }
        }
        let styleTagIndex = 0;
        for (let i = 0; i < document.styleSheets.length; i++) {
            const sheet = document.styleSheets[i]; let sourceInfo;
            if (sheet.href) { sourceInfo = {type: 'external', href: sheet.href}; } else { sourceInfo = {type: 'styleTag', index: styleTagIndex++}; }
            try { const cssRules = sheet.cssRules || sheet.rules; if (!cssRules) continue; processRules(cssRules, sourceInfo); }
            catch(e) { if (sheet.href) { rules.push({ id: ruleId++, selector: '', source: sourceInfo, properties: [], specificity: 0, corsBlocked: true }); } }
        }
        // Calculate overrides: for each property, find winner by specificity + !important
        const propWinners = {};
        for (let ri = rules.length - 1; ri >= 0; ri--) {
            const r = rules[ri];
            for (const prop of r.properties) {
                const key = prop.p;
                const score = (prop.i ? 10000 : 0) + r.specificity;
                if (!propWinners[key] || score >= propWinners[key].score) {
                    propWinners[key] = { ruleId: r.id, propIdx: r.properties.indexOf(prop), score };
                }
            }
        }
        // Mark overridden properties
        for (const r of rules) {
            for (const prop of r.properties) {
                const winner = propWinners[prop.p];
                prop.o = !(winner && winner.ruleId === r.id && winner.propIdx === r.properties.indexOf(prop));
            }
        }
        return JSON.stringify(rules.slice(0, 100));
        """
    }
}

// MARK: - Previews

#Preview("Element Detail") {
    ElementDetailView(
        node: DOMNode(
            path: [0],
            nodeType: 1,
            nodeName: "DIV",
            attributes: ["id": "main", "class": "container flex"],
            textContent: nil,
            children: []
        ),
        navigator: nil
    )
}
