import Foundation

/// Single source of truth for the unified-logging subsystem, so every category
/// in the app shows up under one filter in Console.
enum DictoraLog {
    static let subsystem = "com.dictora.app"
}
