import SwiftUI

struct WebtoonReader: View {

    let vm: ReaderViewModel

    @Binding var current: Int

    let onTap: () -> Void
    @Binding var autoScroll: Bool
    let scrollSpeed: Double

    @State private var scrolledID: Int?
    @State private var zoom: CGFloat = 1
    @State private var zoomAtPinchStart: CGFloat = 1

    /// shortcut: zoomed pages are the normal-resolution bitmap scaled up (a little soft above 2x); decode at a higher resolution if that bothers readers.
    private static let maxZoom: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            reader(width: min(geo.size.width, ReaderViewModel.webtoonMaxWidth) * zoom, viewport: geo.size.width)
        }
    }

    /// Pages are as wide as the screen at 1x; pinching widens them and the view scrolls sideways.
    private func reader(width: CGFloat, viewport: CGFloat) -> some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 0) {
                ForEach(0..<vm.pageCount, id: \.self) { page in
                    WebtoonPage(vm: vm, page: page, width: width)
                }
            }
            .frame(minWidth: viewport)
            .scrollTargetLayout()
            .background(ScrollAutoAdvance(isRunning: $autoScroll, pointsPerSecond: scrollSpeed))
        }

        .scrollPosition(id: $scrolledID, anchor: .top)

        .onAppear { scrolledID = current }

        .onChange(of: scrolledID) { _, new in

            if let new, new != current { current = new }

        }

        .onChange(of: current) { _, new in

            if new != scrolledID { scrolledID = new }

        }

        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { zoom = min(max(zoomAtPinchStart * $0.magnification, 1), Self.maxZoom) }
                .onEnded { _ in zoomAtPinchStart = zoom }
        )
        .onTapGesture(count: 2) {
            withAnimation { zoom = zoom > 1 ? 1 : 2 }
            zoomAtPinchStart = zoom
        }
        .onTapGesture(perform: onTap)
    }
}

private struct WebtoonPage: View {
    let vm: ReaderViewModel
    let page: Int
    let width: CGFloat

    @State private var image: UIImage?
    @State private var retryID = UUID()

    var body: some View {

        Group {

            if let image {

                Image(uiImage: image)

                    .resizable()

                    .scaledToFit()
                    .accessibilityLabel("Comic page")
                    .accessibilityIdentifier("webtoonImage")

                    .frame(width: width)

            } else if vm.failedPages.contains(page) {
                VStack(spacing: 12) {
                    Text("This page could not be loaded.").foregroundStyle(.white)
                    Button("Retry") { retryID = UUID() }.buttonStyle(.borderedProminent)
                }.frame(height: 200)
            } else {

                Color.black
                    .frame(width: width, height: 500)

                    .overlay(ProgressView().tint(.white))

            }

        }

        .task(id: "\(page)-\(retryID)-\(vm.imageRevision)") {
            let revision = vm.imageRevision
            image = nil
            let loaded = await vm.image(at: page, fit: .width)
            if !Task.isCancelled && revision == vm.imageRevision { image = loaded }
        }
        .onDisappear { image = nil }

    }

}

