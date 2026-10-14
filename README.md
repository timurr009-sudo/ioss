# ScreenRecorder (iOS)

Нативное iOS-приложение для записи экрана (Swift) с Broadcast Extension (ReplayKit) и сохранением видео в фото.

## Структура

- `ios/project.yml` — описание проекта для [XcodeGen](https://github.com/yonaskolb/XcodeGen) (цели: `ScreenRecorder` + `BroadcastExtension`)
- `ios/ScreenRecorder/` — основное приложение
- `ios/BroadcastExtension/` — расширение захвата экрана
- `ios/Shared/` — общий код
- `.github/workflows/ios-ipa.yml` — сборка unsigned IPA через GitHub Actions (macOS runner)
- `codemagic.yaml` — сборка unsigned IPA через [Codemagic](https://codemagic.io/)

## Сборка локально

```bash
cd ios
xcodegen generate
xcodebuild -project ScreenRecorder.xcodeproj -scheme ScreenRecorder \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

## Сборка через Codemagic

1. Подключите репозиторий в Codemagic (Add application from Git).
2. Выберите workflow `ios-ipa` из `codemagic.yaml`.
3. Запустите сборку — готовый `ScreenRecorder.ipa` появится в артефактах.

Для подписанной сборки (App Store / TestFlight) добавьте в `codemagic.yaml` секцию `ios_signing` с ключом App Store Connect.
