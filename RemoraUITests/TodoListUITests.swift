//
//  TodoListUITests.swift
//  RemoraUITests
//
//  The To-Do list at the top of All Notes: to-dos as one-line rows in a
//  stored order, reordered by dragging, and also shown as grid tiles.
//

import XCTest

final class TodoListUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeDirectory: URL!

    private let ids = [
        "AAAAAAAA-1111-1111-1111-111111111111",
        "BBBBBBBB-2222-2222-2222-222222222222",
        "CCCCCCCC-3333-3333-3333-333333333333"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false

        storeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "RemoraUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try seedStore()

        app = XCUIApplication()
        app.launchEnvironment["UITEST_LAUNCH_ACTION"] = "allNotes"
        app.launchEnvironment["UITEST_STORE_DIRECTORY"] = storeDirectory.path
        app.launchEnvironment["REMORA_PANE_WIDTH"] = "640"
        app.launchEnvironment["REMORA_DISABLE_FAVICONS"] = "1"
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            "-trialNotesCreated", "0",
            "-autoTitleEnabled", "NO"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["All Notes"].waitForExistence(timeout: 8), "All Notes panel did not open")
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: storeDirectory)
    }

    // MARK: Seed

    /// Three pinned notes in a stored order (Alpha, Bravo, Charlie) that
    /// is the reverse of their recency, plus one unpinned note.
    private func seedStore() throws {
        func note(id: String, title: String, hour: Int, pinned: Bool) -> String {
            """
            {
              "id": "\(id)",
              "context": {
                "kind": "application",
                "identifier": "com.example.\(title.lowercased())",
                "displayName": "Example App"
              },
              "body": "\(title) first line",
              "createdAt": "2026-09-29T10:00:00Z",
              "updatedAt": "2026-09-29T1\(hour):00:00Z",
              "isPinned": \(pinned),
              "title": "\(title)"
            }
            """
        }
        let json = """
        {
          "version": 3,
          "todoOrder": ["\(ids[0])", "\(ids[1])", "\(ids[2])"],
          "notes": [
            \(note(id: ids[0], title: "Alpha", hour: 1, pinned: true)),
            \(note(id: ids[1], title: "Bravo", hour: 2, pinned: true)),
            \(note(id: ids[2], title: "Charlie", hour: 3, pinned: true)),
            \(note(id: "DDDDDDDD-4444-4444-4444-444444444444", title: "Delta", hour: 4, pinned: false))
          ]
        }
        """
        try json.write(to: storeDirectory.appending(path: "notes.json"), atomically: true, encoding: .utf8)
    }

    // MARK: Helpers

    private var rows: [XCUIElement] {
        app.descendants(matching: .any).matching(identifier: "todoRow").allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    private func row(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "todoRow")
            .matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// A grid tile, found by the title text inside it.
    private func tile(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "noteTile")
            .containing(NSPredicate(format: "elementType == %lu AND (label == %@ OR value == %@)",
                                    XCUIElement.ElementType.staticText.rawValue, title, title))
            .firstMatch
    }

    private var searchField: XCUIElement {
        let container = app.descendants(matching: .any).matching(identifier: "allNotesSearchField").firstMatch
        let inner = container.textFields.firstMatch
        if inner.exists { return inner }
        return app.textFields.firstMatch
    }

    private var rowTitles: [String] {
        rows.map { String($0.label.prefix { $0 != "," }) }
    }

    private func header(count: Int) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "To-Do, \(count) notes")).firstMatch
    }

    private func waitForRowTitles(_ expected: [String], timeout: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if rowTitles == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return rowTitles == expected
    }

    /// Every tile, in reading order (top to bottom, then leading to trailing).
    private var tiles: [XCUIElement] {
        app.descendants(matching: .any).matching(identifier: "noteTile").allElementsBoundByIndex
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    private func tileIndex(_ title: String) -> Int? {
        let target = tile(title).frame
        return tiles.firstIndex { $0.frame == target }
    }

    private func completeButton(_ title: String) -> XCUIElement {
        app.buttons["Complete \u{201C}\(title)\u{201D}"]
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func storedOrder() throws -> [String] {
        let data = try Data(contentsOf: storeDirectory.appending(path: "notes.json"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (json["todoOrder"] as? [String]) ?? []
    }

    // MARK: Tests

    func testPinnedNotesShowAsACountedListInStoredOrder() throws {
        XCTAssertTrue(row("Alpha").waitForExistence(timeout: 5), "To-Do rows missing\n\(app.debugDescription.prefix(2500))")
        XCTAssertTrue(header(count: 3).exists, "header should read To-Do with a count of 3")
        XCTAssertEqual(rowTitles, ["Alpha", "Bravo", "Charlie"])
        XCTAssertEqual(row("Alpha").label, "Alpha, Alpha first line")
        // Every note is also a tile below, to-dos included, under its own
        // heading and with no per-app section.
        XCTAssertTrue(app.staticTexts["Delta"].firstMatch.exists)
        let notesHeading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Notes, 4 notes")).firstMatch
        XCTAssertTrue(notesHeading.exists, "the grid should be headed Notes with a count of every note")
        for title in ["Alpha", "Bravo", "Charlie", "Delta"] {
            XCTAssertTrue(tile(title).exists, "\(title) should have a tile")
        }
        XCTAssertFalse(app.staticTexts["Apps"].exists, "notes are no longer grouped into sections")
    }

    func testSearchHidesTheToDoListAndFindsToDosInTheGrid() throws {
        XCTAssertTrue(row("Alpha").waitForExistence(timeout: 5))
        let todoList = app.descendants(matching: .any).matching(identifier: "todoList").firstMatch

        let field = searchField
        XCTAssertTrue(field.waitForExistence(timeout: 5), "search field not found")
        field.click()
        field.typeText("Bravo")

        XCTAssertTrue(todoList.waitForNonExistence(timeout: 3), "the To-Do list should hide while searching")
        XCTAssertTrue(tile("Bravo").waitForExistence(timeout: 3), "the to-do should be found as a tile")
        XCTAssertFalse(tile("Delta").exists, "only matches should show")

        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])

        XCTAssertTrue(todoList.waitForExistence(timeout: 3), "clearing the search should bring the list back")
        XCTAssertTrue(waitForRowTitles(["Alpha", "Bravo", "Charlie"]), "got \(rowTitles)")
    }

    func testDraggingARowReordersAndPersists() throws {
        XCTAssertTrue(row("Alpha").waitForExistence(timeout: 5))

        row("Alpha").press(forDuration: 0.3, thenDragTo: row("Charlie"))

        XCTAssertTrue(waitForRowTitles(["Bravo", "Charlie", "Alpha"]), "got \(rowTitles)")
        XCTAssertTrue(app.staticTexts["All Notes"].exists, "a drag must not open the note")

        // Saves are debounced.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(try storedOrder(), [ids[1], ids[2], ids[0]])
    }

    func testContextMenuCompleteTicks() throws {
        XCTAssertTrue(row("Bravo").waitForExistence(timeout: 5))

        row("Bravo").rightClick()
        let complete = app.menuItems["Complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.click()

        XCTAssertTrue(waitForRowTitles(["Alpha", "Charlie"]), "got \(rowTitles)")
        XCTAssertTrue(header(count: 2).waitForExistence(timeout: 3))
        XCTAssertTrue(tile("Bravo").exists, "Bravo stays a tile")
        XCTAssertFalse(completeButton("Bravo").exists, "and loses its circle")
    }

    // MARK: Row circle

    private var todoList: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "todoList").firstMatch
    }

    func testRowCircleTicksWithCheckmarkThenLeaves() throws {
        XCTAssertTrue(row("Bravo").waitForExistence(timeout: 5))

        let circle = todoList.buttons["Complete \u{201C}Bravo\u{201D}"]
        XCTAssertTrue(circle.waitForExistence(timeout: 3), "each row should lead with its circle")
        XCTAssertLessThan(circle.frame.midX, row("Bravo").frame.minX, "the circle sits before the row's title")
        circle.click()

        XCTAssertTrue(waitForRowTitles(["Alpha", "Charlie"]), "got \(rowTitles)")
        XCTAssertTrue(header(count: 2).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["All Notes"].exists, "clicking the circle must not open the note")
        XCTAssertTrue(tile("Bravo").exists, "the tile stays")
    }

    // MARK: Tiles and the multi-select bar

    func testTileCircleTicksAndTileStays() throws {
        XCTAssertTrue(row("Bravo").waitForExistence(timeout: 5))
        let bravoTile = tile("Bravo")
        let indexBefore = try XCTUnwrap(tileIndex("Bravo"))

        // The tile's circle shows without hovering.
        let circle = bravoTile.buttons["Complete \u{201C}Bravo\u{201D}"]
        XCTAssertTrue(circle.waitForExistence(timeout: 3), "the to-do tile should offer its circle")
        circle.click()

        XCTAssertTrue(waitForRowTitles(["Alpha", "Charlie"]), "got \(rowTitles)")
        XCTAssertTrue(header(count: 2).waitForExistence(timeout: 3))
        XCTAssertTrue(tile("Bravo").exists, "the tile stays in the grid")
        XCTAssertEqual(tileIndex("Bravo"), indexBefore, "the tile keeps its place")
        XCTAssertFalse(completeButton("Bravo").exists, "a ticked note has no circle")
        XCTAssertTrue(app.staticTexts["All Notes"].exists, "ticking must not open the note")
    }

    func testAddToToDoFromTileAppendsRow() throws {
        XCTAssertTrue(row("Alpha").waitForExistence(timeout: 5))
        let deltaTile = tile("Delta")
        XCTAssertTrue(deltaTile.waitForExistence(timeout: 3))

        deltaTile.hover()
        let add = deltaTile.buttons["Add to To-Do"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()

        XCTAssertTrue(waitForRowTitles(["Alpha", "Bravo", "Charlie", "Delta"]), "got \(rowTitles)")
        XCTAssertTrue(completeButton("Delta").waitForExistence(timeout: 3), "Delta's tile now has its circle")
    }

    func testMultiSelectAddsThenTicksBatch() throws {
        XCTAssertTrue(row("Alpha").waitForExistence(timeout: 5))

        let deltaTile = tile("Delta")
        deltaTile.hover()
        let select = deltaTile.buttons["Select note"]
        XCTAssertTrue(select.waitForExistence(timeout: 3))
        select.click()

        let add = button("Add selected notes to To-Do")
        XCTAssertTrue(add.waitForExistence(timeout: 3), "a mixed selection offers Add")
        add.click()
        XCTAssertTrue(waitForRowTitles(["Alpha", "Bravo", "Charlie", "Delta"]), "got \(rowTitles)")

        // Every tile offers its checkbox once anything is selected.
        tile("Alpha").hover()
        tile("Alpha").buttons["Select note"].click()
        for title in ["Bravo", "Charlie", "Delta"] {
            let checkbox = tile(title).buttons["Select note"]
            XCTAssertTrue(checkbox.waitForExistence(timeout: 3), "\(title) checkbox missing")
            checkbox.click()
        }

        let complete = button("Complete selected notes")
        XCTAssertTrue(complete.waitForExistence(timeout: 3), "an all-to-do selection offers Complete")
        complete.click()

        let todoList = app.descendants(matching: .any).matching(identifier: "todoList").firstMatch
        XCTAssertTrue(todoList.waitForNonExistence(timeout: 4), "every row should be ticked; got \(rowTitles)")
        for title in ["Alpha", "Bravo", "Charlie", "Delta"] {
            XCTAssertTrue(tile(title).exists, "\(title) stays in the grid")
        }
    }
}
