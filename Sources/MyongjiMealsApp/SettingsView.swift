import SwiftUI
import MealCore

struct SettingsView: View {
    @ObservedObject var model: MealViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("캠퍼스", selection: Binding(get: { model.campus }, set: model.selectCampus)) {
                        ForEach(Campus.allCases, id: \.self) { campus in
                            Text(campus.displayName).tag(campus)
                        }
                    }
                    Picker("식당", selection: Binding(get: { model.cafeteria }, set: model.selectCafeteria)) {
                        ForEach(model.cafeterias) { cafeteria in
                            Text(cafeteria.name).tag(cafeteria)
                        }
                    }
                } header: {
                    Text("내 캠퍼스")
                } footer: {
                    Text("마지막으로 선택한 캠퍼스와 식당을 이 기기에 기억해요.")
                }

                Section {
                    if let source = model.week?.snapshotSource {
                        LabeledContent("현재 식단 출처", value: model.sourceLabel)
                        LabeledContent("확인 범위", value: source.scope)
                        LabeledContent(source.isAutomatic ? "수집 시각" : "확인 시각", value: model.formattedDate(source.sourceUpdatedAt, pattern: "yyyy. M. d HH:mm"))
                        Link(destination: source.postURL) {
                            Label("현재 식단의 게시물 원문", systemImage: "arrow.up.right.square")
                        }
                    } else if model.week != nil {
                        LabeledContent("현재 식단 출처", value: "학교 홈페이지")
                    }
                    if let instagramURL = model.cafeteria.instagramURL,
                       let username = model.cafeteria.instagramUsername {
                        Link(destination: instagramURL) {
                            Label("식당 인스타그램 @\(username)", systemImage: "camera")
                        }
                    }
                    Link(destination: model.cafeteria.sourceURL) {
                        Label("학교 홈페이지 식단표", systemImage: "arrow.up.right.square")
                    }
                    Text("식단마다 출처와 수집 또는 확인 시각을 표시해요. 저장된 식단은 해당 식당·해당 주에만 사용해요. 자동 수집한 메뉴는 이미지 인식 오류가 있을 수 있으니 변경 사항은 게시물 원문을 확인해 주세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("식단 정보")
                }

                Section {
                    LabeledContent("식단 연결", value: model.isAutomaticRefreshConfigured ? "연결 주소 설정됨" : "연결 전")
                    Text(model.isAutomaticRefreshConfigured
                         ? "앱을 열거나 다시 활성화할 때 새로 등록된 식단을 받아와요. 화면을 당겨서 새로고침할 수도 있어요. 등록되지 않은 주의 식단은 이전 주 메뉴로 채우지 않아요."
                         : "아직 식단 연결 주소가 설정되지 않았어요. 현재는 저장된 인스타 확인본과 학교 홈페이지 식단을 표시해요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let message = model.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(MealTheme.warning)
                    }
                } header: {
                    Text("업데이트")
                }

                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "fork.knife")
                            .font(.title2)
                            .foregroundStyle(MealTheme.pine)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("명지밥").font(.headline)
                            Text("캠퍼스의 한 끼를 간편하게")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    LabeledContent("버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("명지밥은 명지대학교의 공식 앱이 아닌 비공식 식단 안내 앱입니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("앱 정보")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .tint(MealTheme.pine)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
    }
}
