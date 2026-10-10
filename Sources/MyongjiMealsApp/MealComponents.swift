import SwiftUI
import MealCore

struct WeekSelector: View {
    @ObservedObject var model: MealViewModel
    @ScaledMetric(relativeTo: .caption) private var dateHeight = 66
    @ScaledMetric(relativeTo: .body) private var minimumDateWidth = 44

    var body: some View {
        VStack(spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    weekHeading.fixedSize()
                    Spacer(minLength: 0)
                    navigationControls.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    weekHeading
                    HStack {
                        Spacer(minLength: 0)
                        navigationControls
                    }
                }
            }

            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(model.dates, id: \.self) { date in
                                let selected = SchoolCalendar.calendar.isDate(date, inSameDayAs: model.selectedDate)
                                let today = SchoolCalendar.calendar.isDate(date, inSameDayAs: Date())
                                Button { model.selectDate(date) } label: {
                                    VStack(spacing: 7) {
                                        Text(model.formattedDate(date, pattern: "EEEEE"))
                                            .font(.caption)
                                            .foregroundStyle(selected ? Color.white.opacity(0.8) : MealTheme.secondary)
                                        Text(model.formattedDate(date, pattern: "d"))
                                            .font(.body.weight(selected ? .bold : .medium))
                                            .foregroundStyle(selected ? Color.white : MealTheme.ink)
                                            .monospacedDigit()
                                        Circle()
                                            .fill(selected ? Color.white : MealTheme.pine)
                                            .frame(width: 4, height: 4)
                                            .opacity(today ? 1 : 0)
                                    }
                                    .frame(width: max(minimumDateWidth, (geometry.size.width - 12) / 7))
                                    .frame(minHeight: dateHeight)
                                    .background(selected ? MealTheme.pineFill : .clear, in: RoundedRectangle(cornerRadius: 16))
                                    .contentShape(Rectangle())
                                }
                                .id(SchoolCalendar.dayKey(date))
                                .buttonStyle(.plain)
                                .accessibilityLabel(model.formattedDate(date, pattern: "yyyy년 M월 d일 EEEE") + (today ? ", 오늘" : ""))
                                .accessibilityAddTraits(selected ? [.isSelected] : [])
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(SchoolCalendar.dayKey(model.selectedDate), anchor: .center) }
                    .onChange(of: SchoolCalendar.dayKey(model.selectedDate)) { _, newDay in
                        proxy.scrollTo(newDay, anchor: .center)
                    }
                }
            }
            .frame(height: dateHeight)
        }
        .padding(16)
        .mealCard()
    }

    private var weekTitle: String {
        guard let first = model.dates.first, let last = model.dates.last else { return "주간 식단" }
        let isSameYear = SchoolCalendar.calendar.component(.year, from: first) == SchoolCalendar.calendar.component(.year, from: last)
        return model.formattedDate(first, pattern: "yyyy. M. d") + " – " + model.formattedDate(last, pattern: isSameYear ? "M. d" : "yyyy. M. d")
    }

    private var weekHeading: some View {
        Text(weekTitle)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
    }

    private var navigationControls: some View {
        HStack(spacing: 4) {
            Button("오늘") { model.goToToday() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(MealTheme.pine)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .background(MealTheme.softGreen, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityLabel("오늘 날짜로 이동")
            navigationButton(symbol: "chevron.left", label: "이전 주", offset: -1)
            navigationButton(symbol: "chevron.right", label: "다음 주", offset: 1)
        }
    }

    private func navigationButton(symbol: String, label: String, offset: Int) -> some View {
        Button { model.moveWeek(by: offset) } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(MealTheme.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct MealEntryCard: View {
    let entry: MealEntry
    var sourceLabel = "학교 홈페이지"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: categorySymbol)
                    .font(.title3)
                    .foregroundStyle(MealTheme.pine)
                    .frame(width: 42, height: 42)
                    .background(MealTheme.softGreen, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MealTheme.pine)
                    if let title = entry.title, !title.isEmpty {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(MealTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if entry.isPublished {
                if !entry.items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                    .foregroundStyle(MealTheme.pine.opacity(0.55))
                                    .accessibilityHidden(true)
                                Text(item)
                                    .font(.body)
                                    .foregroundStyle(MealTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else if entry.title == nil && entry.note == nil {
                    Text("상세 메뉴는 식단 원문을 확인해 주세요.")
                        .font(.subheadline)
                        .foregroundStyle(MealTheme.secondary)
                }
            } else {
                Text(sourceLabel == "학교 홈페이지" ? "학교 홈페이지에 등록된 식단이 없어요." : "확인본에 이 식단이 없어요.")
                    .font(.subheadline)
                    .foregroundStyle(MealTheme.secondary)
            }

            if entry.isPublished, let note = entry.note, !note.isEmpty {
                Divider().overlay(MealTheme.border)
                Label {
                    Text(note).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundStyle(MealTheme.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mealCard()
    }

    private var categorySymbol: String {
        if entry.category.contains("조식") || entry.category.contains("아침") { return "sunrise" }
        if entry.category.contains("석식") || entry.category.contains("저녁") { return "moon.stars" }
        if entry.category.contains("중식") || entry.category.contains("점심") { return "sun.max" }
        return "fork.knife"
    }
}

struct StatusCard: View {
    let symbol: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(MealTheme.pine)
                .frame(width: 70, height: 70)
                .background(MealTheme.softGreen, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(MealTheme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
            if let retry {
                Button(action: retry) {
                    Label("다시 시도", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 46)
                        .background(MealTheme.pineFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .mealCard()
    }
}

struct LoadingMealCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14).frame(width: 42, height: 42)
                RoundedRectangle(cornerRadius: 6).frame(width: 80, height: 18)
            }
            ForEach([0.78, 0.58, 0.66, 0.46], id: \.self) { width in
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 6)
                        .frame(width: geometry.size.width * width, height: 15)
                }
                .frame(height: 15)
            }
            Text("식단 정보를 확인하고 있어요")
                .font(.caption)
                .foregroundStyle(MealTheme.secondary)
        }
        .foregroundStyle(MealTheme.softGreen)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mealCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("식단 정보를 불러오고 있어요")
    }
}
