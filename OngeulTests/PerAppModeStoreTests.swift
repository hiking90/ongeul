import XCTest

class PerAppModeStoreTests: XCTestCase {

    func testInitiallyNil() {
        let store = PerAppModeStore()
        XCTAssertNil(store.savedMode(for: "com.test.app"))
    }

    func testSaveAndRetrieveMode() {
        let store = PerAppModeStore()
        store.saveMode(.korean, for: "com.test.app")
        XCTAssertEqual(store.savedMode(for: "com.test.app"), .korean)

        store.saveMode(.english, for: "com.test.app")
        XCTAssertEqual(store.savedMode(for: "com.test.app"), .english)
    }

    func testDifferentAppsIndependent() {
        let store = PerAppModeStore()
        store.saveMode(.korean, for: "com.app1")
        store.saveMode(.english, for: "com.app2")

        XCTAssertEqual(store.savedMode(for: "com.app1"), .korean)
        XCTAssertEqual(store.savedMode(for: "com.app2"), .english)
    }
}

class EnglishLockStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var store: EnglishLockStore!

    override func setUp() {
        let suiteName = "com.test.EnglishLockTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = EnglishLockStore(defaults: defaults)
    }

    override func tearDown() {
        if let suiteName = defaults.volatileDomainNames.first {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        store = nil
    }

    func testInitiallyNotLocked() {
        XCTAssertFalse(store.isLocked("com.test.app"))
    }

    func testAddAndCheckLock() {
        store.addLock(for: "com.test.app", previousMode: .korean)
        XCTAssertTrue(store.isLocked("com.test.app"))
    }

    func testRemoveLockRestoresPreviousMode() {
        store.addLock(for: "com.test.app", previousMode: .korean)
        let restored = store.removeLock(for: "com.test.app")
        XCTAssertEqual(restored, .korean)
        XCTAssertFalse(store.isLocked("com.test.app"))
    }

    func testRemoveLockWhenNotLocked_returnsNil() {
        XCTAssertNil(store.removeLock(for: "com.test.app"))
    }

    func testAddLockWithEnglishMode() {
        store.addLock(for: "com.test.app", previousMode: .english)
        let restored = store.removeLock(for: "com.test.app")
        XCTAssertEqual(restored, .english)
    }

    func testMultipleAppsIndependent() {
        store.addLock(for: "com.app1", previousMode: .korean)
        store.addLock(for: "com.app2", previousMode: .english)

        XCTAssertTrue(store.isLocked("com.app1"))
        XCTAssertTrue(store.isLocked("com.app2"))

        let r1 = store.removeLock(for: "com.app1")
        XCTAssertEqual(r1, .korean)
        XCTAssertFalse(store.isLocked("com.app1"))
        XCTAssertTrue(store.isLocked("com.app2"))
    }
}
