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

    var onSingleTap: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onSingleTap: onSingleTap) }

    func makeUIView(context: Context) -> ZoomScrollView {

        let scroll = ZoomScrollView()

        scroll.delegate = context.coordinator

        scroll.imageView.image = image

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

        var onSingleTap: () -> Void

        weak var scrollView: ZoomScrollView?

        init(onSingleTap: @escaping () -> Void) { self.onSingleTap = onSingleTap }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {

            (scrollView as? ZoomScrollView)?.imageView

        }

        @objc func singleTap() { onSingleTap() }

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

