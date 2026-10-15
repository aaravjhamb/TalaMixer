//
//  AxisLockedPan.swift
//  TalaMixer
//
//  A pan recognizer locked to one axis.
//
//  SwiftUI's `DragGesture` cannot do this properly: once it activates, the
//  touch is claimed even if the handler ignores it, so a control inside a
//  scroll view permanently steals scrolling in its footprint. A UIKit pan
//  recognizer can genuinely *fail* for wrong-axis drags — the touch then goes
//  to the enclosing scroll view as if the control weren't there.
//
//  The delegate also asks scroll views to wait for this recognizer's verdict,
//  so a correct-axis drag wins even when the race is close.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

struct AxisLockedPan: UIViewRepresentable {
    enum Axis { case horizontal, vertical }

    var axis: Axis
    /// Cumulative translation since the drag began.
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void
    var onDoubleTap: (() -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: AxisLockedPan

        init(parent: AxisLockedPan) {
            self.parent = parent
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .changed:
                let t = recognizer.translation(in: recognizer.view)
                parent.onChanged(CGSize(width: t.x, height: t.y))
            case .ended, .cancelled, .failed:
                parent.onEnded()
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onDoubleTap?()
        }

        /// The axis lock: refuse drags that lead on the other axis. Refusal is
        /// a real gesture failure, so the scroll view takes the touch over.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            switch parent.axis {
            case .horizontal: return abs(velocity.x) > abs(velocity.y)
            case .vertical: return abs(velocity.y) > abs(velocity.x)
            }
        }

        /// Ask enclosing scroll views to wait for our verdict, so a
        /// correct-axis drag reaches the control even when the scroll
        /// recognizer would otherwise have raced it.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

#else

/// Non-UIKit fallback (the project also lists macOS/visionOS as platforms):
/// a plain drag with a direction check. Less precise, but functional.
struct AxisLockedPan: View {
    enum Axis { case horizontal, vertical }

    var axis: Axis
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void
    var onDoubleTap: (() -> Void)?

    @State private var rejected = false
    @State private var began = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        if !began {
                            began = true
                            let t = value.translation
                            let wrongAxis = axis == .horizontal
                                ? abs(t.height) > abs(t.width)
                                : abs(t.width) > abs(t.height)
                            rejected = wrongAxis
                        }
                        guard !rejected else { return }
                        onChanged(value.translation)
                    }
                    .onEnded { _ in
                        let wasRejected = rejected
                        began = false
                        rejected = false
                        if !wasRejected { onEnded() }
                    }
            )
            .onTapGesture(count: 2) { onDoubleTap?() }
    }
}

#endif
