//
//  WebViewScripts+Emulation.swift
//  wina
//
//  Emulation scripts for WebView.
//

import Foundation

extension WebViewScripts {
    /// Performance observer script - sets up tracking for LCP and CLS
    /// Note: INP removed - Safari/WKWebView doesn't support Event Timing API (until 2026)
    static let performanceObserver = """
        (function() {
            if (window.__webVitals_initialized) return;
            window.__webVitals_initialized = true;

            // LCP tracking (Largest Contentful Paint)
            window.__webVitals_lcp = -1;
            try {
                new PerformanceObserver((list) => {
                    const entries = list.getEntries();
                    if (entries.length > 0) {
                        window.__webVitals_lcp = entries[entries.length - 1].startTime;
                    }
                }).observe({ type: 'largest-contentful-paint', buffered: true });
            } catch (e) {}

            // CLS tracking (Cumulative Layout Shift)
            window.__webVitals_cls = 0;
            try {
                new PerformanceObserver((list) => {
                    for (const entry of list.getEntries()) {
                        if (!entry.hadRecentInput) {
                            window.__webVitals_cls += entry.value;
                        }
                    }
                }).observe({ type: 'layout-shift', buffered: true });
            } catch (e) {}
        })();
        """

    /// Emulation bootstrap script - reads config from window object and applies overrides
    /// Injected at document start, reads window.__winaEmulationConfig set by native code
    static let emulationBootstrap = """
        (function() {
            if (window.__winaEmulationApplied) return;

            // Config is set by native code before page load
            const config = window.__winaEmulationConfig || {};
            if (!config.colorScheme && !config.reducedMotion && !config.highContrast && !config.reducedTransparency) {
                return; // No emulation needed
            }

            window.__winaEmulationApplied = true;

            // Build matchMedia overrides
            const overrides = {};
            if (config.colorScheme && config.colorScheme !== 'system') {
                const scheme = config.colorScheme;
                const opposite = scheme === 'dark' ? 'light' : 'dark';
                overrides['(prefers-color-scheme: ' + scheme + ')'] = true;
                overrides['(prefers-color-scheme: ' + opposite + ')'] = false;
            }
            if (config.reducedMotion) {
                overrides['(prefers-reduced-motion)'] = true;
                overrides['(prefers-reduced-motion: reduce)'] = true;
                overrides['(prefers-reduced-motion: no-preference)'] = false;
            }
            if (config.highContrast) {
                overrides['(prefers-contrast)'] = true;
                overrides['(prefers-contrast: more)'] = true;
                overrides['(prefers-contrast: no-preference)'] = false;
                overrides['(prefers-contrast: less)'] = false;
                overrides['(prefers-contrast: custom)'] = false;
            }
            if (config.reducedTransparency) {
                overrides['(prefers-reduced-transparency)'] = true;
                overrides['(prefers-reduced-transparency: reduce)'] = true;
                overrides['(prefers-reduced-transparency: no-preference)'] = false;
            }

            // Keep native media query parsing, boolean logic, listeners and event delivery.
            const originalMatchMedia = window.matchMedia.bind(window);
            window.matchMedia = function(query) {
                const text = String(query);
                const substituted = text.replace(/\\(\\s*(prefers-[a-z-]+)\\s*(?::\\s*([a-z-]+)\\s*)?\\)/gi,
                    function(clause, feature, value) {
                        const pattern = '(' + feature.toLowerCase() + (value ? ': ' + value.toLowerCase() : '') + ')';
                        if (!Object.prototype.hasOwnProperty.call(overrides, pattern)) return clause;
                        return overrides[pattern] ? '(width >= 0px)' : '(width < 0px)';
                    });
                const result = originalMatchMedia(substituted);
                if (substituted !== text) {
                    Object.defineProperty(result, 'media', {value: text});
                }
                return result;
            };

            // Build and inject CSS overrides
            let css = '';
            if (config.colorScheme && config.colorScheme !== 'system') {
                css += ':root { color-scheme: ' + config.colorScheme + '; }\\n';
            }
            if (config.reducedMotion) {
                css += '*, *::before, *::after { animation-duration: 0.001ms !important; animation-iteration-count: 1 !important; transition-duration: 0.001ms !important; scroll-behavior: auto !important; }\\n';
            }
            if (config.highContrast) {
                css += ':root { forced-color-adjust: auto; }\\n';
            }
            if (config.reducedTransparency) {
                css += '* { backdrop-filter: none !important; -webkit-backdrop-filter: none !important; }\\n';
            }

            if (css) {
                const style = document.createElement('style');
                style.id = 'wina-emulation-style';
                style.textContent = css;
                const appendStyle = function() { (document.head || document.documentElement).appendChild(style); };
                if (document.documentElement) appendStyle();
                else document.addEventListener('DOMContentLoaded', appendStyle, {once: true});
            }
        })();
        """

    static let emulationConfigMarker = "// Walnut emulation configuration"

    /// Script to set emulation config (call before page load or reload)
    static func emulationConfigScript(
        colorScheme: String,
        reducedMotion: Bool,
        highContrast: Bool,
        reducedTransparency: Bool
    ) -> String {
        """
        \(emulationConfigMarker)
        window.__winaEmulationConfig = {
            colorScheme: '\(colorScheme)',
            reducedMotion: \(reducedMotion),
            highContrast: \(highContrast),
            reducedTransparency: \(reducedTransparency)
        };
        window.__winaEmulationApplied = false;
        """
    }
}
