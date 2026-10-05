import SwiftUI

struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Приложение не знает адресов серверов MLBB заранее. У каждого региона свой гейтвей, они меняются между версиями игры, и Moonton их не публикует. Поэтому единственный честный способ — посмотреть, к чему обращается сама игра.")
                }

                Section("Как снять логи") {
                    Step(1, "Подключи iPhone к Mac кабелем и открой Xcode.")
                    Step(2, "Выбери своё устройство в верхней панели, затем Window → Devices and Simulators.")
                    Step(3, "Открой вкладку с логами устройства и запусти запись.")
                    Step(4, "Запусти MLBB, дойди до экрана выбора региона и выбери нужный сервер.")
                    Step(5, "Останови запись и найди в логах домены moonton.com или garena.com, к которым шло обращение. Это и есть настоящие хосты.")
                    Step(6, "Скопируй их и вставь в приложение через «Импортировать хосты из логов».")
                }

                Section("Быстрый способ с телефонa") {
                    Text("Установи бесплатное приложение, собирающее логи сети, например HTTP Catcher или Stream. Оно покажет все домены, к которым обращается MLBB. Это быстрее, чем возиться с Xcode.")
                        .font(.callout)
                }

                Section {
                    Text("Смена региона в уже установленной игре невозможна: iOS не даёт приложению менять файлы другой игры, а публичного способа задать регион при запуске у MLBB нет. Только сброс данных приложения — с потерей привязки аккаунта.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Честно")
                }

                Section {
                    Text("Замер идёт по TCP handshake, а не по HTTP. Гейтвей может отвечать только на игровом порту и возвращать 404 на /, и такой запрос дал бы бессмысленное число.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Как это работает")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Понятно") { dismiss() }
                }
            }
        }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
            Text(text)
        }
        .padding(.vertical, 1)
    }
}

#Preview {
    HowItWorksView()
}