import NitpitchCore
import SwiftUI

/// Where a chosen instrument's per-string dials will live (ROADMAP § 2).
///
/// A placeholder: it lists the strings the grid will show, so the navigation
/// can be exercised end to end, and stops there.
///
/// It deliberately **does not subscribe to audio**. Subscribing would exercise
/// a path the real grid is going to replace, and a placeholder that quietly
/// held a live subscription is exactly the kind of thing that masks an
/// ownership bug rather than revealing one.
struct InstrumentGridView: View {
    let instrument: Instrument
    let naming: NoteNaming

    var body: some View {
        List {
            ForEach(Array(instrument.notes.enumerated()), id: \.offset) { _, note in
                HStack {
                    Text(verbatim: note.name(in: naming))
                        .font(.title3.weight(.medium))
                    Text(verbatim: "\(note.octave)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: String(format: "%.1f Hz", note.frequency()))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(LocalizedStringKey(instrument.name), bundle: .module))
        .accessibilityIdentifier("grid.placeholder")
    }
}
