import SwiftUI

/// About screen: version/build, original-author attribution, data
/// provenance, and the licensing-review notice.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (build \(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("XSky for iPad")
                            .font(.largeTitle.weight(.semibold))
                        Text(version)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("about.version")
                        Text("An interactive equatorial sky atlas.")
                            .foregroundStyle(.secondary)
                    }

                    section(
                        "Original Author",
                        """
                        XSky is a native port of the XSky X Window System \
                        application, copyright 1992–6 Terry R. Friedrichsen \
                        (terry@venus.sunquest.com). The astronomical behavior, \
                        catalog handling, and chart semantics of this app are \
                        derived directly from that original C source.
                        """)

                    section(
                        "Data",
                        """
                        Bundled catalogs: the Yale Catalog of Bright Stars \
                        (4th ed.), the Revised New General Catalog of \
                        Non-Stellar Objects, an optical catalog of \
                        quasi-stellar objects, constellation boundaries and \
                        outlines, and common-name tables, all as distributed \
                        with the original XSky. Constellation identification \
                        uses the boundary table of Dr. Nancy G. Roman (1987, \
                        PASP, 99, 695) with Herget precession credited to \
                        Dr. Wayne H. Warren, Jr. Speed-up contributions by \
                        Brian Wing.
                        """)

                    section(
                        "Licensing Review",
                        """
                        The original XSky license permits copying and \
                        redistribution but not sale, and requires crediting \
                        the original author. The bundled catalog data and \
                        this application require a human licensing review \
                        before any App Store or commercial distribution. \
                        See ACKNOWLEDGEMENTS, Copyright.txt, and Warranty.txt \
                        in the application bundle.
                        """)
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("about.done")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("about")
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }
}
