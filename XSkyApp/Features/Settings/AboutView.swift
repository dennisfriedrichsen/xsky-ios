import SwiftUI
import UIKit

/// About screen: version/build, original-author attribution, data
/// provenance, and the licensing-review notice.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var usingOriginalIcon = UIApplication.shared.alternateIconName == "AppIcon-Original"

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
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("XSky")
                                .font(.largeTitle.weight(.semibold))
                            Text(version)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("about.version")
                            Text("An interactive equatorial sky atlas.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        OriginalIconGlyph()
                            .frame(width: 42, height: 72)
                            .padding(10)
                            .background(.black, in: RoundedRectangle(cornerRadius: 10))
                    }

                    section(
                        "Original Author",
                        """
                        XSky is a native port of the XSky X Window System \
                        application, copyright 1992–6 Terry R. Friedrichsen. \
                        The astronomical behavior, catalog handling, and \
                        chart semantics of this app are derived directly \
                        from that original C source.

                        terry@venus.sunquest.com (Internet)
                        uunet!sunquest!terry (Usenet)
                        terry@sds.sdsc.edu (alternate address; I live in Tucson)
                        """)

                    section(
                        "A Word of Warranty",
                        """
                        The original xsky shipped with this warranty: \
                        "xsky doesn't do anything; it is not merchantable, \
                        and it is not fit for any purpose whatsoever. In \
                        fact, don't use xsky at all; it's free, and you're \
                        getting what you paid for." Thirty years and a full \
                        rewrite later, we're pleased to report that xsky \
                        STILL doesn't do anything.
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
                        "Cursor",
                        """
                        The pointer shown when a mouse or trackpad is \
                        attached is the X11 Trek Cursor, the original \
                        cursor glyph from the X Window System (X11) \
                        `cursor` font (`XC_trek`, glyph 142), distributed \
                        as part of X.Org's `font-cursor-misc` package. \
                        The package's original copyright notice states \
                        that these glyphs are "unencumbered."
                        """)

                    if UIApplication.shared.supportsAlternateIcons {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("App Icon").font(.headline)
                            Text(
                                """
                                Switch to a reproduction of the original \
                                xsky icon, a 28×48 X11 bitmap glyph from the \
                                early 1990s.
                                """)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Toggle("Use original xsky icon", isOn: $usingOriginalIcon)
                                .accessibilityIdentifier("about.originalIconToggle")
                                .onChange(of: usingOriginalIcon) { _, useOriginal in
                                    UIApplication.shared.setAlternateIconName(
                                        useOriginal ? "AppIcon-Original" : nil)
                                }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Licensing Review").font(.headline)
                        Text(
                            """
                            The original XSky license permits copying and \
                            redistribution but not sale, and requires crediting \
                            the original author. This app is offered at no \
                            cost in the App Store. The source and authorship \
                            of the bundled quasi-stellar object catalog is \
                            still being confirmed.
                            """)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        NavigationLink("View Full Licenses & Notices") {
                            LicensesView()
                        }
                        .font(.callout)
                        .accessibilityIdentifier("about.licensesLink")
                    }
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Acknowledged") { dismiss() }
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
