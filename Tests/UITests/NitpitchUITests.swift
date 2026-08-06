import XCTest

/// Local-only UI regression tests (`make uitest`); CI never runs
/// `xcodebuild test`.
///
/// The simulator has no usable microphone — it delivers silence — so these
/// cover launch, navigation, and layout. The needle responding to a real note
/// is verified on device by hand; the DSP itself is covered headlessly by the
/// NitpitchCore suite.
final class NitpitchUITests: XCTestCase {
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Wipe persisted settings so each run starts identical (see LaunchStores).
        app.launchArguments = ["-uitest-clean"] + extraArguments
        app.launch()
        return app
    }

    /// The toolbar menu. Its identifier lands on descendants too, so match the
    /// button rather than "any" — the broad query finds several elements and
    /// XCTest refuses to guess which one to tap.
    private func openLayoutMenu(_ app: XCUIApplication) {
        let menu = app.buttons["grid.columns"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
    }

    /// Root → chooser → violin's grid, which several tests need to reach.
    private func openViolinGrid(_ app: XCUIApplication) {
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        let violin = app.descendants(matching: .any)["chooser.violin"]
        XCTAssertTrue(violin.waitForExistence(timeout: 5))
        violin.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["grid.strings"].waitForExistence(timeout: 5))
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLaunchesToAStatusOrReading() {
        let app = launch()
        // With no audio the app should sit in a status state rather than showing
        // a stale or garbage note.
        let status = app.staticTexts["tuner.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
    }

    /// The launch screen is chromatic whatever instrument was chosen last, so
    /// what's on it is the way *into* an instrument rather than a picker
    /// showing one. (This replaces a test that asserted the opposite.)
    func testLaunchesOnTheChromaticTuner() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.descendants(matching: .any)["grid.strings"].exists,
            "the app should not open on an instrument")
    }

    func testChoosingAnInstrumentOpensItsStrings() {
        let app = launch()
        openViolinGrid(app)
    }

    /// The chooser is pushed, not presented: back from a grid lands on the
    /// list you chose from, then on the tuner — the stack you walked.
    func testBackFromGridReturnsToTheChooser() {
        let app = launch()
        openViolinGrid(app)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["chooser.violin"].waitForExistence(timeout: 5),
            "back from the grid should land on the chooser")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["tuner.instrument"].waitForExistence(timeout: 5),
            "back from the chooser should land on the tuner")
    }

    // MARK: - The string view

    /// A grid cell opens its string full screen; the arrows walk the strings;
    /// back returns to the grid.
    func testCellOpensStringViewAndArrowsWalkStrings() {
        let app = launch()
        openViolinGrid(app)

        let cell = app.descendants(matching: .any)["grid.cell.0"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()

        let target = app.descendants(matching: .any)["string.target"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.label.hasPrefix("G"), "first violin string is G3")

        let next = app.descendants(matching: .any)["string.next"]
        next.tap()
        XCTAssertTrue(target.label.hasPrefix("D"), "next string up is D4")

        // The first string has no previous; walking back down re-enables it.
        let previous = app.descendants(matching: .any)["string.prev"]
        previous.tap()
        XCTAssertTrue(target.label.hasPrefix("G"))
        XCTAssertFalse(previous.isEnabled, "no string below G3")

        // For the eye as much as the assertions — the layout is judged from
        // the report.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "string-view"
        shot.lifetime = .keepAlways
        add(shot)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["grid.strings"].waitForExistence(timeout: 5),
            "back from a string should land on the grid")
    }

    /// The intonation panel is ambient on the string view: the octave's own
    /// dial and both capture values sit below the switcher, no mode to find.
    /// Launched under -demo, whose synthetic measurement populates them —
    /// the simulator's real microphone is silence and captures nothing.
    func testIntonationPanelIsAmbientAndCaptures() {
        let app = launch(extraArguments: ["-demo"])
        openViolinGrid(app)
        app.descendants(matching: .any)["grid.cell.0"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["string.target"].waitForExistence(timeout: 5))

        let open = app.descendants(matching: .any)["intonation.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["intonation.dial"].exists)
        let delta = app.descendants(matching: .any)["intonation.delta"]
        XCTAssertTrue(delta.exists)

        // The demo's measurement lands: the delta stops reading "—".
        let populated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "—"), object: delta)
        XCTAssertEqual(
            XCTWaiter().wait(for: [populated], timeout: 5), .completed,
            "the demo measurement should populate the delta")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "intonation"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The reference tone: the string view's speaker toggles it on and off,
    /// and the button honestly reports which.
    func testReferenceToneToggles() {
        let app = launch(extraArguments: ["-demo"])
        openViolinGrid(app)
        app.descendants(matching: .any)["grid.cell.0"].firstMatch.tap()

        let tone = app.descendants(matching: .any)["string.tone"].firstMatch
        XCTAssertTrue(tone.waitForExistence(timeout: 5))
        tone.tap()
        let sounding = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "On"), object: tone)
        XCTAssertEqual(
            XCTWaiter().wait(for: [sounding], timeout: 5), .completed,
            "the speaker should report the tone sounding")

        tone.tap()
        let silent = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Off"), object: tone)
        XCTAssertEqual(
            XCTWaiter().wait(for: [silent], timeout: 5), .completed,
            "toggling back should silence it")
    }

    /// The interval lane: the demo's synthetic double stop populates the
    /// chip under the meter — pair, beats, and its accessibility value.
    func testIntervalLaneShowsTheDemoDoubleStop() {
        let app = launch(extraArguments: ["-demo"])
        openViolinGrid(app)

        let chip = app.descendants(matching: .any)["tuner.interval"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        let populated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "beats per second"),
            object: chip)
        XCTAssertEqual(
            XCTWaiter().wait(for: [populated], timeout: 5), .completed,
            "the demo double stop should populate the chip")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "interval-lane"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The grid's speakers: the reference A by the stepper, one per string
    /// cell — and the handover: tapping another speaker mid-tone takes the
    /// sound over (a glide) rather than stacking or restarting.
    func testGridSpeakersHandOver() {
        let app = launch(extraArguments: ["-demo"])
        openViolinGrid(app)

        let reference = app.descendants(matching: .any)["grid.tone.reference"].firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        reference.tap()
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value == %@", "On"),
                        object: reference)
                ], timeout: 5), .completed,
            "the reference A should sound")

        let cell = app.descendants(matching: .any)["grid.tone.0"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value == %@", "On"), object: cell),
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value == %@", "Off"),
                        object: reference),
                ], timeout: 5), .completed,
            "the string's speaker should take the tone over from the reference")

        cell.tap()
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value == %@", "Off"), object: cell)
                ], timeout: 5), .completed,
            "tapping the sounding speaker stops it")
    }

    /// The target stepper: nudge G3 down, the headline changes, the grid's
    /// cell follows when you go back, and the header relabels the tuning
    /// Custom — the whole edit loop, end to end.
    func testEditingATargetFollowsThroughToTheGrid() {
        let app = launch()
        openViolinGrid(app)
        app.descendants(matching: .any)["grid.cell.0"].firstMatch.tap()

        let target = app.descendants(matching: .any)["string.target"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.label.hasPrefix("G"))

        let down = app.descendants(matching: .any)["string.down"]
        down.tap()
        XCTAssertTrue(target.label.hasPrefix("F"), "G3 down a semitone is F sharp 3")

        app.navigationBars.buttons.firstMatch.tap()
        let cell = app.descendants(matching: .any)["grid.cell.0"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(cell.label.hasPrefix("F"), "the grid cell follows the edit")
        XCTAssertTrue(
            app.buttons["grid.tuning"].firstMatch.label.contains("Custom"),
            "an edited named tuning relabels itself Custom")
    }

    /// Instrument management on iOS: the toolbar + adds (type picked from
    /// its menu), swipe reveals duplicate, swipe deletes an added one.
    func testAddDuplicateAndDeleteInstruments() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        // The + opens the creation sheet — one kind, one sheet — and
        // cancelling it creates NOTHING (adding used to create first and
        // offer a rename after).
        app.buttons["chooser.add"].firstMatch.tap()
        app.buttons["Guitar"].firstMatch.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        let secondGuitar = app.buttons["Guitar 2"].firstMatch
        XCTAssertFalse(
            secondGuitar.waitForExistence(timeout: 2),
            "a cancelled creation leaves nothing behind")

        // Same door, confirmed this time — the sheet's suggested name
        // stands unless edited, and the common case is two taps.
        app.buttons["chooser.add"].firstMatch.tap()
        app.buttons["Guitar"].firstMatch.tap()
        let create = app.buttons["creator.create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        // Rows surface as buttons labelled with the instrument's name.
        XCTAssertTrue(secondGuitar.waitForExistence(timeout: 5))

        // Duplicate opens the creation sheet prefilled from the source —
        // "a copy" is "near what I want", and Cancel would create nothing.
        let guitar = app.descendants(matching: .any)["chooser.guitar"].firstMatch
        guitar.swipeLeft()
        app.buttons["Duplicate"].firstMatch.tap()
        let duplicateCreate = app.buttons["creator.create"].firstMatch
        XCTAssertTrue(duplicateCreate.waitForExistence(timeout: 5))
        duplicateCreate.tap()
        XCTAssertTrue(app.buttons["Guitar 3"].firstMatch.waitForExistence(timeout: 5))

        // Delete the added guitar by swiping it.
        secondGuitar.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(secondGuitar.waitForExistence(timeout: 2))
    }

    /// The creation sheet's odd-shape path, end to end: the string list
    /// waits behind the disclosure, adding a high string grows the draft,
    /// Create makes it real, and the grid shows the extra dial.
    func testCreationSheetEditsTheStrings() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        app.buttons["chooser.add"].firstMatch.tap()
        app.buttons["Violin"].firstMatch.tap()

        // The string list is an accordion in the same sheet — no separate
        // "custom" anywhere; editing IS what custom means.
        let summary = app.staticTexts["4 strings"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        summary.tap()
        let addHigh = app.buttons["editor.add.high"].firstMatch
        XCTAssertTrue(addHigh.waitForExistence(timeout: 5))
        addHigh.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["editor.row.4"].firstMatch
                .waitForExistence(timeout: 5),
            "a fifth string appears in the draft")
        app.buttons["creator.create"].firstMatch.tap()

        // The grown instrument opens with five dials.
        let row = app.buttons["Violin 2"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["grid.cell.4"].firstMatch
                .waitForExistence(timeout: 5),
            "the fifth dial exists")
    }

    /// The shape chooses the presentation: rotate to landscape and the dials
    /// become strips — strings drawn as strings — rotate back and the grid
    /// returns.
    func testWideViewportShowsStrips() {
        let app = launch()
        openViolinGrid(app)
        XCTAssertTrue(
            app.descendants(matching: .any)["grid.cell.0"].firstMatch.waitForExistence(
                timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let strip = app.descendants(matching: .any)["strips.row.0"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "wide shows strings as strings")
        // Geometry proves the layout genuinely went landscape — a screenshot
        // can lie sideways (XCUITest captures the raw framebuffer), a frame
        // can't.
        XCTAssertGreaterThan(
            strip.frame.width, strip.frame.height * 4,
            "a strip should be much wider than tall")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "strips-view"
        shot.lifetime = .keepAlways
        add(shot)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(
            app.descendants(matching: .any)["grid.cell.0"].firstMatch.waitForExistence(
                timeout: 5), "tall shows the dial grid")
    }

    // MARK: - Tunings and the lock

    /// Switching the guitar to Drop D retargets the low string's dial — the
    /// header menu is the tuning control, and the instance remembers.
    func testTuningMenuRetunesTheGrid() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        let guitar = app.descendants(matching: .any)["chooser.guitar"]
        XCTAssertTrue(guitar.waitForExistence(timeout: 5))
        guitar.tap()

        let cell = app.descendants(matching: .any)["grid.cell.0"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(cell.label.hasPrefix("E"), "guitar standard bottom string is E")

        let tuningMenu = app.buttons["grid.tuning"].firstMatch
        XCTAssertTrue(tuningMenu.waitForExistence(timeout: 5))
        tuningMenu.tap()
        let dropD = app.buttons["Drop D"].firstMatch
        XCTAssertTrue(dropD.waitForExistence(timeout: 5))
        dropD.tap()

        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(cell.label.hasPrefix("D"), "Drop D bottom string is D")
    }

    /// The preset loop, end to end: set Drop D, save it as "Gig" (tuning
    /// only), go back to Standard, load Gig — and the header reads Drop D
    /// again, because the values are the identity.
    func testSaveAndLoadAPreset() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        app.descendants(matching: .any)["chooser.guitar"].firstMatch.tap()

        let tuningMenu = app.buttons["grid.tuning"].firstMatch
        XCTAssertTrue(tuningMenu.waitForExistence(timeout: 5))
        tuningMenu.tap()
        app.buttons["Drop D"].firstMatch.tap()

        tuningMenu.tap()
        app.buttons["Save as preset…"].firstMatch.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Gig")
        // The sheet's defaults stand (payload checkboxes on): the flow under
        // test is save-and-load, and A=440 riding along changes nothing.
        app.buttons["preset.save.confirm"].firstMatch.tap()
        XCTAssertTrue(
            tuningMenu.label.contains("Gig"),
            "saving claims the preset — the pill shows what you just named")

        tuningMenu.tap()
        app.buttons["Standard"].firstMatch.tap()
        XCTAssertTrue(tuningMenu.label.contains("Standard"))

        tuningMenu.tap()
        // Prefix match: the row's label carries the payload suffix ("Gig
        // · A=440"), which is the point of the label.
        let gig = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Gig")
        ).firstMatch
        XCTAssertTrue(gig.waitForExistence(timeout: 5), "the saved preset should be offered")
        gig.tap()
        XCTAssertTrue(
            tuningMenu.label.contains("Gig"),
            "the pill shows the picked preset, not the tuning it matches")
    }

    /// A pinned preset is a launch shortcut into the setup: pin "Gig" to
    /// the guitar in its presets sheet, and a chip appears under the
    /// guitar's rack row; tapping it opens the guitar WITH Gig loaded.
    func testPinnedPresetOpensTheSetup() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        app.descendants(matching: .any)["chooser.guitar"].firstMatch.tap()

        // Set up Drop D, save it as "Gig", pin it in the presets sheet.
        let tuningMenu = app.buttons["grid.tuning"].firstMatch
        XCTAssertTrue(tuningMenu.waitForExistence(timeout: 5))
        tuningMenu.tap()
        app.buttons["Drop D"].firstMatch.tap()
        tuningMenu.tap()
        app.buttons["Save as preset…"].firstMatch.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Gig")
        // The sheet's defaults stand (payload checkboxes on): the flow under
        // test is save-and-load, and A=440 riding along changes nothing.
        app.buttons["preset.save.confirm"].firstMatch.tap()

        tuningMenu.tap()
        app.buttons["Manage presets…"].firstMatch.tap()
        let pin = app.descendants(matching: .any)["presets.pin.Gig"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        app.buttons["Done"].firstMatch.tap()

        // Leave the guitar in a different tuning, so the pin has work to do.
        tuningMenu.tap()
        app.buttons["Standard"].firstMatch.tap()

        // Star the guitar so it has a rack row, then walk back home.
        app.navigationBars.buttons.firstMatch.tap()
        let star = app.descendants(matching: .any)["chooser.pin.guitar"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        star.tap()
        app.navigationBars.buttons.firstMatch.tap()

        // The chip sits under the guitar's row; tapping it opens the
        // guitar with Gig loaded — an explicit pick, drift overwritten.
        let chip = app.descendants(matching: .any)["pin.guitar.Gig"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the pin renders as a chip")
        chip.tap()
        let pill = app.buttons["grid.tuning"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertTrue(
            pill.label.contains("Gig"),
            "the pin opens the instrument INTO the preset")
    }

    /// The padlock is ambient: a fixed toolbar toggle, no dialogs anywhere.
    /// Locked controls dim; the lock itself is the one way back — and it
    /// follows the instrument into the string view.
    func testTheLockFreezesControlsWithoutDialogs() {
        let app = launch()
        openViolinGrid(app)

        let lock = app.buttons["grid.lock"].firstMatch
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        lock.tap()

        let tuningMenu = app.descendants(matching: .any)["grid.tuning"].firstMatch
        XCTAssertTrue(tuningMenu.waitForExistence(timeout: 5))
        XCTAssertFalse(tuningMenu.isEnabled, "locked: the tuning menu is disabled")

        // The lock follows the instrument into the string view.
        app.descendants(matching: .any)["grid.cell.0"].firstMatch.tap()
        let stringLock = app.buttons["string.lock"].firstMatch
        XCTAssertTrue(stringLock.waitForExistence(timeout: 5))
        let down = app.descendants(matching: .any)["string.down"]
        XCTAssertTrue(down.waitForExistence(timeout: 5))
        XCTAssertFalse(down.isEnabled, "locked: the target stepper is disabled")

        // Unlocking here unfreezes everywhere — it's the instrument's lock.
        stringLock.tap()
        XCTAssertTrue(down.isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(tuningMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(tuningMenu.isEnabled, "unlocked in the string view, unlocked here")
    }

    // MARK: - Favourites

    /// The point of the row: one tap from launch to the violin's strings,
    /// no list in between. Violin starts pinned.
    func testFavoriteChipGoesStraightToTheGrid() {
        let app = launch()
        let chip = app.descendants(matching: .any)["favorite.violin"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["grid.strings"].waitForExistence(timeout: 5))
        // And back is ONE step to the tuner — the chip skipped the chooser,
        // so the stack must have too.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["tuner.instrument"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["chooser.violin"].exists)
    }

    /// Pinning in the chooser puts a chip on the launch screen; unpinning
    /// removes it.
    func testPinningFromTheChooser() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        // Every factory instrument is seeded and ordinary — the star is
        // right there on the row.
        let pin = app.descendants(matching: .any)["chooser.pin.guitar"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["favorite.guitar"].waitForExistence(timeout: 5),
            "pinning should add a chip")

        button.tap()
        pin.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["favorite.guitar"].exists,
            "unpinning should remove the chip")
    }

    // MARK: - Detector diagnostics

    /// The diagnostics screen is gated on `-debug`, and the gate is the only
    /// thing keeping it out of a shipped build — so it's worth a test that it
    /// really is shut by default.
    func testDetectorScreenIsHiddenWithoutTheDebugFlag() {
        let app = launch()
        openViolinGrid(app)

        openLayoutMenu(app)
        XCTAssertFalse(
            app.descendants(matching: .any)["grid.debug"].waitForExistence(timeout: 2),
            "the detector screen must not be reachable in a normal launch")
    }

    /// The grid's intonation layer: the … menu toggle lights the octave row
    /// on every cell — proven through the accessibility value, which gains
    /// the delta once the demo's synthetic measurement lands.
    func testIntonationLayerTogglesAcrossTheGrid() {
        let app = launch(extraArguments: ["-demo"])
        openViolinGrid(app)
        let cell = app.descendants(matching: .any)["grid.cell.0"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        openLayoutMenu(app)
        let toggle = app.descendants(matching: .any)["Check intonation"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        let measured = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "octave delta"),
            object: cell)
        XCTAssertEqual(
            XCTWaiter().wait(for: [measured], timeout: 5), .completed,
            "the cell's octave layer should carry the demo measurement")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "grid-intonation"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testDetectorScreenOpensUnderTheDebugFlag() {
        let app = launch(extraArguments: ["-debug"])
        openViolinGrid(app)

        openLayoutMenu(app)
        let entry = app.descendants(matching: .any)["grid.debug"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["debug.detector"].waitForExistence(timeout: 5))
        // Every string gets a row, so a subharmonic on a neighbour is visible.
        for name in ["G3", "D4", "A4", "E5"] {
            XCTAssertTrue(
                app.staticTexts[name].waitForExistence(timeout: 2),
                "no diagnostics row for \(name)")
        }

        // Attached for the screenshot in the test report — this screen is judged
        // by eye as much as by assertion.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "detector-diagnostics"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Chromatic is the screen you arrive from, so offering it in the chooser
    /// would be offering to navigate to where you already are.
    func testTheChooserDoesNotOfferChromatic() {
        let app = launch()
        let button = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["chooser.violin"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["chooser.chromatic"].exists)
    }
}
