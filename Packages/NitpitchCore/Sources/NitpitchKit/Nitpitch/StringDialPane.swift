import NitpitchCore
import SwiftUI

/// A neighbouring string's pane while it slides in: the dial at rest and the
/// target it will aim for — no reading, because nothing is listening for it
/// yet. Mirrors `StringDialPane`'s geometry exactly (the stepper slots are
/// blank stand-ins) so the live pane can take its place without a shift.
struct GhostDialPane: View {
    let note: Note
    let naming: NoteNaming

    var body: some View {
        TunerDial(cents: 0, inTune: false, isReading: false) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Color.clear.frame(
                        width: StringDialPane.stepperSlot, height: StringDialPane.stepperSlot)
                    NoteNameLabel(
                        note: note, naming: naming, fontSize: StringDialPane.noteFontSize
                    )
                    .frame(width: StringDialPane.nameSlotWidth)
                    Color.clear.frame(
                        width: StringDialPane.stepperSlot, height: StringDialPane.stepperSlot)
                }
                Text(verbatim: "—")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(height: StringDialPane.readoutHeight)
        }
        .accessibilityHidden(true)
    }
}

/// The dial and its readout, observing the string's model.
struct StringDialPane: View {
    @ObservedObject var tuner: StringTunerViewModel
    let naming: NoteNaming
    let isLocked: Bool
    let canStepTarget: (Int) -> Bool
    let stepTarget: (Int) -> Void

    /// The readout's fixed geometry, shared with `GhostDialPane` so the
    /// mirror is structure rather than a promise: the note's font size,
    /// its fixed name slot (so the − and + don't wobble with the name's
    /// width), the 40pt stepper slots, and the readout's total height
    /// (name line + spacing + cents line).
    static let noteFontSize: CGFloat = 46
    static let nameSlotWidth: CGFloat = 190
    static let stepperSlot: CGFloat = 40
    static let readoutHeight: CGFloat = noteFontSize * 1.15 + 4 + 20

    var body: some View {
        TunerDial(cents: displayCents, inTune: isInTune, isReading: isReading) {
            readout
        }
    }

    /// The *target*, not the detection: this screen answers "how far is this
    /// from D", so D is the headline and the cents are the answer — and the
    /// steppers flanking it change what's being asked: nudge D2 down to C2
    /// and this string's target IS C2 (the tuning relabels itself Custom).
    /// The chromatic tuner shows what it heard; this shows what you're after.
    private var readout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                targetStep(systemName: "minus", id: "string.down", by: -1)
                NoteNameLabel(
                    note: tuner.target, naming: naming, fontSize: Self.noteFontSize
                )
                .frame(width: Self.nameSlotWidth)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("string.target")
                .accessibilityLabel(tuner.target.accessibleName(in: naming))
                targetStep(systemName: "plus", id: "string.up", by: 1)
            }
            Text(verbatim: centsLabel)
                .font(.title3.monospacedDigit())
                .foregroundStyle(
                    isInTune
                        ? AnyShapeStyle(Color.green)
                        : AnyShapeStyle(.secondary)
                )
                .accessibilityIdentifier("string.cents")
        }
        .frame(height: Self.readoutHeight)
    }

    /// A tap target, not a `Button` — same reasoning as the string arrows:
    /// with the widened hit area a swipe often begins here, and it must
    /// join the page-pan instead of being held hostage until release.
    private func targetStep(systemName: String, id: String, by delta: Int) -> some View {
        let enabled = canStepTarget(delta) && !isLocked
        return Image(systemName: systemName)
            .font(.body.weight(.medium))
            .frame(width: Self.stepperSlot, height: Self.stepperSlot)
            // The glyph slot stays 40pt so the row's geometry holds, but
            // the hit area reaches out into the empty stretch between
            // the stepper and the note name — a tap in the visual
            // no-man's-land was clearly aimed at the stepper, and
            // nothing else in the row is interactive to dispute it.
            .contentShape(Rectangle().inset(by: -28))
            .foregroundStyle(.secondary)
            .opacity(enabled ? 1 : 0.35)
            .onTapGesture { stepTarget(delta) }
            .disabled(!enabled)
            .accessibilityIdentifier(id)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                delta < 0
                    ? Text("Lower target", bundle: .module)
                    : Text("Raise target", bundle: .module))
    }

    private var centsLabel: String {
        guard case .reading(let cents, _) = tuner.state else { return "—" }
        return TuningReadout.centsLabel(cents)
    }

    private var displayCents: Double {
        if case .reading(let cents, _) = tuner.state { return cents }
        return 0
    }

    private var isInTune: Bool {
        if case .reading(let cents, _) = tuner.state {
            return TuningDisplay.isInTune(cents: cents)
        }
        return false
    }

    private var isReading: Bool {
        if case .reading = tuner.state { return true }
        return false
    }
}
