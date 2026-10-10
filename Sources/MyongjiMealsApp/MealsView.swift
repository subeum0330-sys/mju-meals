import SwiftUI
import MealCore

struct MealsView: View {
    @StateObject private var model = MealViewModel()
    @State private var showsSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                restaurantPicker
                WeekSelector(model: model)
                menuSection
                restaurantDetails
                sourceFooter
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(MealTheme.canvas)
        .foregroundStyle(MealTheme.ink)
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.resume() } }
        }
        .sheet(isPresented: $showsSettings) { SettingsView(model: model) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(MealTheme.pineFill, in: RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("명지밥")
                    .font(.largeTitle.weight(.bold))
                    .tracking(-1.5)
                Menu {
                    ForEach(Campus.allCases, id: \.self) { campus in
                        Button {
                            model.selectCampus(campus)
                        } label: {
                            if campus == model.campus {
                                Label(campus.displayName, systemImage: "checkmark")
                            } else {
                                Text(campus.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(model.campus.displayName) · \(model.campusCity)")
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MealTheme.secondary)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("캠퍼스 선택, 현재 \(model.campus.displayName)")
            }
            Spacer(minLength: 8)
            Button { showsSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(MealTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(MealTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정")
        }
    }

    private var restaurantPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("어디서 먹을까요?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MealTheme.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.cafeterias) { cafeteria in
                        let selected = model.cafeteria.id == cafeteria.id
                        Button {
                            model.selectCafeteria(cafeteria)
                        } label: {
                            HStack(spacing: 6) {
                                if selected {
                                    Image(systemName: "checkmark").font(.caption.weight(.bold))
                                }
                                Text(cafeteria.name).font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(selected ? Color.white : MealTheme.secondary)
                            .padding(.horizontal, 17)
                            .frame(minHeight: 46)
                            .background(selected ? MealTheme.pineFill : MealTheme.surface, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(selected ? Color.clear : MealTheme.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
            }
            .contentMargins(.trailing, 1)
        }
    }

    private var menuSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(model.formattedDate(model.selectedDate, pattern: "yyyy년 M월 d일 EEEE"))
                    .font(.subheadline)
                    .foregroundStyle(MealTheme.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(model.isToday ? "오늘의 식단" : "이날의 식단")
                        .font(.title2.weight(.bold))
                        .tracking(-0.7)
                    Spacer()
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("식단 불러오는 중")
                    } else if model.week != nil {
                        Label(model.sourceLabel, systemImage: model.week?.snapshotSource == nil ? "building.2" : "checkmark.seal")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MealTheme.pine)
                    }
                }
            }

            if model.isPastDate {
                Label("지난 날짜의 식단이에요", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MealTheme.warning)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MealTheme.warningFill, in: RoundedRectangle(cornerRadius: 16))
            }

            if let source = model.week?.snapshotSource {
                snapshotNotice(source)
            }

            if model.isShowingSavedResult {
                savedResultNotice
            }

            if model.week == nil && model.isLoading {
                LoadingMealCard()
            } else if model.week == nil, let message = model.errorMessage {
                StatusCard(
                    symbol: "wifi.exclamationmark",
                    title: "식단에 연결하지 못했어요",
                    message: message,
                    retry: { Task { await model.refresh() } }
                )
            } else if !model.hasPublishedEntries {
                StatusCard(
                    symbol: "tray",
                    title: model.week?.snapshotSource == nil ? "학교 홈페이지에 등록된 식단이 없어요" : "확인본에 이 날짜의 식단이 없어요",
                    message: "선택한 날짜의 메뉴와 운영 여부는\n식당의 최신 안내를 확인해 주세요."
                )
            } else {
                ForEach(model.entries) { entry in
                    MealEntryCard(entry: entry, sourceLabel: model.sourceLabel)
                }
            }

            if model.needsSourceFollowUp, let url = model.cafeteria.instagramURL {
                instagramAccountLink(url)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.isLoading)
    }

    private func snapshotNotice(_ source: MealSnapshotSource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(source.scope)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MealTheme.pine)
            Text(source.isAutomatic
                 ? "식당 게시물에서 자동으로 읽어온 식단이에요. 이미지의 글자를 잘못 읽을 수 있으니 중요한 내용은 원문을 확인해 주세요."
                 : "식당 게시물을 직접 확인해 저장한 식단이에요. 이 확인본 이후의 변경 사항은 원문을 확인해 주세요.")
                .font(.caption)
                .foregroundStyle(MealTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
            Text("\(source.isAutomatic ? "수집" : "확인") · \(model.formattedDate(source.sourceUpdatedAt, pattern: "yyyy. M. d HH:mm")) · @\(source.username)")
                .font(.caption2)
                .foregroundStyle(MealTheme.secondary)
            Link(destination: source.postURL) {
                Label("식당 게시물 원문 보기", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MealTheme.softGreen, in: RoundedRectangle(cornerRadius: 20))
    }

    private func instagramAccountLink(_ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: "camera").font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("식당 인스타그램에서 확인하기")
                        .font(.subheadline.weight(.semibold))
                    if let username = model.cafeteria.instagramUsername {
                        Text("@\(username)").font(.caption)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
            }
            .foregroundStyle(MealTheme.pine)
            .frame(minHeight: 44)
            .padding(16)
            .background(MealTheme.softGreen, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var savedResultNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("최신 식단을 불러오지 못했어요", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
            Text("같은 식당·같은 주의 저장된 자료를 표시하고 있어요. 변경 사항은 식단 원문을 확인해 주세요.")
                .font(.caption)
            Button("다시 불러오기") { Task { await model.refresh() } }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .disabled(model.isLoading)
        }
        .foregroundStyle(MealTheme.warning)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MealTheme.warningFill, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var restaurantDetails: some View {
        if let week = model.week, week.location != nil || week.operatingHours != nil {
            VStack(alignment: .leading, spacing: 14) {
                Text("식당 안내").font(.headline)
                if let location = week.location, !location.isEmpty {
                    Label {
                        Text(location).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                }
                if let hours = week.operatingHours, !hours.isEmpty {
                    Label {
                        Text(hours).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "clock")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(MealTheme.secondary)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mealCard()
        }
    }

    private var sourceFooter: some View {
        VStack(spacing: 11) {
            if !model.needsSourceFollowUp,
               let instagramURL = model.cafeteria.instagramURL,
               let username = model.cafeteria.instagramUsername {
                Link(destination: instagramURL) {
                    Label("식당 인스타그램 @\(username)", systemImage: "camera")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MealTheme.pine)
                        .frame(minHeight: 44)
                }
            }
            Link(destination: model.cafeteria.sourceURL) {
                HStack(spacing: 7) {
                    Text("학교 홈페이지 식단표")
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MealTheme.pine)
                .frame(minHeight: 44)
            }
            if model.week?.snapshotSource == nil, let fetchedAt = model.week?.fetchedAt {
                Text("홈페이지 확인 · \(model.formattedDate(fetchedAt, pattern: "yyyy. M. d HH:mm"))")
                    .font(.caption)
            }
            Text("학교 사정에 따라 메뉴와 운영 시간이 달라질 수 있어요.")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(MealTheme.secondary)
        .frame(maxWidth: .infinity)
    }
}
