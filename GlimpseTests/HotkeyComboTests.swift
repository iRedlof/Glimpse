import Carbon
import Testing
@testable import Glimpse

struct HotkeyComboTests {
    @Test(arguments: [-1, Int.max, 128])
    func invalidSavedKeyUsesDefault(value: Int) {
        let domain = "GlimpseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(value, forKey: "hotkeyKeyCode")
        defaults.set(Int(cmdKey), forKey: "hotkeyModifiers")
        #expect(HotkeyCombo.load(defaults: defaults) == .default)
    }

    @Test(arguments: [-1, Int.max, 0, 1])
    func invalidSavedModifiersUseDefault(value: Int) {
        let domain = "GlimpseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(8, forKey: "hotkeyKeyCode")
        defaults.set(value, forKey: "hotkeyModifiers")
        #expect(HotkeyCombo.load(defaults: defaults) == .default)
    }

    @Test
    func validSavedHotkeyIsPreserved() {
        let domain = "GlimpseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(0, forKey: "hotkeyKeyCode")
        defaults.set(Int(cmdKey | optionKey), forKey: "hotkeyModifiers")
        #expect(HotkeyCombo.load(defaults: defaults) ==
                HotkeyCombo(keyCode: 0, modifiers: UInt32(cmdKey | optionKey)))
    }

    @Test
    func displayString_cmdShiftC() {
        let combo = HotkeyCombo(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey))
        #expect(combo.displayString == "⇧⌘C")
    }

    @Test
    func displayString_cmdOnly() {
        let combo = HotkeyCombo(keyCode: 0, modifiers: UInt32(cmdKey))
        #expect(combo.displayString == "⌘A")
    }

    @Test
    func displayString_allModifiers() {
        let combo = HotkeyCombo(keyCode: 49, modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        #expect(combo.displayString == "⌃⌥⇧⌘Space")
    }

    @Test
    func displayString_unknownKeyCode() {
        let combo = HotkeyCombo(keyCode: 999, modifiers: UInt32(cmdKey))
        #expect(combo.displayString == "⌘Key999")
    }

    @Test
    func equatable_sameCombo() {
        let a = HotkeyCombo(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey))
        let b = HotkeyCombo(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey))
        #expect(a == b)
    }

    @Test
    func equatable_differentCombo() {
        let a = HotkeyCombo(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey))
        let b = HotkeyCombo(keyCode: 8, modifiers: UInt32(cmdKey))
        #expect(a != b)
    }
}
