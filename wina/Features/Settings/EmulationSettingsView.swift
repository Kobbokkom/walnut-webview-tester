//
//  EmulationSettingsView.swift
//  wina
//
//  User preference emulation for testing media query responses.
//  Configuration setting - requires page reload for full effect.
//

import SwiftUI

// MARK: - Emulation Settings View

struct EmulationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let navigator: WebViewNavigator

    // Stored settings (persisted)
    @AppStorage("emulationColorScheme") private var storedColorScheme: String = "system"
    @AppStorage("emulationReducedMotion") private var storedReducedMotion: Bool = false
    @AppStorage("emulationHighContrast") private var storedHighContrast: Bool = false
    @AppStorage("emulationReducedTransparency") private var storedReducedTransparency: Bool = false

    // Local state (editing)
    @State private var colorScheme: EmulatedColorScheme = .system
    @State private var reducedMotion: Bool = false
    @State private var highContrast: Bool = false
    @State private var reducedTransparency: Bool = false

    private var hasChanges: Bool {
        colorScheme.rawValue != storedColorScheme ||
        reducedMotion != storedReducedMotion ||
        highContrast != storedHighContrast ||
        reducedTransparency != storedReducedTransparency
    }

    private var isEmulationActive: Bool {
        storedColorScheme != "system" ||
        storedReducedMotion ||
        storedHighContrast ||
        storedReducedTransparency
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Overrides JavaScript matchMedia with limited visual effects. CSS @media rules keep system preferences. Applying reloads the page.")
                        .font(.subheadline)
                }
            }

            Section {
                HStack {
                    Picker("Color Scheme", selection: $colorScheme) {
                        ForEach(EmulatedColorScheme.allCases) { scheme in
                            Text(scheme.label).tag(scheme)
                        }
                    }
                    InfoPopoverButton(text: "prefers-color-scheme\n\nOverrides JavaScript color scheme detection and the CSS color-scheme property. CSS @media rules keep system preferences.")
                }

                HStack {
                    Toggle("Reduced Motion", isOn: $reducedMotion)
                    InfoPopoverButton(text: "prefers-reduced-motion\n\nDisables animations and transitions.")
                }

                HStack {
                    Toggle("High Contrast", isOn: $highContrast)
                    InfoPopoverButton(text: "prefers-contrast\n\nOverrides JavaScript contrast detection. Does not recolor the page or override CSS @media rules.")
                }

                HStack {
                    Toggle("Reduced Transparency", isOn: $reducedTransparency)
                    InfoPopoverButton(text: "prefers-reduced-transparency\n\nDisables blur and transparency effects.")
                }
            }

            Section {
                HStack {
                    Spacer()
                    GlassActionButton("Reset", icon: "arrow.counterclockwise", style: .destructive) {
                        resetToDefaults()
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(Text(verbatim: "Emulation"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Apply") { applyChanges() }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if hasChanges {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Changes will reload page")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            } else if isEmulationActive {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.purple)
                    Text(verbatim: "Emulation Active")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasChanges)
        .onAppear {
            loadFromStorage()
        }
    }

    private func loadFromStorage() {
        colorScheme = EmulatedColorScheme(rawValue: storedColorScheme) ?? .system
        reducedMotion = storedReducedMotion
        highContrast = storedHighContrast
        reducedTransparency = storedReducedTransparency
    }

    private func applyChanges() {
        // Save to storage
        storedColorScheme = colorScheme.rawValue
        storedReducedMotion = reducedMotion
        storedHighContrast = highContrast
        storedReducedTransparency = reducedTransparency

        // Set config and reload (preserves history)
        let configScript = WebViewScripts.emulationConfigScript(
            colorScheme: colorScheme.rawValue,
            reducedMotion: reducedMotion,
            highContrast: highContrast,
            reducedTransparency: reducedTransparency
        )
        navigator.applyEmulation(configScript: configScript)
        dismiss()
    }

    private func resetToDefaults() {
        // Reset local state
        colorScheme = .system
        reducedMotion = false
        highContrast = false
        reducedTransparency = false
    }
}

// MARK: - Emulation Types

enum EmulatedColorScheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: return "System Default"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var cssValue: String {
        switch self {
        case .system: return "system"
        case .light: return "light"
        case .dark: return "dark"
        }
    }
}

#Preview {
    NavigationStack {
        EmulationSettingsView(navigator: WebViewNavigator())
    }
}
