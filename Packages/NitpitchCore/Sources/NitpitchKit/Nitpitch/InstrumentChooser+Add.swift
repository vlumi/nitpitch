import NitpitchCore
import SwiftUI

// The + flow, out of the chooser's main file for the file gauge: pick a
// KIND, and one sheet (`InstrumentCreator`) decides everything else.

extension InstrumentChooser {
    /// One entry per instrument kind, in the list's own family grouping so
    /// the order reads as organized. No counts, no variants, no submenus:
    /// the creation sheet owns every question after "what kind" — the
    /// common case is two taps (kind, Create), and the odd shapes edit the
    /// same sheet's string list instead of answering a separate question.
    var addMenu: some View {
        Menu {
            ForEach(Instrument.addable, id: \.family) { group in
                Section {
                    ForEach(group.instruments) { template in
                        Button {
                            creating = template
                        } label: {
                            Text(LocalizedStringKey(template.name), bundle: .module)
                        }
                    }
                } header: {
                    Text(LocalizedStringKey(group.family.name), bundle: .module)
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityIdentifier("chooser.add")
        .accessibilityLabel(Text("Add instrument", bundle: .module))
    }
}
