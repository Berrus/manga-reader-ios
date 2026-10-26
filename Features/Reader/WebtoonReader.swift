import SwiftUI

struct WebtoonReader: View {

    let vm: ReaderViewModel

    @Binding var current: Int

    let onTap: () -> Void

    @State private var scrolledID: Int?

    var body: some View {

        ScrollView {

            LazyVStack(spacing: 0) {

                ForEach(0..<vm.pageCount, id: \.self) { page in

                    WebtoonPage(vm: vm, page: page)

                }

            }

            .scrollTargetLayout()

        }

        .scrollPosition(id: $scrolledID, anchor: .top)

        .onAppear { scrolledID = current }

        .onChange(of: scrolledID) { _, new in

            if let new, new != current { current = new }

        }

        .onChange(of: current) { _, new in

            if new != scrolledID { scrolledID = new }

        }

        .onTapGesture(perform: onTap)


    }

}

private struct WebtoonPage: View {

    let vm: ReaderViewModel

    let page: Int

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

                    .frame(maxWidth: ReaderViewModel.webtoonMaxWidth)

                    .frame(maxWidth: .infinity)

            } else if vm.failedPages.contains(page) {
                VStack(spacing: 12) {
                    Text("This page could not be loaded.").foregroundStyle(.white)
                    Button("Retry") { retryID = UUID() }.buttonStyle(.borderedProminent)
                }.frame(height: 200)
            } else {

                Color.black

                    .frame(height: 500)

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

