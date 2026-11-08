//
//  BenchmarkView.swift
//  wina
//

import SwiftUI
import WebKit

// MARK: - Benchmark View

struct BenchmarkView: View {
    @State private var perfInfo: PerformanceInfo?
    @State private var loadingStatus = "Launching WebView process..."
    @State private var isRunning = false

    var body: some View {
        List {
            if let info = perfInfo {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("\(info.totalScore)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            Text("iPhone 14 Pro ≈ 10,000")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("System") {
                    InfoRow(
                        label: "JS Reported Cores", value: info.hardwareConcurrency,
                        info:
                            "navigator.hardwareConcurrency.\nJS thread pool sizing.\nMay differ from actual CPU cores\nfor privacy protection."
                    )
                    InfoRow(
                        label: "Timer Resolution", value: info.timerResolution,
                        info: "performance.now() precision.\nReduced for Spectre mitigation.\nTypically 1ms in WKWebView.")
                }

                Section("JavaScript") {
                    BenchmarkRow(
                        label: "Math", ops: info.mathOps,
                        info: "Math.sqrt, sin, cos, random.\nTests JIT optimization.\nCore computation speed.")
                    BenchmarkRow(
                        label: "Array", ops: info.arrayOps,
                        info: "map, filter, reduce, sort.\nFunctional programming ops.\nMemory allocation intensive.")
                    BenchmarkRow(
                        label: "String", ops: info.stringOps,
                        info: "split, join, indexOf, replace.\nText processing speed.\nCommon in web apps.")
                    BenchmarkRow(
                        label: "Object", ops: info.objectOps,
                        info: "Object.keys/values, spread.\nJSON parse/stringify.\nData manipulation speed.")
                    BenchmarkRow(
                        label: "RegExp", ops: info.regexpOps,
                        info: "match, replace, test.\nPattern matching speed.\nValidation performance.")
                }

                Section("DOM") {
                    BenchmarkRow(
                        label: "Create", ops: info.domCreate,
                        info: "createElement, appendChild.\nNode creation overhead.\nVirtual DOM comparison.")
                    BenchmarkRow(
                        label: "Query", ops: info.domQuery,
                        info: "querySelector(All), getElement*.\nDOM traversal speed.\nSelector engine perf.")
                    BenchmarkRow(
                        label: "Modify", ops: info.domModify,
                        info: "style, className, attribute.\nReflow/repaint triggers.\nAnimation performance.")
                }

                Section("Graphics") {
                    BenchmarkRow(
                        label: "Canvas 2D", ops: info.canvas2d,
                        info: "2D drawing operations.\nfillRect, arc, stroke.\nSoftware rendering.")
                    BenchmarkRow(
                        label: "WebGL", ops: info.webgl,
                        info: "GPU-accelerated graphics.\nclear, bindBuffer.\nHardware rendering.")
                }

                Section("Memory") {
                    BenchmarkRow(
                        label: "Allocation", ops: info.memoryAlloc,
                        info: "ArrayBuffer, TypedArray.\nMemory allocation speed.\nGC pressure indicator.")
                    BenchmarkRow(
                        label: "Operations", ops: info.memoryOps,
                        info: "Fill, copy, sort arrays.\nMemory bandwidth test.\nCPU cache efficiency.")
                }

                Section("Crypto") {
                    BenchmarkRow(
                        label: "Hash", ops: info.cryptoHash,
                        info: "Hashing algorithm test.\nCPU-intensive operations.\nSecurity computation speed.")
                }

                Section {
                    Button {
                        Task {
                            isRunning = true
                            perfInfo = await PerformanceInfo.load { status in
                                loadingStatus = status
                            }
                            isRunning = false
                        }
                    } label: {
                        HStack {
                            Text("Run Again")
                            Spacer()
                            if isRunning {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isRunning)
                }
            }
        }
        .overlay {
            if perfInfo == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loadingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: "Performance"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            perfInfo = await PerformanceInfo.load { status in
                loadingStatus = status
            }
        }
    }
}

// MARK: - Performance Info Model

struct PerformanceInfo: Sendable, Encodable {
    // System
    let hardwareConcurrency: String
    let timerResolution: String

    // JS Benchmark
    let mathOps: String
    let arrayOps: String
    let stringOps: String
    let objectOps: String
    let regexpOps: String

    // DOM Benchmark
    let domCreate: String
    let domQuery: String
    let domModify: String

    // Graphics Benchmark
    let canvas2d: String
    let webgl: String

    // Memory Benchmark
    let memoryAlloc: String
    let memoryOps: String

    // Crypto Benchmark
    let cryptoHash: String

    // Total
    let totalScore: Int

    // iPhone 14 Pro reference values (ops/sec) - calibrated to score 10,000
    private static let reference: [String: Double] = [
        "math": 21_100_000,
        "array": 19_900_000,
        "string": 11_600_000,
        "object": 4_900_000,
        "regexp": 18_300_000,
        "domCreate": 4_600_000,
        "domQuery": 8_300_000,
        "domModify": 2_900_000,
        "canvas2d": 828_000,
        "webgl": 5_800_000,
        "memoryAlloc": 3_500_000,
        "memoryOps": 3_000_000,
        "cryptoHash": 10_700_000
    ]

    // MARK: - Load Function

    @MainActor
    static func load(onStatusUpdate: @escaping (String) -> Void) async -> PerformanceInfo {
        onStatusUpdate("Launching WebView process...")

        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)

        onStatusUpdate("Initializing WebView...")
        await webView.loadHTMLStringAsync("<html><body><div id='test'></div></body></html>", baseURL: nil)

        onStatusUpdate("Running benchmarks...")
        let rawResult = await webView.evaluateJavaScriptAsync(benchmarkScript)
        let result = rawResult as? [String: Any] ?? [:]

        return parseResult(from: result)
    }

    // MARK: - Result Parsing

    private static func parseResult(from result: [String: Any]) -> PerformanceInfo {
        let benchmarks = extractBenchmarks(from: result)
        let totalScore = calculateScore(benchmarks: benchmarks)
        let cores = toInt(result["hardwareConcurrency"])
        let resolution = result["timerResolution"] as? Double ?? 0

        return PerformanceInfo(
            hardwareConcurrency: cores > 0 ? "\(cores)" : "N/A",
            timerResolution: resolution >= 0 ? String(format: "%.2f ms", resolution) : "Restricted",
            mathOps: formatOps(benchmarks["math"] ?? 0),
            arrayOps: formatOps(benchmarks["array"] ?? 0),
            stringOps: formatOps(benchmarks["string"] ?? 0),
            objectOps: formatOps(benchmarks["object"] ?? 0),
            regexpOps: formatOps(benchmarks["regexp"] ?? 0),
            domCreate: formatOps(benchmarks["domCreate"] ?? 0),
            domQuery: formatOps(benchmarks["domQuery"] ?? 0),
            domModify: formatOps(benchmarks["domModify"] ?? 0),
            canvas2d: formatOps(benchmarks["canvas2d"] ?? 0),
            webgl: formatOps(benchmarks["webgl"] ?? 0),
            memoryAlloc: formatOps(benchmarks["memoryAlloc"] ?? 0),
            memoryOps: formatOps(benchmarks["memoryOps"] ?? 0),
            cryptoHash: formatOps(benchmarks["cryptoHash"] ?? 0),
            totalScore: totalScore
        )
    }

    private static func extractBenchmarks(from result: [String: Any]) -> [String: Int] {
        [
            "math": toInt(result["mathOps"]),
            "array": toInt(result["arrayOps"]),
            "string": toInt(result["stringOps"]),
            "object": toInt(result["objectOps"]),
            "regexp": toInt(result["regexpOps"]),
            "domCreate": toInt(result["domCreate"]),
            "domQuery": toInt(result["domQuery"]),
            "domModify": toInt(result["domModify"]),
            "canvas2d": toInt(result["canvas2d"]),
            "webgl": toInt(result["webgl"]),
            "memoryAlloc": toInt(result["memoryAlloc"]),
            "memoryOps": toInt(result["memoryOps"]),
            "cryptoHash": toInt(result["cryptoHash"])
        ]
    }

    private static func calculateScore(benchmarks: [String: Int]) -> Int {
        var totalRatio = 0.0
        for (key, ops) in benchmarks {
            if let ref = reference[key], ref > 0 {
                totalRatio += Double(ops) / ref
            }
        }
        let averageRatio = totalRatio / Double(benchmarks.count)
        return Int(averageRatio * 10000)  // iPhone 14 Pro = 10,000
    }

    private static func formatOps(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM ops/s", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK ops/s", Double(value) / 1_000)
        } else {
            return "\(value) ops/s"
        }
    }

    private static func toInt(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return 0
    }

    // MARK: - Benchmark Script
    // swiftlint:disable line_length
    private static let benchmarkScript = """
    (function() {
        try {
            function bench(fn, duration) { var ops = 0; var start = performance.now(); var end = start + duration; while (performance.now() < end) { fn(); ops++; } return Math.round(ops / ((performance.now() - start) / 1000)); }
            var times = [], iterations = 0, last = performance.now();
            while (times.length < 20 && iterations < 10000) { var now = performance.now(); if (now > last) { times.push(now - last); last = now; } iterations++; }
            var resolution = times.length > 0 ? Math.min.apply(null, times) : -1;
            var mathOps = bench(function() { Math.sqrt(Math.random() * 10000); Math.sin(Math.random()); Math.cos(Math.random()); }, 100);
            var arrayOps = bench(function() { var a = [1,2,3,4,5]; a.map(function(x) { return x * 2; }); a.filter(function(x) { return x > 2; }); a.reduce(function(a,b) { return a + b; }, 0); }, 100);
            var stringOps = bench(function() { var s = 'hello world'; s.split(' ').join('-'); s.toUpperCase(); s.indexOf('world'); }, 100);
            var objectOps = bench(function() { var o = {a: 1, b: 2, c: 3}; Object.keys(o); Object.values(o); JSON.parse(JSON.stringify(o)); }, 100);
            var regexpOps = bench(function() { var re = /[0-9]+/g; 'test123abc456'.match(re); 'hello'.replace(/l/g, 'x'); }, 100);
            var container = document.createElement('div'); document.body.appendChild(container);
            var domCreate = bench(function() { var el = document.createElement('div'); el.className = 'test-class'; el.textContent = 'test'; }, 100);
            for (var i = 0; i < 100; i++) { var div = document.createElement('div'); div.className = 'item item-' + i; div.id = 'item-' + i; container.appendChild(div); }
            var domQuery = bench(function() { document.querySelectorAll('.item'); document.getElementById('item-50'); document.getElementsByClassName('item'); }, 100);
            var targetEl = document.getElementById('item-25'); var domModify = 0;
            if (targetEl) { domModify = bench(function() { targetEl.style.color = 'red'; targetEl.setAttribute('data-test', 'value'); targetEl.classList.toggle('active'); }, 100); }
            var canvas2d = 0; try { var c = document.createElement('canvas'); c.width = 256; c.height = 256; var ctx = c.getContext('2d'); if (ctx) { canvas2d = bench(function() { ctx.fillStyle = 'rgb(' + Math.floor(Math.random()*255) + ',0,0)'; ctx.fillRect(Math.random()*200, Math.random()*200, 50, 50); ctx.beginPath(); ctx.arc(128, 128, 50, 0, Math.PI * 2); ctx.stroke(); }, 100); } } catch(e) {}
            var webgl = 0; try { var gc = document.createElement('canvas'); gc.width = 256; gc.height = 256; var gl = gc.getContext('webgl') || gc.getContext('experimental-webgl'); if (gl) { webgl = bench(function() { gl.clearColor(Math.random(), Math.random(), Math.random(), 1.0); gl.clear(gl.COLOR_BUFFER_BIT); }, 100); } } catch(e) {}
            var memoryAlloc = bench(function() { var buf = new ArrayBuffer(1024); var view = new Uint8Array(buf); view[0] = 255; }, 100);
            var memoryOps = bench(function() { var arr = new Float64Array(100); for (var i = 0; i < 100; i++) { arr[i] = i * 1.5; } arr.sort(); }, 100);
            var cryptoHash = bench(function() { var data = 'benchmark test string for hashing'; var hash = 0; for (var i = 0; i < data.length; i++) { var char = data.charCodeAt(i); hash = ((hash << 5) - hash) + char; hash = hash & hash; } return hash; }, 100);
            return { hardwareConcurrency: navigator.hardwareConcurrency || 0, timerResolution: resolution, mathOps: mathOps, arrayOps: arrayOps, stringOps: stringOps, objectOps: objectOps, regexpOps: regexpOps, domCreate: domCreate, domQuery: domQuery, domModify: domModify, canvas2d: canvas2d, webgl: webgl, memoryAlloc: memoryAlloc, memoryOps: memoryOps, cryptoHash: cryptoHash };
        } catch(e) { return { error: e.message }; }
    })()
    """
    // swiftlint:enable line_length
}
