import SwiftUI
import UIKit

/// Drives SwiftUI's backing scroll view through public UIKit APIs only.
struct ScrollAutoAdvance: UIViewRepresentable {
    @Binding var isRunning: Bool
    var pointsPerSecond: Double

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        context.coordinator.probe = view
        return view
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateUIView(_ view: UIView, context: Context) {
        let binding = $isRunning
        context.coordinator.onStop = { binding.wrappedValue = false }
        context.coordinator.speed = ReaderTuning.speed(pointsPerSecond)
        if isRunning { context.coordinator.start() } else { context.coordinator.stop() }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator: NSObject {
        weak var probe: UIView?
        private var link: CADisplayLink?
        private var previous: CFTimeInterval = 0
        private var missingFrames = 0
        var speed = 40.0
        var onStop: (() -> Void)?
        func start() {
            guard link == nil else { return }
            previous = 0
            missingFrames = 0
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            self.link = link
            link.add(to: .main, forMode: .common)
        }
        func stop() { link?.invalidate(); link = nil; previous = 0 }
        private func finish() {
            stop()
            DispatchQueue.main.async { [weak self] in self?.onStop?() }
        }
        @objc private func tick(_ link: CADisplayLink) {
            guard !UIAccessibility.isReduceMotionEnabled, !UIAccessibility.isVoiceOverRunning,
                  UIApplication.shared.applicationState == .active else { finish(); return }
            var ancestor = probe?.superview
            while ancestor != nil && !(ancestor is UIScrollView) { ancestor = ancestor?.superview }
            guard let scroll = ancestor as? UIScrollView else {
                missingFrames += 1
                if missingFrames > 120 { finish() }
                return
            }
            guard !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating else { finish(); return }
            let delta = previous == 0 ? 0 : min(link.timestamp - previous, 0.1)
            previous = link.timestamp
            let bottom = max(-scroll.adjustedContentInset.top,
                             scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            guard scroll.contentOffset.y < bottom - 0.5 else { finish(); return }
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
                                           y: min(bottom, scroll.contentOffset.y + speed * delta)), animated: false)
        }
    }
}
