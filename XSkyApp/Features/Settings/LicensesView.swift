import SwiftUI

/// Full-text third-party notices, licenses, and catalog attributions,
/// consolidated from Resources/LegacyCatalogs/NOTICES.txt.
struct LicensesView: View {
    private var noticesText: String {
        guard let url = Bundle.main.url(forResource: "NOTICES", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "NOTICES.txt could not be loaded from the app bundle."
        }
        return text
    }

    var body: some View {
        ScrollView {
            Text(noticesText)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .navigationTitle("Licenses & Notices")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("licenses")
    }
}
