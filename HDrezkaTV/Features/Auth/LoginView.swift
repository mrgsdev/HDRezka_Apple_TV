import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var mirror = Mirror.current.absoluteString
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var phoneLogin = PhoneLoginModel()

    var body: some View {
        HStack(alignment: .center, spacing: 100) {
            VStack(alignment: .leading, spacing: 28) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 520)
                Text("Войдите в свой аккаунт HDrezka, чтобы смотреть фильмы и сериалы на Apple TV.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                phoneLoginCard
            }
            .frame(maxWidth: 820, alignment: .leading)

            VStack(spacing: 28) {
                Text("Или введите здесь")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // .asciiCapable opens the TV keyboard in Latin even when the system language is Russian.
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                    .keyboardType(.asciiCapable)
                    .onSubmit { Task { await signIn() } }

                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        if isLoading { ProgressView() }
                        Text(isLoading ? "Входим…" : "Войти")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty)

                if let message = errorText ?? phoneLogin.status {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(errorText == nil ? Color.secondary : Color.red)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Зеркало сайта")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://rezka.fi", text: $mirror)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(applyMirror)
                    Text(SettingsView.mirrorHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)
            }
            .frame(width: 680)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The logo's dark navy; the logo asset itself is transparent, so any shade works.
        .background(Color(.sRGB, red: 2 / 255, green: 19 / 255, blue: 25 / 255).ignoresSafeArea())
        .onAppear { phoneLogin.start() }
        .onDisappear { phoneLogin.stop() }
    }

    private var phoneLoginCard: some View {
        HStack(alignment: .center, spacing: 36) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(.white)
                if let qr = phoneLogin.qrCode {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                } else {
                    ProgressView().tint(.black)
                }
            }
            .frame(width: 280, height: 280)

            VStack(alignment: .leading, spacing: 14) {
                Text("Вход с телефона")
                    .font(.headline)
                Text("Наведите камеру iPhone на QR-код или откройте адрес в браузере на устройстве в той же сети:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(phoneLogin.url?.absoluteString ?? "Запускаем…")
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(28)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 28))
    }

    private func applyMirror() {
        if let url = Mirror.normalize(mirror) {
            Mirror.current = url
            mirror = url.absoluteString
            errorText = nil
            auth.refresh()
        } else {
            errorText = "Некорректный адрес зеркала"
        }
    }

    private func signIn() async {
        guard !isLoading, !email.isEmpty, !password.isEmpty else { return }
        applyMirror()
        isLoading = true
        errorText = nil
        do {
            try await auth.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
