import SwiftUI
import UIKit

/// A LabeledContent value that copies itself to the clipboard — but only on
/// a second tap, so a casual tap while just reading the text doesn't
/// silently steal the clipboard. First tap arms it with a floating hint;
/// tapping again (or waiting it out) either copies or just disarms.
struct CopyableValue: View {
    let text: String

    @State private var isArmed = false
    @State private var didCopy = false

    var body: some View {
        Button {
            if isArmed {
                UIPasteboard.general.string = text
                isArmed = false
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    didCopy = false
                }
            } else {
                isArmed = true
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    isArmed = false
                }
            }
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                Text(text)
                    .multilineTextAlignment(.trailing)
                if isArmed {
                    Text("Klepni znovu pro zkopírování")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else if didCopy {
                    Text("Zkopírováno")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .sensoryFeedback(.success, trigger: didCopy)
    }
}
