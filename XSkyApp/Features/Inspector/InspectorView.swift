import SwiftUI
import XSkyCore

/// Object inspector: identity, designations, position, catalog data as
/// semantic rows, and label/centering actions.
struct InspectorView: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        Group {
            if let details = workspace.selectedDetails,
                let selection = workspace.selection
            {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(details)
                        designations(details)
                        rows(details)
                        actions(details, selection: selection)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "No Selection", systemImage: "scope",
                    description: Text("Tap an object on the chart."))
            }
        }
        .background(Color(white: 0.05))
        .accessibilityIdentifier("inspector")
    }

    private func header(_ details: ObjectDetails) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(details.preferredName)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("inspector.name")
            Text(details.catalogName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func designations(_ details: ObjectDetails) -> some View {
        if !details.designations.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Designations")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(details.designations, id: \.self) { d in
                    Text(d).font(.callout.monospacedDigit())
                }
            }
        }
    }

    private func rows(_ details: ObjectDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(details.rows) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.callout.monospacedDigit())
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.label): \(row.value)")
            }
        }
    }

    private func actions(
        _ details: ObjectDetails, selection: CatalogObjectID
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if let object = workspace.store?.object(selection) {
                    workspace.center(on: object.coordinate)
                }
            } label: {
                Label("Center on Chart", systemImage: "scope")
            }
            .accessibilityIdentifier("inspector.center")

            if workspace.hasLabel(forObject: selection) {
                Button {
                    workspace.removeLabel(forObject: selection)
                } label: {
                    Label("Remove Label", systemImage: "tag.slash")
                }
                .accessibilityIdentifier("inspector.removeLabel")
            } else {
                Button {
                    workspace.addLabel(forObject: selection)
                } label: {
                    Label("Add Label", systemImage: "tag")
                }
                .accessibilityIdentifier("inspector.addLabel")
            }

            Button {
                UIPasteboard.general.string =
                    details.designations.first ?? details.preferredName
            } label: {
                Label("Copy Designation", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("inspector.copyDesignation")

            Button {
                if let object = workspace.store?.object(selection) {
                    let ra = SexagesimalRA(radians: Radians(object.raRadians))
                    let dec = SexagesimalDec(radians: Radians(object.decRadians))
                    UIPasteboard.general.string =
                        "\(ra.displayString), \(dec.displayString)"
                }
            } label: {
                Label("Copy Coordinate", systemImage: "location")
            }
            .accessibilityIdentifier("inspector.copyCoordinate")
        }
        .buttonStyle(.bordered)
        .font(.callout)
    }
}
