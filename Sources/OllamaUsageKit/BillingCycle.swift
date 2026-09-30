import Foundation

/// 청구 주기 — CONTEXT.md의 **갱신 예정일**.
///
/// Ollama Cloud의 포함 크레딧은 "구독을 시작한 날과 같은 날"에 매월 리셋된다.
/// 그 달에 그 날이 없으면 **그 달 마지막 날**이 기준이다 (예: 31일 구독 → 9월은 30일).
/// 기준일은 유지된다 — 9월 30일에 리셋됐어도 다음 회차는 10월 31일이다.
///
/// 구독 시작일은 API가 알려 주지 않으므로 설정 파일(`billing_day_of_month`)에서 온다.
/// API의 `period.ending_at`은 롤링 윈도우의 끝(= 관측 시각)이라 갱신일로 쓸 수 없다 (ADR-0007).
public enum BillingCycle {

    /// 다음 갱신 예정일을 `YYYY-MM-DD`로 돌려준다. 기준일이 1...31 밖이면 nil.
    ///
    /// - Parameters:
    ///   - anchorDay: 구독을 시작한 날(1...31)
    ///   - today: 계산 기준 시각 (테스트에서 주입)
    ///   - calendar: 날짜 계산에 쓸 달력 (기본: 사용자 로컬)
    public static func nextResetDate(
        anchorDay: Int,
        today: Date,
        calendar: Calendar = .current
    ) -> String? {
        guard (1...31).contains(anchorDay) else { return nil }

        let components = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = components.year,
              let month = components.month,
              let todayDay = components.day
        else { return nil }

        // 이번 달 기준일이 아직 오지 않았으면 이번 달, 왔거나 지났으면 다음 달.
        // (기준일 당일은 그 회차가 시작된 날이므로 다음 회차는 다음 달이다.)
        let thisMonthDay = clampedDay(anchorDay, year: year, month: month, calendar: calendar)
        let (targetYear, targetMonth) = todayDay < thisMonthDay
            ? (year, month)
            : nextMonth(year: year, month: month)
        let targetDay = clampedDay(anchorDay, year: targetYear, month: targetMonth, calendar: calendar)

        return String(format: "%04d-%02d-%02d", targetYear, targetMonth, targetDay)
    }

    /// 그 달에 기준일이 없으면 말일로 보정한다 (기준일 자체는 바뀌지 않는다).
    private static func clampedDay(_ anchorDay: Int, year: Int, month: Int, calendar: Calendar) -> Int {
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count
        else { return anchorDay }
        return min(anchorDay, days)
    }

    private static func nextMonth(year: Int, month: Int) -> (year: Int, month: Int) {
        month == 12 ? (year + 1, 1) : (year, month + 1)
    }
}