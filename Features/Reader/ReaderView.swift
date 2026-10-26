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

        ReaderContent(

            chapter: chapter,

            onPrevious: previousChapter.map { target -> () -> Void in { chapter = target } },

            onNext: nextChapter.map { target -> () -> Void in { chapter = target } }

        )

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

            Color.black.ignoresSafeArea()

            if let error = vm.loadError {

                Text(error).foregroundStyle(.white)

            } else {

                switch mode {

                case .paged:

                    PagedReader(vm: vm, current: $current, isRTL: isRTL, onTap: toggleControls)

                case .webtoon:

                    WebtoonReader(vm: vm, current: $current, onTap: toggleControls)

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

                        Slider(value: Binding(get: { Double(current) },

                                              set: { current = Int($0.rounded()) }),

                               in: 0...Double(max(vm.pageCount - 1, 1)), step: 1)

                            .disabled(pageCountIsOne)
                            .accessibilityLabel("Page")
                            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)

                    }

                    .padding().background(.ultraThinMaterial)

                }

            }

        }

        .navigationTitle(chapter.name)

        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)

        .toolbar(showControls ? .visible : .hidden, for: .navigationBar)

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

                } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Reader settings")

            }

        }

        .onChange(of: current) { _, new in

            vm.saveProgress(new)

            vm.preload(around: new, fit: fit)

        }

        .onChange(of: mode) { _, _ in

            vm.clearCache()

            vm.preload(around: current, fit: fit)

        }

        .onAppear {

            vm.open()

            vm.saveProgress(current, markRead: pageCountIsOne)

            vm.preload(around: current, fit: fit)

        }

        .preferredColorScheme(.dark)
        .statusBarHidden(!showControls)

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

    let onTap: () -> Void

    /// Maps logical page <-> TabView position. The mapping is its own inverse.

    private func flip(_ index: Int) -> Int { isRTL ? vm.pageCount - 1 - index : index }

    var body: some View {

        TabView(selection: Binding(

            get: { flip(current) },

            set: { current = flip($0) })) {

            ForEach(0..<vm.pageCount, id: \.self) { position in

                PageView(vm: vm, page: flip(position), onTap: onTap)

                    .tag(position)

            }

        }

        .tabViewStyle(.page(indexDisplayMode: .never))

        .ignoresSafeArea()

    }

}

private struct PageView: View {

    let vm: ReaderViewModel

    let page: Int

    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var retryID = UUID()

    var body: some View {

        Group {

            if let image {

                ZoomableImage(image: image, onSingleTap: onTap)
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

                    .onTapGesture(perform: onTap)

            }

        }

        .task(id: "\(page)-\(retryID)") { image = await vm.image(at: page, fit: .screen) }

    }

}

