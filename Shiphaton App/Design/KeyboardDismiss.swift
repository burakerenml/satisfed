//
//  KeyboardDismiss.swift
//  Shiphaton App
//
//  Tap anywhere that isn't a text box and the keyboard goes away. One
//  recognizer on the window covers every screen and every sheet, so no
//  field has to opt in and none can be forgotten.
//

import SwiftUI
import UIKit

enum KeyboardDismiss {
    /// Drops whatever keyboard is up, wherever it came from.
    static func putAway() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}

extension View {
    /// Attach once, at the root. Every keyboard in the app then drops on
    /// the first tap that lands outside a text input.
    func dismissesKeyboardOnTap() -> some View {
        background(KeyboardDismissInstaller().frame(width: 0, height: 0))
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private var installed = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard !installed, let window else { return }
            installed = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(putKeyboardAway))
            // Never swallow or hold up the tap: buttons, rows, and swipes
            // under it must behave exactly as if it weren't there.
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
        }

        @objc private func putKeyboardAway() {
            KeyboardDismiss.putAway()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// A tap on another text box is a move, not a dismissal: leave it
        /// alone so the keyboard hands over instead of flickering away.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextInput { return false }
                view = current.superview
            }
            return true
        }
    }
}
