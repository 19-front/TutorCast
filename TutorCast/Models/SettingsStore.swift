import Foundation
import SwiftUI
import Combine
import CryptoKit
import CommonCrypto

// MARK: - Secure Storage Utilities

/// Encrypts data using CryptoKit (AES-256-GCM)
private func encryptData(_ data: Data) -> Data? {
    guard let key = loadOrCreateEncryptionKey() else { return nil }
    
    do {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined
    } catch {
        print("[Security] Encryption failed: \(error)")
        return nil
    }
}

/// Decrypts data using CryptoKit (AES-256-GCM)
private func decryptData(_ encryptedData: Data) -> Data? {
    guard let key = loadOrCreateEncryptionKey() else { return nil }
    
    do {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    } catch {
        print("[Security] Decryption failed: \(error)")
        return nil
    }
}

/// Loads or creates a persistent encryption key in Keychain
private func loadOrCreateEncryptionKey() -> SymmetricKey? {
    let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.tutorcast.profilekey",
        kSecAttrAccount as String: "main",
        kSecReturnData as String: true
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(keychainQuery as CFDictionary, &result)
    
    if status == errSecSuccess, let keyData = result as? Data {
        return SymmetricKey(data: keyData)
    } else if status == errSecItemNotFound {
        // Create new key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.tutorcast.profilekey",
            kSecAttrAccount as String: "main",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return key
        }
    }
    
    return nil
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    
    let objectWillChange = PassthroughSubject<Void, Never>()
    
    @AppStorage("settings.opacity") var overlayOpacity: Double = 0.85
    @AppStorage("settings.fontSize") var fontSize: Double = 16
    @AppStorage("settings.theme") var themeRaw: String = Theme.minimal.rawValue
    @AppStorage("settings.activeProfileID") var activeProfileID: String = ""
    @AppStorage("settings.lastProfileVersion") var lastProfileVersion: String = "0"
    
    // MARK: - AutoCAD Direct Command Settings
    @AppStorage("autocad.directCommands.enabled") var directCommandsEnabled: Bool = true
    @AppStorage("autocad.showSubcommand") var showSubcommand: Bool = true
    @AppStorage("autocad.fallbackToKeyboard") var fallbackToKeyboard: Bool = true
    @AppStorage("autocad.environment.override") var environmentOverride: String = ""
    @AppStorage("autocad.parallels.manualIP") var parallelsManualIP: String = ""
    @AppStorage("autocad.tcpPort") var tcpPort: Int = 19848

    enum Theme: String, CaseIterable, Identifiable, Codable {
        case minimal
        case neon
        case autoCAD
        
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .minimal: return "Minimal"
            case .neon: return "Neon"
            case .autoCAD: return "AutoCAD"
            }
        }
        
        // Theme color palette
        var backgroundColor: NSColor {
            switch self {
            case .minimal:
                return NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            case .neon:
                return NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
            case .autoCAD:
                return NSColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 1.0)
            }
        }
        
        var textColor: NSColor {
            switch self {
            case .minimal:
                return NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
            case .neon:
                return NSColor(red: 0.0, green: 1.0, blue: 0.8, alpha: 1.0)
            case .autoCAD:
                return NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
            }
        }
        
        var accentColor: NSColor {
            switch self {
            case .minimal:
                return NSColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1.0)
            case .neon:
                return NSColor(red: 1.0, green: 0.0, blue: 0.75, alpha: 1.0)
            case .autoCAD:
                return NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
            }
        }
        
        var fontName: String {
            switch self {
            case .minimal:
                return "SF Mono"
            case .neon:
                return "SF Mono"
            case .autoCAD:
                return "Courier New"
            }
        }
        
        var fontSize: Double {
            switch self {
            case .minimal: return 16
            case .neon: return 18
            case .autoCAD: return 14
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .minimal: return 8
            case .neon: return 12
            case .autoCAD: return 6
            }
        }
    }

    @Published var profiles: [Profile] = []
    @Published var currentProfile: Profile? = nil

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        let appSupport = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = appSupport?.appendingPathComponent("TutorCast", isDirectory: true)
        if let folder, !(fileManager.fileExists(atPath: folder.path)) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        }
        self.fileURL = (folder ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("profiles.json")
        
        // Secure file permissions
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: self.fileURL.path)
        
        load()
    }

    var theme: Theme {
        get { Theme(rawValue: themeRaw) ?? .minimal }
        set { themeRaw = newValue.rawValue }
    }

    // MARK: - Profile Loading & Persistence

    func load() {
        var loadedProfiles: [Profile] = []
        
        if let data = try? Data(contentsOf: fileURL), 
           let decryptedData = decryptData(data),
           let decoded = try? JSONDecoder().decode([Profile].self, from: decryptedData) {
            loadedProfiles = decoded
        } else {
            // First launch: seed with built-in profiles
            loadedProfiles = [
                BuiltInProfiles.autoCAD(),
                BuiltInProfiles.photoshop(),
                BuiltInProfiles.default()
            ]
            save()
        }
        
        // Ensure all built-in profiles are always up-to-date
        updateBuiltInProfiles(&loadedProfiles)
        
        profiles = loadedProfiles
        
        // Set active profile if not set
        if activeProfileID.isEmpty {
            activeProfileID = profiles.first?.id.uuidString ?? ""
        }
        
        // Load the current profile
        if let uuid = UUID(uuidString: activeProfileID) {
            currentProfile = profiles.first(where: { $0.id == uuid })
        }
        if currentProfile == nil {
            currentProfile = profiles.first
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(profiles),
           let encryptedData = encryptData(data) {
            try? encryptedData.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Built-in Profile Maintenance

    private func updateBuiltInProfiles(_ profiles: inout [Profile]) {
        let builtIns = [
            BuiltInProfiles.autoCAD(),
            BuiltInProfiles.photoshop(),
            BuiltInProfiles.default()
        ]
        
        for builtIn in builtIns {
            if let idx = profiles.firstIndex(where: { $0.name == builtIn.name && !$0.isCustom }) {
                profiles[idx].mappings = builtIn.mappings
            }
        }
    }

    // MARK: - Profile Management

    func addProfile(named name: String = "New Profile") {
        let uniqueName = uniqueProfileName(basedOn: name)
        let newProfile = Profile(name: uniqueName, mappings: [], isCustom: true)
        profiles.append(newProfile)
        save()
    }

    func deleteProfile(at index: Int) {
        guard index >= 0 && index < profiles.count else { return }
        guard profiles[index].isCustom else { return } // Prevent deletion of built-in profiles
        
        let deletedProfile = profiles.remove(at: index)
        
        // If we deleted the active profile, switch to first available
        if currentProfile?.id == deletedProfile.id {
            currentProfile = profiles.first
            if let newCurrent = currentProfile {
                activeProfileID = newCurrent.id.uuidString
            }
        }
        save()
    }

    func duplicateProfile(_ profile: Profile) {
        let copy = Profile(
            name: uniqueProfileName(basedOn: profile.name + " copy"),
            mappings: profile.mappings,
            isCustom: true
        )
        profiles.append(copy)
        save()
    }

    func renameProfile(_ profile: Profile, to newName: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let sanitizedName = uniqueProfileName(basedOn: newName)
        
        var updated = profiles[idx]
        updated.name = sanitizedName
        profiles[idx] = updated
        
        if currentProfile?.id == profile.id {
            currentProfile = updated
        }
        save()
    }

    func updateMappings(for profile: Profile, mappings: [ActionMapping]) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        
        var updated = profiles[idx]
        updated.mappings = mappings
        profiles[idx] = updated
        
        if currentProfile?.id == profile.id {
            currentProfile = updated
        }
        save()
    }

    func setActiveProfile(_ profile: Profile) {
        activeProfileID = profile.id.uuidString
        currentProfile = profile
        objectWillChange.send()
    }

    func activeProfile() -> Profile? {
        guard let uuid = UUID(uuidString: activeProfileID) else { return profiles.first }
        return profiles.first(where: { $0.id == uuid }) ?? profiles.first
    }

    // MARK: - Utilities

    private func uniqueProfileName(basedOn base: String) -> String {
        var candidate = base.trimmingCharacters(in: .whitespaces)
        if candidate.isEmpty {
            candidate = "New Profile"
        }
        
        var i = 2
        let originalCandidate = candidate
        while profiles.contains(where: { $0.name == candidate }) {
            candidate = "\(originalCandidate) \(i)"
            i += 1
        }
        return candidate
    }
}
