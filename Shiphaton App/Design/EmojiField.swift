//
//  EmojiField.swift
//  Shiphaton App
//
//  A one-emoji text box. Tapping it brings up the emoji keyboard straight
//  away, and whatever gets typed or pasted collapses to the last emoji in
//  it, so the binding only ever holds a single emoji or nothing at all.
//

import SwiftUI
import UIKit

struct EmojiField: UIViewRepresentable {
    @Binding var emoji: String
    var fontSize: CGFloat = 30

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: fontSize)
        field.textAlignment = .center
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .done
        // The tile is the caret: a blinking bar next to a 30pt emoji only
        // looks like a glitch.
        field.tintColor = .clear
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        if field.text != emoji { field.text = emoji }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let parent: EmojiField

        init(_ parent: EmojiField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            let picked = (field.text ?? "").last(where: \.isEmojiLike).map(String.init) ?? ""
            if field.text != picked { field.text = picked }
            if parent.emoji != picked { parent.emoji = picked }
            // The emoji keyboard has no return key. One emoji is all the
            // box holds, so picking it is the whole job: the keyboard can
            // go, and the tile keeps showing what was chosen.
            if !picked.isEmpty { field.resignFirstResponder() }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return true
        }
    }
}

/// A text field that asks for the emoji keyboard the moment it becomes
/// first responder. Falls back to the usual keyboard when the person has
/// removed the emoji one in Settings, they can still switch by hand.
final class EmojiTextField: UITextField {
    override var textInputContextIdentifier: String? { "shiphaton.emojiField" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}

private extension Character {
    /// True for pictographic emoji, including flags, skin tones and
    /// keycap-free sequences, false for plain letters and digits (which
    /// Unicode also tags as "emoji" because they can take a keycap).
    var isEmojiLike: Bool {
        guard let first = unicodeScalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        return first.properties.isEmoji && unicodeScalars.count > 1
    }
}
