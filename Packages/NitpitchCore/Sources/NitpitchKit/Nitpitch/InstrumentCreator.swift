import NitpitchCore
import SwiftUI

/// One sheet creates the instrument: name and strings together, prefilled
/// from the template, with Create the moment anything comes to exist and
/// Cancel leaving no trace.
///
/// The common case is two taps — pick the kind, Create. Kinds that really
/// come in sizes (double bass, the guitars) show their common counts as
/// one-tap chips. There is no "custom" to select anywhere — like tunings,
/// the shape's identity follows the values: touch the list and the chips
/// simply stop matching.
///
/// The presentation forks by platform. iPhone: a List with the string rows
/// behind a disclosure, so the sheet stays calm. Mac: a plain fixed-width
/// form that HUGS its content (`fixedSize`, like the Settings window) with
/// the rows always visible — a disclosure there meant hunting a tiny
/// chevron and a shrink-then-grow resize, and every attempt to precompute
/// a List's height left either a keyhole or a margin.
struct InstrumentCreator: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var settings: Settings
    let template: Instrument
    /// Duplicate's shortcut: prefill everything from an existing
    /// instrument — "a copy" is usually "near what I want", and every
    /// prefilled field stays editable before anything exists.
    let source: InstrumentInstance?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var strings: [Int]
    @State private var isListExpanded = false

    init(
        store: InstrumentStore, settings: Settings, template: Instrument,
        source: InstrumentInstance? = nil
    ) {
        self.store = store
        self.settings = settings
        self.template = template
        self.source = source
        _name = State(
            initialValue: source.map {
                store.nextName(after: $0.name, templateID: template.id)
            } ?? store.nextAddedName(for: template))
        _strings = State(initialValue: source?.strings ?? template.strings)
    }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        sheetBody
        #endif
    }

    private func create() {
        let added = store.add(
            of: template, named: name, strings: strings,
            referenceHz: source?.referenceHz)
        // Creation is deliberate by construction — it earns the star, and
        // the rack cap keeps a growing collection from flooding the
        // launch screen.
        if !settings.favorites.contains(added.id) {
            settings.favorites.append(added.id)
        }
        dismiss()
    }

    #if os(macOS)
    private var macBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New instrument", bundle: .module)
                .font(.headline)
            TextField(text: $name) { Text("Name", bundle: .module) }
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("creator.name")
            if template.commonStringCounts.count > 1 {
                countChips
            }
            stringsSummary
                .font(.callout)
            // The rows, at their own deterministic heights; only a truly
            // long instrument scrolls, everything else is hugged exactly.
            ScrollView {
                VStack(spacing: 0) {
                    stringList
                }
            }
            .frame(height: min(StringListEditor.blockHeight(strings: strings.count), 440))
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Cancel", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    create()
                } label: {
                    Text("Create", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("creator.create")
            }
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
    #else
    private var sheetBody: some View {
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
                        stringList
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
                        create()
                    } label: {
                        Text("Create", bundle: .module)
                    }
                    .accessibilityIdentifier("creator.create")
                }
            }
        }
    }
    #endif

    private var stringList: some View {
        StringListEditor(
            strings: strings,
            naming: settings.naming,
            lowOnTop: settings.stripsLowOnTop
        ) { edited in
            strings = edited
        }
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

    /// The list's caption: the count, and a name for the pitches —
    /// "Standard" whenever they're the count's standard stringing (a
    /// chip's 5-string bass is standard even though the catalog's named
    /// tunings only know four strings), a catalog name when one matches,
    /// "Custom" only when nothing does.
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
