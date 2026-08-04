import Foundation

/// Frozen copy for the monthly budget widget, resolved by the host app before publication.
struct MonthlyBudgetCopy: Sendable, Equatable {
    let title: String
    let settingsTitle: String
    let forecastTitle: String
    let unconfiguredMessage: String
    let forecastOverBudgetMessage: String

    /// Returns the copy stored in a newly published monthly budget snapshot and its host setting.
    /// - Parameter language: The app language selected when the snapshot is generated.
    /// - Returns: Fully localized budget copy for the selected supported app language.
    static func make(language: AppLanguage) -> MonthlyBudgetCopy {
        MonthlyBudgetCopy(
            title: AppStrings.text(.widgetMonthlyBudgetTitle, language: language),
            settingsTitle: AppStrings.text(
                .widgetMonthlyBudgetSettingsTitle,
                language: language
            ),
            forecastTitle: AppStrings.text(
                .widgetMonthlyBudgetForecastTitle,
                language: language
            ),
            unconfiguredMessage: AppStrings.text(
                .widgetMonthlyBudgetUnconfiguredMessage,
                language: language
            ),
            forecastOverBudgetMessage: AppStrings.text(
                .widgetMonthlyBudgetForecastOverBudgetMessage,
                language: language
            )
        )
    }
}
