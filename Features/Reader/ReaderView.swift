import SwiftUI

/// Wrapper that lets the reader hop between chapters of the same series.

struct ReaderView: View {

    @State private var chapter: Chapter

    init(chapter: Chapter) { _chapter = State(initialValue: chapter) }

    private var siblings: [Chapter] { chapter.manga?.sortedChapters ?? [chapter] }

    private var index: Int? { siblings.firstIndex(where: { $0.id == chapter.id }) }

    private var previousChapter: Chapter? {

        guard let i = index, i > 0 else { return nil }

        return siblings[i - 1]

    }

    private var nextChapter: Chapter? {

        guard let i = index, i < siblings.count - 1 else { return nil }

        return siblings[i + 1]

    }

    var body: some View {

        Group {
            if chapter.isRemote && !chapter.isDownloaded {
                RemoteChapterView(chapter: chapter)
            } else {
                ReaderContent(

            chapter: chapter,

            onPrevious: previousChapter.map { target -> () -> Void in { chapter = target } },

            onNext: nextChapter.map { target -> () -> Void in { chapter = target } }

        )

            }
        }
        .id(chapter.id)

    }

}

private struct ReaderContent: View {

    let chapter: Chapter

    let onPrevious: (() -> Void)?

    let onNext: (() -> Void)?

    @State private var vm: ReaderViewModel

    @State private var current: Int

    @State private var showControls = true

    @State private var autoScroll = false
    @State private var coverTint = Color.black
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("reader.preload") private var preload = 2
    @AppStorage("reader.cacheMB") private var cacheMB = 64
    @AppStorage("reader.autoscrollSpeed") private var scrollSpeed = 40.0

    @Environment(\.displayScale) private var displayScale
    @AppStorage("reader.background") private var backgroundRaw = ReaderBackground.black.rawValue
    @AppStorage("reader.tapZones") private var tapZones = true
    @AppStorage("reader.keepAwake") private var keepAwake = true

    private var background: ReaderBackground { ReaderBackground(rawValue: backgroundRaw) ?? .black }

    init(chapter: Chapter, onPrevious: (() -> Void)?, onNext: (() -> Void)?) {

        self.chapter = chapter

        self.onPrevious = onPrevious

        self.onNext = onNext

        _vm = State(initialValue: ReaderViewModel(chapter: chapter))

        // Reopening a finished chapter starts from the beginning.

        let finished = chapter.isRead && chapter.lastPage >= chapter.pageCount - 1

        let start = finished ? 0 : chapter.lastPage

        _current = State(initialValue: max(0, min(start, max(chapter.pageCount - 1, 0))))

    }

    private var mode: ReaderMode { chapter.manga?.readerMode ?? .paged }

    private var direction: ReadingDirection { chapter.manga?.direction ?? .rightToLeft }

    private var pageCountIsOne: Bool { chapter.pageCount <= 1 }

    private var isPaged: Bool { mode == .paged }

    private var isRTL: Bool { isPaged && direction == .rightToLeft }

    private var fit: ImageFit { isPaged ? .screen : .width }

    var body: some View {

        ZStack {

            (background == .cover ? coverTint : background.color).ignoresSafeArea()

            if let error = vm.loadError {

                ReaderErrorView(message: error)

            } else {

                switch mode {

                case .paged:

                    PagedReader(vm: vm, current: $current, isRTL: isRTL, onTap: handleTap, onEdge: handleEdge)

                case .webtoon:

                    WebtoonReader(vm: vm, current: $current, onTap: {
                        autoScroll = false
                        toggleControls()
                    }, autoScroll: $autoScroll, scrollSpeed: scrollSpeed)

                }

            }

            if showControls && vm.loadError == nil {

                VStack {

                    Spacer()

                    VStack(spacing: 8) {

                        HStack {

                            Button { onPrevious?() } label: {

                                Image(systemName: "chevron.left.to.line")

                            }.disabled(onPrevious == nil)
                            .accessibilityLabel("Previous chapter")

                            Spacer()

                            Text("\(current + 1) / \(vm.pageCount)")

                                .font(.caption.monospacedDigit())
                                .accessibilityIdentifier("readerPageCount")

                            Spacer()

                            Button { onNext?() } label: {

                                Image(systemName: "chevron.right.to.line")

                            }.disabled(onNext == nil)
                            .accessibilityLabel("Next chapter")

                        }

                        .foregroundStyle(.white)

                        if mode == .webtoon {
                            Button {
                                autoScroll.toggle()
                            } label: {
                                Label(autoScroll ? "Pause autoscroll" : "Start autoscroll",
                                      systemImage: autoScroll ? "pause.fill" : "play.fill")
                            }
                            .accessibilityIdentifier("readerAutoscroll")
                            .disabled(reduceMotion || voiceOver)
                        }

                        Slider(value: Binding(get: { Double(current) },

                                              set: { current = Int($0.rounded()) }),

                               in: 0...Double(max(vm.pageCount - 1, 1)), step: 1)

                            .disabled(pageCountIsOne)
                            .accessibilityLabel("Page")
                            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)

                    }

                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .environment(\.colorScheme, .dark)
                    .frame(maxWidth: 600)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    .padding(.horizontal, 12).padding(.bottom, 8)

                }

            }

        }

        .navigationTitle(chapter.name)

        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)

        .toolbar(showControls ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)

        .toolbar {

            ToolbarItem(placement: .topBarTrailing) {

                Menu {

                    Picker("Mode", selection: Binding(

                        get: { mode },

                        set: { chapter.manga?.readerMode = $0 })) {

                        Text("Paged").tag(ReaderMode.paged)

                        Text("Webtoon (vertical)").tag(ReaderMode.webtoon)

                    }

                    if isPaged {

                        Picker("Direction", selection: Binding(

                            get: { direction },

                            set: { chapter.manga?.direction = $0 })) {

                            Text("Right to left").tag(ReadingDirection.rightToLeft)

                            Text("Left to right").tag(ReadingDirection.leftToRight)

                        }

                    }

                Picker("Background", selection: $backgroundRaw) {
                        ForEach(ReaderBackground.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Toggle("Tap edges to turn pages", isOn: $tapZones)
                    Toggle("Keep screen on", isOn: $keepAwake)
                } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Reader settings")

            }

        }

        .onChange(of: current) { _, new in

            vm.saveProgress(new)

            vm.preload(around: new, fit: fit)

        }

        .onChange(of: mode) { _, _ in

            autoScroll = false
            vm.clearCache()

            vm.preload(around: current, fit: fit)

        }

        .onAppear {

            vm.configureMemory(preload: preload, cacheMB: cacheMB)
            vm.open()

            vm.saveProgress(current, markRead: pageCountIsOne)

            vm.preload(around: current, fit: fit)

        }

        .preferredColorScheme(.dark)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onDisappear {
            autoScroll = false
            vm.clearCache()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { autoScroll = false; UIApplication.shared.isIdleTimerDisabled = false }
            else { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        }
        .onChange(of: reduceMotion) { _, value in if value { autoScroll = false } }
        .onChange(of: voiceOver) { _, value in if value { autoScroll = false } }
        .onChange(of: preload) { _, _ in vm.configureMemory(preload: preload, cacheMB: cacheMB) }
        .onChange(of: cacheMB) { _, _ in vm.configureMemory(preload: preload, cacheMB: cacheMB) }
        .task {
            let data = chapter.manga?.coverData
            let tint = await Task.detached(priority: .utility) { CoverReaderTint.extract(data) }.value
            if !Task.isCancelled { coverTint = tint.color }
        }
        .onChange(of: keepAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
        .statusBarHidden(!showControls)
        .background { keyboardShortcuts }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateViewport(geo.size) }
                    .onChange(of: geo.size) { _, size in updateViewport(size) }
            }
            .ignoresSafeArea()
        }

    }

    /// Hardware-keyboard paging for iPad and Mac. Left/right follow the reading direction.
    private var keyboardShortcuts: some View {
        Group {
            Button("Left") { step(isRTL ? 1 : -1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Right") { step(isRTL ? -1 : 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Next") { step(1) }.keyboardShortcut(.space, modifiers: [])
            Button("Down") { step(1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("Up") { step(-1) }.keyboardShortcut(.upArrow, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func updateViewport(_ size: CGSize) {
        vm.configureViewport(size, scale: displayScale)
    }

    private func step(_ delta: Int) {
        current = min(max(current + delta, 0), max(vm.pageCount - 1, 0))
    }

    /// Edge taps turn pages (following reading direction); the centre toggles the controls.
    /// Pulling a zoomed page past its left or right edge goes to the neighbouring page on that side.
    private func handleEdge(_ side: Int) { step(side * (isRTL ? -1 : 1)) }

    private func handleTap(_ x: CGFloat) {
        guard tapZones else { toggleControls(); return }
        if x < 0.25 { step(isRTL ? 1 : -1) }
        else if x > 0.75 { step(isRTL ? -1 : 1) }
        else { toggleControls() }
    }

    private func toggleControls() {

        withAnimation { showControls.toggle() }

    }

}

// MARK: - Paged

private struct PagedReader: View {

    let vm: ReaderViewModel

    @Binding var current: Int

    let isRTL: Bool

    let onTap: (CGFloat) -> Void
    let onEdge: (Int) -> Void

    /// Maps logical page <-> TabView position. The mapping is its own inverse.

    private func flip(_ index: Int) -> Int { isRTL ? vm.pageCount - 1 - index : index }

    var body: some View {

        TabView(selection: Binding(

            get: { flip(current) },

            set: { current = flip($0) })) {

            ForEach(0..<vm.pageCount, id: \.self) { position in

                PageView(vm: vm, page: flip(position), onTap: onTap, onEdge: onEdge)

                    .tag(position)

            }

        }

        .tabViewStyle(.page(indexDisplayMode: .never))

    }

}

private struct PageView: View {

    let vm: ReaderViewModel

    let page: Int
    let onTap: (CGFloat) -> Void
    let onEdge: (Int) -> Void
    @State private var image: UIImage?
    @State private var retryID = UUID()

    var body: some View {

        Group {

            if let image {

                ZoomableImage(image: image, onSingleTap: onTap, onEdgeSwipe: onEdge)
                    .accessibilityIdentifier("readerImage")

            } else if vm.failedPages.contains(page) {
                VStack(spacing: 12) {
                    Text("This page could not be loaded.").foregroundStyle(.white)
                    Button("Retry") { retryID = UUID() }.buttonStyle(.borderedProminent)
                }
            } else {

                ProgressView().tint(.white)

                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    .contentShape(Rectangle())

                    .onTapGesture { onTap(0.5) }

            }

        }

        .task(id: "\(page)-\(retryID)-\(vm.imageRevision)") {
            let revision = vm.imageRevision
            image = nil
            let loaded = await vm.image(at: page, fit: .screen)
            if !Task.isCancelled && revision == vm.imageRevision { image = loaded }
        }

    }

}

