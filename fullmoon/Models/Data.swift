//
//  Data.swift
//  Navi
//
//  Based on fullmoon by Jordan Singer.
//  Modified for Navi - offline AI chat assistant.
//

import SwiftUI
import SwiftData

class AppManager: ObservableObject {
    @AppStorage("systemPrompt") var systemPrompt = "you are a helpful assistant"
    @AppStorage("appTintColor") var appTintColor: AppTintColor = .monochrome
    @AppStorage("appFontDesign") var appFontDesign: AppFontDesign = .standard
    @AppStorage("appFontSize") var appFontSize: AppFontSize = .medium
    @AppStorage("appFontWidth") var appFontWidth: AppFontWidth = .standard
    @AppStorage("currentModelName") var currentModelName: String? = "gemma-4-e2b-it"
    @AppStorage("shouldPlayHaptics") var shouldPlayHaptics = true
    @AppStorage("numberOfVisits") var numberOfVisits = 0
    @AppStorage("numberOfVisitsOfLastRequest") var numberOfVisitsOfLastRequest = 0
    
    var userInterfaceIdiom: LayoutType {
        #if os(visionOS)
        return .vision
        #elseif os(macOS)
        return .mac
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
        #else
        return .unknown
        #endif
    }
    
    var availableMemory: Double {
        let ramInBytes = ProcessInfo.processInfo.physicalMemory
        let ramInGB = Double(ramInBytes) / (1024 * 1024 * 1024)
        return ramInGB
    }

    enum LayoutType {
        case mac, phone, pad, vision, unknown
    }
        
    private let installedModelsKey = "installedModels"
        
    @Published var installedModels: [String] = [] {
        didSet {
            saveInstalledModelsToUserDefaults()
        }
    }
    
    init() {
        loadInstalledModelsFromUserDefaults()
    }
    
    func incrementNumberOfVisits() {
        numberOfVisits += 1
        print("app visits: \(numberOfVisits)")
    }
    
    private func saveInstalledModelsToUserDefaults() {
        if let jsonData = try? JSONEncoder().encode(installedModels) {
            UserDefaults.standard.set(jsonData, forKey: installedModelsKey)
        }
    }
    
    private func loadInstalledModelsFromUserDefaults() {
        if let jsonData = UserDefaults.standard.data(forKey: installedModelsKey),
           let decodedArray = try? JSONDecoder().decode([String].self, from: jsonData) {
            self.installedModels = decodedArray
        } else {
            self.installedModels = []
        }
    }
    
    func playHaptic() {
        if shouldPlayHaptics {
            #if os(iOS)
            let impact = UIImpactFeedbackGenerator(style: .soft)
            impact.impactOccurred()
            #endif
        }
    }
    
    func addInstalledModel(_ model: String) {
        if !installedModels.contains(model) {
            installedModels.append(model)
        }
    }
    
    func modelDisplayName(_ modelName: String) -> String {
        if let naviModel = NaviModelRegistry.models.first(where: { $0.id == modelName }) {
            return naviModel.displayName
        }
        return modelName.lowercased()
    }
    
    func getMoonPhaseIcon() -> String {
        let currentDate = Date()
        let baseDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 6))!
        let daysSinceBaseDate = Calendar.current.dateComponents([.day], from: baseDate, to: currentDate).day!
        let moonCycleLength = 29.53
        let daysIntoCycle = Double(daysSinceBaseDate).truncatingRemainder(dividingBy: moonCycleLength)
        
        switch daysIntoCycle {
        case 0..<1.8457:
            return "moonphase.new.moon"
        case 1.8457..<5.536:
            return "moonphase.waxing.crescent"
        case 5.536..<9.228:
            return "moonphase.first.quarter"
        case 9.228..<12.919:
            return "moonphase.waxing.gibbous"
        case 12.919..<16.610:
            return "moonphase.full.moon"
        case 16.610..<20.302:
            return "moonphase.waning.gibbous"
        case 20.302..<23.993:
            return "moonphase.last.quarter"
        case 23.993..<27.684:
            return "moonphase.waning.crescent"
        default:
            return "moonphase.new.moon"
        }
    }
}

enum Role: String, Codable {
    case assistant
    case user
    case system
}

@Model
class Message {
    @Attribute(.unique) var id: UUID
    var role: Role
    var content: String
    var timestamp: Date
    var generatingTime: TimeInterval?
    
    // Navi additions: image support and completion tracking
    var imageData: Data?
    var isComplete: Bool = true
    
    @Relationship(inverse: \Thread.messages) var thread: Thread?
    
    init(role: Role, content: String, thread: Thread? = nil, generatingTime: TimeInterval? = nil, imageData: Data? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.thread = thread
        self.generatingTime = generatingTime
        self.imageData = imageData
    }
}

@Model
final class Thread: Sendable {
    @Attribute(.unique) var id: UUID
    var title: String?
    var timestamp: Date
    
    // Navi addition: track which model this thread uses
    var modelId: String?
    
    @Relationship var messages: [Message] = []
    
    var sortedMessages: [Message] {
        return messages.sorted { $0.timestamp < $1.timestamp }
    }
    
    init() {
        self.id = UUID()
        self.timestamp = Date()
    }
}

enum AppTintColor: String, CaseIterable {
    case monochrome, blue, brown, gray, green, indigo, mint, orange, pink, purple, red, teal, yellow
    
    func getColor() -> Color {
        switch self {
        case .monochrome: .primary
        case .blue: .blue
        case .red: .red
        case .green: .green
        case .yellow: .yellow
        case .brown: .brown
        case .gray: .gray
        case .indigo: .indigo
        case .mint: .mint
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .teal: .teal
        }
    }
}

enum AppFontDesign: String, CaseIterable {
    case standard, monospaced, rounded, serif
    
    func getFontDesign() -> Font.Design {
        switch self {
        case .standard: .default
        case .monospaced: .monospaced
        case .rounded: .rounded
        case .serif: .serif
        }
    }
}

enum AppFontWidth: String, CaseIterable {
    case compressed, condensed, expanded, standard
    
    func getFontWidth() -> Font.Width {
        switch self {
        case .compressed: .compressed
        case .condensed: .condensed
        case .expanded: .expanded
        case .standard: .standard
        }
    }
}

enum AppFontSize: String, CaseIterable {
    case xsmall, small, medium, large, xlarge
    
    func getFontSize() -> DynamicTypeSize {
        switch self {
        case .xsmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xlarge: .xLarge
        }
    }
}
