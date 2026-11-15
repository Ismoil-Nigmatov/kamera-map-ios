import SwiftUI
import UIKit

struct PhoneField: UIViewRepresentable {
    @Binding var digits: String
    var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(digits: $digits)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .phonePad
        field.textContentType = .telephoneNumber
        field.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        field.placeholder = "90 123 45 67"
        field.delegate = context.coordinator
        field.accessibilityIdentifier = "phoneField"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.digits = $digits
        let formatted = Format.nationalPhone(digits)
        if field.text != formatted {
            field.text = formatted
        }
        if isFocused, !field.isFirstResponder, field.window != nil {
            DispatchQueue.main.async {
                field.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var digits: Binding<String>

        init(digits: Binding<String>) {
            self.digits = digits
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let bounds = Range(range, in: current) else { return false }

            let next: String
            if string.isEmpty, !current[bounds].isEmpty, current[bounds].allSatisfy({ !$0.isNumber }) {
                let before = Format.nationalDigits(String(current[..<bounds.lowerBound]))
                let after = Format.nationalDigits(String(current[bounds.upperBound...]))
                next = String(before.dropLast()) + after
            } else {
                next = Format.nationalDigits(current.replacingCharacters(in: bounds, with: string))
            }

            digits.wrappedValue = next
            textField.text = Format.nationalPhone(next)
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
            textField.sendActions(for: .editingChanged)
            return false
        }
    }
}
