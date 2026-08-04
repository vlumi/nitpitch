import NitpitchCore
import SwiftUI

/// One sheet creates the instrument: name and strings together, prefilled
/// from the template, with Create the moment anything comes to exist and
/// Cancel leaving no trace.
///
/// The common case is two taps — pick the kind, Create. Kinds that really
/// come in sizes (double bass, the guitars) show their common counts as
/// one-tap chips; the full string list waits behind a disclosure for the
/// genuinely odd shapes. There is no "custom" to select anywhere — like
/// tunings, the shape's identity follows the values: touch the list and
/// the chips simply stop matching.
struct InstrumentCreator: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var settings: Settings
    let template: Instrument
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var strings: [Int]
    @State private var isListExpanded = false

    init(store: InstrumentStore, settings: Settings, template: Instrument) {
        self.store = store
        self.settings = settings
        self.template = template
        _name = State(initialValue: store.nextAddedName(for: template))
        _strings = State(initialValue: template.strings)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(text: $name) { Text("Name", bundle: .module) }
                        .accessibilityIdentifier("creator.name")
                }
                Section {
                    if template.commonStringCounts.count > 1 {
                        countChips
                    }
                    DisclosureGroup(isExpanded: $isListExpanded) {
                        StringListEditor(
                            strings: strings,
                            naming: settings.naming,
                            lowOnTop: settings.stripsLowOnTop
                        ) { edited in
                            strings = edited
                        }
                    } label: {
                        stringsSummary
                    }
                }
            }
            .navigationTitle(Text("New instrument", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Creation happens HERE: nothing existed while the sheet
                    // was open, so Cancel had nothing to clean up.
                    Button {
                        store.add(of: template, named: name, strings: strings)
                        dismiss()
                    } label: {
                        Text("Create", bundle: .module)
                    }
                    .accessibilityIdentifier("creator.create")
                }
            }
        }
        .frame(
            minWidth: 380,
            // Rows: name, chips (when shown) and the summary always; the
            // strings and their two add rows only while disclosed.
            minHeight: InstrumentEditor.sheetHeight(
                rows: (template.commonStringCounts.count > 1 ? 3 : 2)
                    + (isListExpanded ? strings.count + 2 : 0),
                chrome: 180))
    }

    /// The kind's common sizes as one-tap chips. A chip lights only while
    /// the draft IS that size's standard stringing — edit anything and the
    /// light just goes out; "custom" is a state of the values, not a choice.
    private var countChips: some View {
        HStack(spacing: 8) {
            ForEach(template.commonStringCounts, id: \.self) { count in
                let chipStrings = template.strings(count: count)
                let matches = strings == chipStrings
                Button {
                    strings = chipStrings
                } label: {
                    Text("\(count) strings", bundle: .module)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                matches
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.secondary.opacity(0.1))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("creator.count.\(count)")
            }
            Spacer(minLength: 0)
        }
    }

    /// What the disclosure hides, said on its label: the count, and a name
    /// for the pitches — "Standard" whenever they're the count's standard
    /// stringing (a chip's 5-string bass is standard even though the
    /// catalog's named tunings only know four strings), a catalog name when
    /// one matches, "Custom" only when nothing does.
    private var stringsSummary: some View {
        HStack(spacing: 6) {
            Text("\(strings.count) strings", bundle: .module)
            Text(LocalizedStringKey(stringsLabel), bundle: .module)
                .foregroundStyle(.secondary)
        }
    }

    private var stringsLabel: String {
        if strings == template.strings(count: strings.count) { return "Standard" }
        return template.knownTuning(matching: strings)?.name ?? "Custom"
    }
}
