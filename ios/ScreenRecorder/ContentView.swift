import SwiftUI

struct ContentView: View {
    @StateObject private var model = RecorderModel()
    @State private var picker = BroadcastPickerController()
    @Environment(\.scenePhase) private var scenePhase

    private let background = Color(red: 0.055, green: 0.055, blue: 0.063)
    private let surface = Color(red: 0.11, green: 0.11, blue: 0.12)
    private let accent = Color(red: 0.94, green: 0.27, blue: 0.27)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    header
                    recordButton
                    timer
                    if model.photoAccessDenied { photoAccessCard }
                    if let message = model.statusMessage { statusCard(message) }
                    stepsCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.appBecameActive() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Запись экрана")
                .font(.system(size: 28, weight: .bold))
            Text("Со звуком, до 1 часа. Видео сохраняется только в «Фото» на этом iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var recordButton: some View {
        Button {
            picker.present()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: model.progress)

                if model.isRecording {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent)
                        .frame(width: 64, height: 64)
                } else {
                    Circle()
                        .fill(accent)
                        .frame(width: 140, height: 140)
                }
            }
            .frame(width: 196, height: 196)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(
            BroadcastPicker(controller: picker)
                .frame(width: 1, height: 1)
                .opacity(0.02)
                .accessibilityHidden(true)
        )
        .accessibilityLabel(model.isRecording ? "Остановить запись" : "Начать запись экрана")
    }

    private var timer: some View {
        VStack(spacing: 6) {
            Text(formatted(model.elapsed))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .monospacedDigit()
            HStack(spacing: 8) {
                if model.isRecording {
                    Circle().fill(accent).frame(width: 8, height: 8)
                }
                Text(model.isRecording ? "Идёт запись · максимум 60:00" : "Нажмите, чтобы начать")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var photoAccessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Нет доступа к «Фото»")
                .font(.headline)
            Text("Без него запись не сможет сохраниться. Разрешите добавление в «Фото» в настройках.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Открыть настройки") { model.openSettings() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusCard(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Как записывать")
                .font(.headline)
            step(1, "Нажмите красную кнопку.")
            step(2, "Включите «Микрофон», если нужен ваш голос, и нажмите «Начать вещание».")
            step(3, "Сверните приложение и откройте что угодно — запись идёт в фоне.")
            step(4, "Чтобы остановить, нажмите красный индикатор вверху экрана или кнопку здесь.")
            step(5, "Видео само сохранится в «Фото». Через 60 минут запись остановится автоматически.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08), in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
