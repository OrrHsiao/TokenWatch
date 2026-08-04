import Foundation

/// Frozen copy for the monthly budget widget that avoids consulting the extension bundle.
///
/// The host app's current localization migration is intentionally left untouched here. Simplified
/// and traditional Chinese app languages receive matching Chinese copy; other languages use the
/// established English fallback.
struct MonthlyBudgetCopy: Sendable, Equatable {
    let title: String
    let settingsTitle: String
    let forecastTitle: String
    let unconfiguredMessage: String
    let forecastOverBudgetMessage: String

    /// Returns the copy stored in a newly published monthly budget snapshot.
    /// - Parameter language: The app language selected when the snapshot is generated.
    /// - Returns: Matching Chinese copy or the English fallback for the feature.
    static func make(language: AppLanguage) -> MonthlyBudgetCopy {
        switch language {
        case .zhHK, .zhHant:
            return MonthlyBudgetCopy(
                title: "本月預算",
                settingsTitle: "每月預算（USD）",
                forecastTitle: "月底預估",
                unconfiguredMessage: "在 TokenWatch 中設定每月預算",
                forecastOverBudgetMessage: "預計超出預算"
            )
        case .zhHans:
            return MonthlyBudgetCopy(
                title: "本月预算",
                settingsTitle: "每月预算（USD）",
                forecastTitle: "月底预估",
                unconfiguredMessage: "在 TokenWatch 中设置月度预算",
                forecastOverBudgetMessage: "预计超出预算"
            )
        default:
            return MonthlyBudgetCopy(
                title: "Monthly Budget",
                settingsTitle: "Monthly budget (USD)",
                forecastTitle: "Month-end forecast",
                unconfiguredMessage: "Set a monthly budget in TokenWatch",
                forecastOverBudgetMessage: "Projected to exceed budget"
            )
        }
    }
}
