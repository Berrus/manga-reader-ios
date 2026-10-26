import SwiftUI

import UIKit

final class ZoomScrollView: UIScrollView {

    let imageView = UIImageView()

    override init(frame: CGRect) {

        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFit

        addSubview(imageView)

        minimumZoomScale = 1

        maximumZoomScale = 4

        bouncesZoom = true

        showsHorizontalScrollIndicator = false

        showsVerticalScrollIndicator = false

        contentInsetAdjustmentBehavior = .never

        backgroundColor = .clear

    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {

        super.layoutSubviews()

        // Only manage the frame at rest; UIKit owns it while zoomed.

        if zoomScale == minimumZoomScale {

            imageView.frame = bounds

            contentSize = bounds.size

        }

    }

}

struct ZoomableImage: UIViewRepresentable {

    let image: UIImage

    /// Receives the tap position as 0...1 across the width (0.5 while zoomed in).
    var onSingleTap: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onSingleTap: onSingleTap) }

    func makeUIView(context: Context) -> ZoomScrollView {

        let scroll = ZoomScrollView()

        scroll.delegate = context.coordinator

        scroll.imageView.image = image
        scroll.imageView.isAccessibilityElement = true
        scroll.imageView.accessibilityLabel = "Comic page"
        scroll.imageView.accessibilityIdentifier = "readerImage"

        context.coordinator.scrollView = scroll

        let double = UITapGestureRecognizer(target: context.coordinator,

                                            action: #selector(Coordinator.doubleTap(_:)))

        double.numberOfTapsRequired = 2

        scroll.addGestureRecognizer(double)

        let single = UITapGestureRecognizer(target: context.coordinator,

                                            action: #selector(Coordinator.singleTap))

        single.require(toFail: double)

        scroll.addGestureRecognizer(single)

        return scroll

    }

    func updateUIView(_ scroll: ZoomScrollView, context: Context) {

        context.coordinator.onSingleTap = onSingleTap

        if scroll.imageView.image !== image {

            scroll.zoomScale = 1

            scroll.imageView.image = image

            scroll.setNeedsLayout()

        }

    }

    final class Coordinator: NSObject, UIScrollViewDelegate {

        var onSingleTap: (CGFloat) -> Void

        weak var scrollView: ZoomScrollView?

        init(onSingleTap: @escaping (CGFloat) -> Void) { self.onSingleTap = onSingleTap }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {

            (scrollView as? ZoomScrollView)?.imageView

        }

        @objc func singleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = scrollView, scroll.zoomScale <= 1.01, scroll.bounds.width > 0 else {
                onSingleTap(0.5)
                return
            }
            let x = gesture.location(in: scroll).x - scroll.contentOffset.x
            onSingleTap(min(max(x / scroll.bounds.width, 0), 1))
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {

            guard let scroll = scrollView else { return }

            if scroll.zoomScale > 1 {

                scroll.setZoomScale(1, animated: true)

            } else {

                let point = gesture.location(in: scroll.imageView)

                let scale: CGFloat = 2.5

                let size = CGSize(width: scroll.bounds.width / scale,

                                  height: scroll.bounds.height / scale)

                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,

                                  width: size.width, height: size.height)

                scroll.zoom(to: rect, animated: true)

            }

        }

    }

}

