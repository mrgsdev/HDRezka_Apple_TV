import SwiftUI

/// Settings → «Детский режим»: what it does, its level, and the way in and out. The settings form shows
/// the steps: a section inside a form presents nothing on tvOS.
struct ParentalSection: View {
    @Binding var sheet: ParentalSheet.Mode?
    private let parental = ParentalControl.shared

    var body: some View {
        Section {
            if parental.isUnreadable {
                Label("Не удалось прочитать настройки детского режима из связки ключей, поэтому включён самый строгий уровень.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Повторить", action: parental.load)
            } else if let limit = parental.limit {
                LabeledContent("Возраст", value: String(localized: "до \(limit.title)"))
                Button("Изменить или выключить…") { sheet = .manage }
            } else {
                Button("Включить детский режим…") { sheet = .setup }
            }
        } header: {
            Text("Детский режим")
        } footer: {
            Text("Скрывает фильмы и сериалы старше выбранного возраста и отзывы, не даёт их смотреть. Изменить или выключить его можно только с PIN-кодом.")
        }
    }
}

/// The steps of turning kid mode on, changing it and getting back in with the recovery code.
struct ParentalSheet: View {
    enum Mode: String, Identifiable {
        case setup, manage
        var id: String { rawValue }
    }

    private enum Step: Equatable {
        case chooseLevel
        case enterPIN
        case forgotPIN
        case manage
        /// Choosing a PIN, the first time or after the old one or the recovery code.
        case newPIN
        /// The new PIN once more, to be sure of it.
        case repeatPIN(String)
        case showCode(String)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var level = AgeLimit.age12
    @State private var code = ""
    @State private var message: String?

    private let parental = ParentalControl.shared

    init(mode: Mode) {
        self.mode = mode
        _step = State(initialValue: mode == .setup ? .chooseLevel : .enterPIN)
        _level = State(initialValue: ParentalControl.shared.limit ?? .age12)
    }

    var body: some View {
        VStack(spacing: 50) {
            content
            if let message {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(80)
        .frame(maxWidth: 1300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .animation(.easeOut(duration: 0.2), value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .chooseLevel:
            title("Детский режим", "Выберите, до какого возраста показывать фильмы и сериалы.")
            levelPicker
            buttons {
                Button("Отмена") { dismiss() }
                Button("Дальше") { go(.newPIN) }
            }

        case .newPIN:
            title("Придумайте PIN-код", "4 цифры. Он понадобится, чтобы изменить или выключить детский режим.")
            PINPad { pin in go(.repeatPIN(pin)) }
            buttons { Button("Отмена") { dismiss() } }

        case let .repeatPIN(first):
            title("Введите PIN-код ещё раз", "Чтобы не ошибиться в нём.")
            PINPad { pin in savePIN(first, pin) }
                .id(first)
            buttons { Button("Отмена") { dismiss() } }

        case let .showCode(recovery):
            title("Код восстановления", "Запишите его. Если вы забудете PIN-код, этот код поможет задать новый. Больше он показан не будет.")
            Text(verbatim: recovery)
                .font(.system(size: 76, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 50)
                .padding(.vertical, 30)
                .background(Brand.panel, in: RoundedRectangle(cornerRadius: 30))
            buttons { Button("Я записал код") { dismiss() } }

        case .enterPIN:
            title("Введите PIN-код", "Чтобы изменить или выключить детский режим.")
            PINPad { pin in handle(parental.check(pin: pin), next: .manage) }
                .id(message ?? "")
            buttons {
                Button("Отмена") { dismiss() }
                Button("Забыли PIN-код?") { go(.forgotPIN) }
            }

        case .forgotPIN:
            title("Код восстановления", "Введите код, который был показан при включении детского режима или последней смене PIN-кода.")
            TextField(text: $code, prompt: Text(verbatim: "XXXX-XXXX-XXXX")) { EmptyView() }
                .font(.system(.title2, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(width: 700)
            buttons {
                Button("Отмена") { dismiss() }
                Button("Продолжить") { handle(parental.check(recoveryCode: code), next: .newPIN) }
                    .disabled(code.filter { $0.isLetter || $0.isNumber }.count < 12)
            }

        case .manage:
            title("Детский режим", "Возраст, до которого показывать фильмы и сериалы.")
            levelPicker
            buttons {
                Button("Сохранить") {
                    parental.setLimit(level)
                    dismiss()
                }
                Button("Сменить PIN-код") { go(.newPIN) }
                Button("Выключить", role: .destructive) {
                    parental.setLimit(nil)
                    dismiss()
                }
                Button("Отмена") { dismiss() }
            }
        }
    }

    private var levelPicker: some View {
        HStack(spacing: 30) {
            ForEach(AgeLimit.allCases) { limit in
                Button {
                    level = limit
                } label: {
                    HStack(spacing: 12) {
                        if level == limit { Image(systemName: "checkmark") }
                        Text(verbatim: limit.title)
                    }
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 160)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .focusSection()
    }

    private func title(_ text: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.title.bold())
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Full width, so the remote reaches the row from anything above it, however narrow the row is.
    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 30) { content() }
            .frame(maxWidth: .infinity)
            .focusSection()
    }

    // MARK: Steps

    private func go(_ next: Step) {
        message = nil
        code = ""
        step = next
    }

    private func savePIN(_ first: String, _ second: String) {
        guard first == second else {
            go(.newPIN)
            message = String(localized: "PIN-коды не совпадают. Придумайте PIN-код заново.")
            return
        }
        let recovery = parental.limit == nil ? parental.enable(limit: level, pin: first) : parental.resetPIN(to: first)
        go(.showCode(recovery))
    }

    private func handle(_ result: ParentalControl.CheckResult, next: Step) {
        switch result {
        case .ok:
            go(next)
        case .wrong:
            message = String(localized: "Неверно. Попробуйте ещё раз.")
        case let .locked(until):
            let minutes = max(1, Int(until.timeIntervalSinceNow / 60 + 0.99))
            message = String(localized: "Слишком много неверных попыток. Попробуйте через \(minutes) мин.")
        }
    }
}

/// Four digits on a keypad, as the system's own restrictions passcode takes them: dots fill in as the
/// digits come, and the fourth hands the PIN over.
private struct PINPad: View {
    let done: (String) -> Void

    @State private var pin = ""

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]

    var body: some View {
        VStack(spacing: 40) {
            HStack(spacing: 30) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? Color.primary : Color.primary.opacity(0.15))
                        .frame(width: 30, height: 30)
                }
            }
            VStack(spacing: 20) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 20) {
                        ForEach(row, id: \.self) { key in
                            if key.isEmpty {
                                Color.clear.frame(width: 150, height: 90)
                            } else {
                                Button {
                                    press(key)
                                } label: {
                                    Text(verbatim: key)
                                        .font(.title2.weight(.semibold))
                                        .frame(width: 110, height: 60)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .focusSection()
    }

    private func press(_ key: String) {
        if key == "⌫" {
            pin = String(pin.dropLast())
            return
        }
        guard pin.count < 4 else { return }
        pin += key
        if pin.count == 4 {
            let entered = pin
            // Long enough to see the last dot fill in.
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                pin = ""
                done(entered)
            }
        }
    }
}

/// Where kid mode has hidden every title: says so, and where the age is changed.
struct KidModeEmptyView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 70))
                .foregroundStyle(.secondary)
            Text("Для выбранного возраста здесь ничего нет")
                .font(.headline)
            Text("Детский режим скрывает фильмы и сериалы старше \(ParentalControl.shared.limit?.title ?? ""). Возраст меняется в Настройках.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1000)
        }
        .padding(60)
        .frame(maxWidth: .infinity)
    }
}
