//
//  MediaCodecsView.swift
//  wina
//

import SwiftUI

// MARK: - Media Codecs View

struct MediaCodecsView: View {
    @State private var codecInfo: MediaCodecInfo?
    @State private var loadingStatus = "Launching WebView process..."

    var body: some View {
        List {
            if let info = codecInfo {
                Section {
                    Text("Codec support may vary depending on device and OS version.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listSectionSpacing(0)

                Section("Video Codecs") {
                    CodecRow(label: "H.264 (AVC)", support: info.h264)
                    CodecRow(label: "H.265 (HEVC)", support: info.hevc)
                    CodecRow(label: "VP8", support: info.vp8)
                    CodecRow(label: "VP9", support: info.vp9)
                    CodecRow(label: "AV1", support: info.av1)
                    CodecRow(label: "Theora", support: info.theora)
                }

                Section("Audio Codecs") {
                    CodecRow(label: "AAC", support: info.aac)
                    CodecRow(label: "MP3", support: info.mp3)
                    CodecRow(label: "Opus", support: info.opus)
                    CodecRow(label: "Vorbis", support: info.vorbis)
                    CodecRow(label: "FLAC", support: info.flac)
                    CodecRow(label: "WAV (PCM)", support: info.wav)
                }

                Section("Containers") {
                    CodecRow(label: "MP4", support: info.mp4)
                    CodecRow(label: "WebM", support: info.webm)
                    CodecRow(label: "Ogg", support: info.ogg)
                    CodecRow(label: "HLS (m3u8)", support: info.hls)
                }

                Section("Media Capabilities API") {
                    CapabilityRow(label: "MediaCapabilities", supported: info.supportsMediaCapabilities)
                    CapabilityRow(
                        label: "MediaSource Extensions",
                        supported: false,
                        info: "API for adaptive streaming (e.g., DASH). Not supported in WKWebView.",
                        unavailable: true
                    )
                    CapabilityRow(label: "Encrypted Media", supported: info.supportsEME)
                }
            }
        }
        .overlay {
            if codecInfo == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loadingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: "Media Codecs"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            codecInfo = await MediaCodecInfo.load { status in
                loadingStatus = status
            }
        }
    }
}

// MARK: - Media Codec Info Model

struct MediaCodecInfo: Sendable, Encodable {
    // Video
    let h264: CodecSupport
    let hevc: CodecSupport
    let vp8: CodecSupport
    let vp9: CodecSupport
    let av1: CodecSupport
    let theora: CodecSupport

    // Audio
    let aac: CodecSupport
    let mp3: CodecSupport
    let opus: CodecSupport
    let vorbis: CodecSupport
    let flac: CodecSupport
    let wav: CodecSupport

    // Containers
    let mp4: CodecSupport
    let webm: CodecSupport
    let ogg: CodecSupport
    let hls: CodecSupport

    // APIs
    let supportsMediaCapabilities: Bool
    let supportsMSE: Bool
    let supportsEME: Bool

    static let empty = MediaCodecInfo(
        h264: .none, hevc: .none, vp8: .none, vp9: .none, av1: .none, theora: .none,
        aac: .none, mp3: .none, opus: .none, vorbis: .none, flac: .none, wav: .none,
        mp4: .none, webm: .none, ogg: .none, hls: .none,
        supportsMediaCapabilities: false, supportsMSE: false, supportsEME: false
    )

    @MainActor
    static func load(
        using shared: SharedInfoWebView = .shared,
        onStatusUpdate: @escaping (String) -> Void
    ) async -> MediaCodecInfo {
        // Return cached if available
        if let cached = shared.cachedCodecInfo {
            onStatusUpdate("Using cached data...")
            return cached
        }

        // Initialize shared WebView (or use live WebView if available)
        let generation = shared.cacheGeneration
        await shared.initialize(onStatusUpdate: onStatusUpdate)

        onStatusUpdate("Detecting media codecs...")
        let script = """
        (function() {
            var video = document.createElement('video');
            var audio = document.createElement('audio');

            function check(el, type) {
                var result = el.canPlayType(type);
                return result || 'no';
            }

            return {
                // Video codecs
                h264: check(video, 'video/mp4; codecs="avc1.42E01E"'),
                hevc: check(video, 'video/mp4; codecs="hvc1.1.6.L93.B0"'),
                vp8: check(video, 'video/webm; codecs="vp8"'),
                vp9: check(video, 'video/webm; codecs="vp9"'),
                av1: check(video, 'video/mp4; codecs="av01.0.01M.08"'),
                theora: check(video, 'video/ogg; codecs="theora"'),

                // Audio codecs
                aac: check(audio, 'audio/mp4; codecs="mp4a.40.2"'),
                mp3: check(audio, 'audio/mpeg; codecs="mp3"'),
                opus: check(audio, 'audio/ogg; codecs="opus"'),
                vorbis: check(audio, 'audio/ogg; codecs="vorbis"'),
                flac: check(audio, 'audio/flac'),
                wav: check(audio, 'audio/wav'),

                // Containers (with common codec for accurate detection)
                mp4: check(video, 'video/mp4; codecs="avc1.42E01E"'),
                webm: check(video, 'video/webm; codecs="vp8"'),
                ogg: check(video, 'video/ogg; codecs="theora"'),
                hls: check(video, 'application/vnd.apple.mpegurl; codecs="avc1.42E01E"'),

                // APIs
                mediaCapabilities: 'mediaCapabilities' in navigator,
                mse: 'ManagedMediaSource' in window || 'MediaSource' in window,
                eme: 'requestMediaKeySystemAccess' in navigator
            };
        })()
        """

        let result = await shared.evaluateJavaScript(script) as? [String: Any] ?? [:]

        func parseSupport(_ value: Any?) -> CodecSupport {
            guard let str = value as? String else { return .none }
            switch str {
            case "probably": return .probably
            case "maybe": return .maybe
            default: return .none
            }
        }

        let codecResult = MediaCodecInfo(
            h264: parseSupport(result["h264"]),
            hevc: parseSupport(result["hevc"]),
            vp8: parseSupport(result["vp8"]),
            vp9: parseSupport(result["vp9"]),
            av1: parseSupport(result["av1"]),
            theora: parseSupport(result["theora"]),
            aac: parseSupport(result["aac"]),
            mp3: parseSupport(result["mp3"]),
            opus: parseSupport(result["opus"]),
            vorbis: parseSupport(result["vorbis"]),
            flac: parseSupport(result["flac"]),
            wav: parseSupport(result["wav"]),
            mp4: parseSupport(result["mp4"]),
            webm: parseSupport(result["webm"]),
            ogg: parseSupport(result["ogg"]),
            hls: parseSupport(result["hls"]),
            supportsMediaCapabilities: result["mediaCapabilities"] as? Bool ?? false,
            supportsMSE: result["mse"] as? Bool ?? false,
            supportsEME: result["eme"] as? Bool ?? false
        )

        // Cache result
        if shared.cacheGeneration == generation {
            shared.cachedCodecInfo = codecResult
        }
        return codecResult
    }
}
