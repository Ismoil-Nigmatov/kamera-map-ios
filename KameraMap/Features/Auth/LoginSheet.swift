import SwiftUI

struct LoginSheet: View {
    @Environment(SessionStore.self) var session
    @Environment(MapStore.self) var store
    @Environment(ToastCenter.self) var toasts

    enum Step: Equatable {
        case phone
        case code(LoginCode)
    }

    enum Field: Hashable {
        case phone
        case code
        case name
    }

    @State var step: Step = .phone
    @State var phoneDigits = ""
    @State var code = ""
    @State var name = ""
    @State var isWorking = false
    @State var resendAt = Date.distantPast
    @FocusState var focus: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch step {
                    case .phone:
                        phoneStep
                    case .code(let login):
                        codeStep(login)
                    }
                }
                .padding(20)
                .animation(.snappy, value: step)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(step == .phone ? "Вход" : "Код из SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .phone ? "Отмена" : "Назад") {
                        if step == .phone {
                            store.sheet = nil
                        } else {
                            step = .phone
                            code = ""
                            focus = .phone
                        }
                    }
                }
            }
        }
        .onAppear {
            focus = .phone
        }
    }

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Вход по номеру телефона")
                    .font(.title2.weight(.bold))
                Text("Пароль не нужен: пришлём код. Новый номер сразу станет аккаунтом.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text("+998")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                PhoneField(digits: $phoneDigits, isFocused: step == .phone)
                    .frame(height: 30)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))

            Button {
                Task { await requestCode() }
            } label: {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Получить код")
                }
            }
            .buttonStyle(ProminentButtonStyle())
            .disabled(phoneDigits.count != 9 || isWorking)
            .accessibilityIdentifier("requestCodeButton")
        }
    }

    private func codeStep(_ login: LoginCode) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Введите код")
                    .font(.title2.weight(.bold))
                Text("Отправили на \(login.phone)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let shown = login.code {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    (Text("SMS пока не отправляются. Ваш код: ") + Text(shown).font(.body.monospaced().weight(.bold)))
                        .font(.subheadline)
                        .accessibilityIdentifier("shownCode")
                    Spacer(minLength: 0)
                    Button("Вставить") {
                        code = shown
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(14)
                .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
            }

            TextField("Код из 6 цифр", text: $code)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .code)
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(6))
                    if digits != value {
                        code = digits
                    }
                }
                .accessibilityIdentifier("codeField")

            if login.isNewUser {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Как вас зовут?")
                        .font(.headline)
                    TextField("Имя", text: $name)
                        .textContentType(.givenName)
                        .focused($focus, equals: .name)
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("nameField")
                }
            }

            Button {
                Task { await signIn(login) }
            } label: {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Войти")
                }
            }
            .buttonStyle(ProminentButtonStyle())
            .disabled(code.count != 6 || (login.isNewUser && name.trimmingCharacters(in: .whitespaces).isEmpty) || isWorking)
            .accessibilityIdentifier("signInButton")

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = Int(resendAt.timeIntervalSince(context.date).rounded(.up))
                if left > 0 {
                    Text("Отправить код ещё раз можно через \(left) с")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Отправить код ещё раз") {
                        Task { await requestCode() }
                    }
                    .font(.footnote.weight(.semibold))
                    .disabled(isWorking)
                }
            }
        }
    }

    private func requestCode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let login = try await session.requestCode(phone: "+998" + phoneDigits)
            resendAt = Date().addingTimeInterval(TimeInterval(login.resendIn))
            code = ""
            step = .code(login)
            focus = login.code == nil ? .code : (login.isNewUser ? .name : .code)
        } catch {
            toasts.show(error)
        }
    }

    private func signIn(_ login: LoginCode) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try await session.signIn(phone: "+998" + phoneDigits, code: code, name: login.isNewUser ? trimmed : nil)
            Haptics.success()
            toasts.show("Вы вошли. Добро пожаловать!")
            store.didSignIn()
        } catch {
            toasts.show(error)
        }
    }
}
