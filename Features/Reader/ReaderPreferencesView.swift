import SwiftUI

enum ReaderTuning {
    static func preload(_ value: Int) -> Int { min(max(value, 0), 4) }
    static func cacheMB(_ value: Int) -> Int { [32, 64, 128].contains(value) ? value : 64 }
    static func speed(_ value: Double) -> Double {
        guard value.isFinite else { return 40 }
        return min(max(value, 10), 100)
    }
}

struct ReaderPreferencesView: View {
    @AppStorage("reader.preload") private var preload = 2
    @AppStorage("reader.cacheMB") private var cacheMB = 64
    @AppStorage("reader.autoscrollSpeed") private var speed = 40.0
    var body: some View {
        Form {
            Section {
                Stepper("Preload \(ReaderTuning.preload(preload)) pages", value: $preload, in: 0...4)
                Picker("Image cache", selection: $cacheMB) {
                    Text("32 MB").tag(32)
                    Text("64 MB").tag(64)
                    Text("128 MB").tag(128)
                }
            } header: { Text("Reader memory") }
            footer: { Text("Preloading applies to local and downloaded chapters. The system may clear the image cache earlier when memory is needed.") }
            Section {
                Slider(value: $speed, in: 10...100, step: 10) { Text("Autoscroll speed") }
                Text("\(Int(ReaderTuning.speed(speed))) points per second").font(.caption)
            } header: { Text("Webtoon autoscroll") }
            footer: { Text("Start from the reader controls. Scrolling pauses when you touch the page, leave the reader, or switch apps. It is unavailable with Reduce Motion or VoiceOver enabled.") }
        }
        .navigationTitle("Reader")
    }
}
