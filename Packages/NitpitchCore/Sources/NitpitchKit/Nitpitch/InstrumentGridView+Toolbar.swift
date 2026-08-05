import NitpitchCore
import SwiftUI

// The grid's toolbar vocabulary — the tuning pill, the padlock, and the
// instrument's … menu — out of the type body for the SwiftLint gauges; the
// view proper stays the part worth one eyeful.
extension InstrumentGridView {
    /// The tuning, front and centre — "Drop D" is what this screen is *for*,
    /// so it's the header control rather than a buried setting. Only tunings
    /// that fit this instrument's strings are offered at all: a mismatched
    /// count is a type error, not a runtime surprise.
    var tuningMenu: some View {
        Menu {
            // Two marks with two meanings. The CHECK is identity: the row you
            // picked — the loaded preset, or the tuning when nothing loaded.
            // The EQUALS asserts an action, not object equality: "loading
            // this would change nothing". For a tuning-only preset that stays
            // exactly true whatever the reference is — it says nothing about
            // the reference, and its label (no "· A=442" suffix) already
            // declares that scope. Without the split, a preset saved from
            // Standard and Standard itself both showed checked — true, but
            // reading as a contradiction.
            ForEach(orderedTunings, id: \.self) { tuning in
                let matches = tuning.strings == instance.strings
                Button {
                    store.setTuning(id: instance.id, strings: tuning.strings)
                } label: {
                    menuRow(
                        tuningText(tuning.name ?? "Custom"),
                        checked: matches && claimIsFree,
                        matching: matches)
                }
            }

            let fitting = orderedPresets
            if !fitting.isEmpty {
                Divider()
                ForEach(fitting) { preset in
                    Button {
                        presets.load(preset, onto: instance, in: store)
                    } label: {
                        menuRow(
                            presetLabel(preset),
                            checked: loadedPreset?.id == preset.id && valuesMatch(preset),
                            matching: valuesMatch(preset))
                    }
                }
            }

            // Only where the instrument's construction allows a choice:
            // string players tune beatless fifths (the pure 3:2, ~2¢ wide
            // of equal); frets ARE equal temperament, so fretted
            // instruments never see this row. Lives in the tuning menu
            // because it's part of what the targets ARE — and presets
            // carry it, like the reference.
            if instance.template?.family == .bowed {
                Picker(
                    selection: Binding(
                        get: { instance.appliedTemperament },
                        set: { store.setTemperament(id: instance.id, $0) })
                ) {
                    Text("Equal", bundle: .module).tag(Temperament.equal)
                    if instance.template?.id == "double-bass" {
                        Text("Pure fourths", bundle: .module).tag(Temperament.pure)
                    } else {
                        Text("Pure fifths", bundle: .module).tag(Temperament.pure)
                    }
                } label: {
                    Text("Temperament", bundle: .module)
                }
            }

            Divider()
            Button {
                presetName = ""
                isSavingPreset = true
            } label: {
                Label {
                    Text("Save as preset…", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            // Always offered: the sheet stopped being deletion-only when
            // the pins moved in — gating it on having saved a preset locked
            // a fresh user out of pinning Standard entirely.
            Button {
                isManagingPresets = true
            } label: {
                Label {
                    Text("Manage presets…", bundle: .module)
                } icon: {
                    Image(systemName: "list.bullet")
                }
            }
        } label: {
            HStack(spacing: 4) {
                pillText
                    .font(.callout.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(instance.isLocked)
        .accessibilityIdentifier("grid.tuning")
    }

    /// What the pill says: the preset you picked — with "(edited)" once a
    /// granular edit drifts from its payload — or the tuning identity when
    /// nothing is claimed. Only an explicit menu pick replaces the claim;
    /// without the suffix, stepping one string of "T-bird" made the pill
    /// announce "Drop D", a catalog tuning nobody picked.
    var pillText: Text {
        guard let loaded = loadedPreset else {
            return tuningText(instance.tuningName ?? "Custom")
        }
        if valuesMatch(loaded) {
            return Text(verbatim: loaded.name)
        }
        return Text("\(loaded.name) (edited)", bundle: .module)
    }

    /// The padlock, ambient and fixed: one glance says whether this
    /// instrument's setup is frozen, one tap flips it. Closed and prominent
    /// when locked, open and quiet when not — the same glyph pair every
    /// platform uses for exactly this.
    var lockButton: some View {
        Button {
            store.setLocked(id: instance.id, !instance.isLocked)
        } label: {
            Image(systemName: instance.isLocked ? "lock.fill" : "lock.open")
                .foregroundStyle(
                    instance.isLocked ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .accessibilityIdentifier("grid.lock")
        .accessibilityLabel(
            instance.isLocked
                ? Text("Unlock", bundle: .module) : Text("Lock", bundle: .module))
    }

    var layoutMenu: some View {
        Menu {
            // The instrument's own management, right where the instrument
            // is — the chooser's swipe and long-press carry the same
            // actions for those who find them.
            Section {
                Button {
                    instrumentRenameText = instance.name
                    isRenamingInstrument = true
                } label: {
                    Label {
                        Text("Rename", bundle: .module)
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
                Button {
                    if let template = instance.template {
                        duplicating = Creation(template: template, source: instance)
                    }
                } label: {
                    Label {
                        Text("Duplicate", bundle: .module)
                    } icon: {
                        Image(systemName: "plus.square.on.square")
                    }
                }
                Button {
                    isEditingStrings = true
                } label: {
                    Label {
                        Text("Edit strings…", bundle: .module)
                    } icon: {
                        Image(systemName: "music.note.list")
                    }
                }
                .disabled(instance.isLocked)
            }

            Picker(selection: $columns) {
                // Auto is the default and must stay reachable — without this
                // row, picking a fixed count was a one-way door.
                Text("Auto", bundle: .module).tag(0)
                ForEach(1...3, id: \.self) { count in
                    Text("\(count) across", bundle: .module).tag(count)
                }
            } label: {
                Text("Columns", bundle: .module)
            }

            // The octave layer on every cell and strip at once — checking a
            // whole instrument's intonation without switching strings. A
            // session choice behind a toggle, unlike the string view's
            // ambient panel: this screen is a tuning surface first.
            Toggle(isOn: $isIntonating) {
                Label {
                    Text("Check intonation", bundle: .module)
                } icon: {
                    Image(systemName: "tuningfork")
                }
            }

            // The Mac's way into the strips: its window doesn't rotate, so
            // the metaphor is a deliberate choice here, not a shape.
            #if os(macOS)
            Toggle(isOn: $settings.stripsOnMac) {
                Text("Strings as strips", bundle: .module)
            }
            #endif

            Section {
                Button(role: .destructive) {
                    deleteInstrument()
                } label: {
                    Label {
                        Text("Delete", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .disabled(instance.isLocked)
            }

            if LaunchStores.isDebug {
                Divider()
                Button {
                    isShowingDebug = true
                } label: {
                    Label {
                        Text(verbatim: "Detector…")
                    } icon: {
                        Image(systemName: "waveform.badge.magnifyingglass")
                    }
                }
                .accessibilityIdentifier("grid.debug")
            }
        } label: {
            // A badge while anything is off its shipped value, so a surprising
            // reading is never mistaken for how the app actually behaves.
            Image(
                systemName: detection.isModified
                    ? "ellipsis.circle.fill" : "ellipsis.circle"
            )
            .foregroundStyle(detection.isModified ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
        }
        // The identifier predates the menu's growth; tests know it by it.
        .accessibilityIdentifier("grid.columns")
        .accessibilityLabel(Text("Instrument options", bundle: .module))
    }

    /// Deleting from inside the instrument: satellites go with it, and the
    /// screen closes — there is nothing left to stand on.
    func deleteInstrument() {
        settings.favorites.removeAll { $0 == instance.id }
        settings.presetPins.removeAll { $0.instrumentID == instance.id }
        store.remove(id: instance.id)
        dismissGrid()
    }

}
