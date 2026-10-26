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

        .ignoresSafeArea()

    }

}

private struct WebtoonPage: View {

    let vm: ReaderViewModel

    let page: Int

    @State private var image: UIImage?

    var body: some View {

        Group {

            if let image {

                Image(uiImage: image)

                    .resizable()

                    .scaledToFit()

                    .frame(maxWidth: .infinity)

            } else {

                Color.black

                    .frame(height: 500)

                    .overlay(ProgressView().tint(.white))

            }

        }

        .task(id: page) { image = await vm.image(at: page, fit: .width) }

    }

}

