# Kamera Map для iOS

Нативное приложение (SwiftUI, iOS 17+) к сайту Kamera Map: карта камер и радаров Узбекистана, метки водителей, правки камер, вход по номеру телефона. Карта — Яндекс MapKit (полная версия SDK, пакет `yandex/mapkit-ios`).

## Как устроено

- Проект описан в `project.yml` (XcodeGen), сам `.xcodeproj` не хранится — генерируется командой `xcodegen generate`.
- Данные берутся из API сайта: адрес — `KM_API_BASE_URL` в `Config/App.xcconfig` (сейчас тестовый сервер https://test.ismoiljon.me).
- Ключ MapKit — `KM_YANDEX_MAPKIT_KEY`. В репозиторий он не попадает: локально лежит в `Config/Secrets.xcconfig` (образец — `Config/Secrets.example.xcconfig`), в сборке на GitHub — в секрете `YANDEX_MAPKIT_KEY`.

## Сборка без Mac

Каждый push в `main` запускает GitHub Actions на `macos-26`: генерация проекта, сборка, юнит-тесты и UI-тесты в симуляторе iPhone. UI-тесты проходят по главным экранам и сохраняют скриншоты — они лежат в артефакте `screenshots` у запуска.

```bash
gh run list --repo <владелец>/kamera-map-ios
gh run download <номер запуска> --name screenshots
```

## Сборка на Mac

```bash
brew install xcodegen
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # и впишите ключ MapKit
xcodegen generate
open KameraMap.xcodeproj
```

## Что умеет

- Карта с камерами: цвет — статус (работает / не проверена / не работает), стрелка — направление съёмки, число — лимит скорости; близкие камеры собираются в кластеры.
- Карточка камеры: что фиксирует, на каких полосах и когда, «Камера на месте?», правки водителей с голосованием, для админа — смена статуса.
- Метки водителей (тренога, пост ДПС, ДТП, другое): место выбирается сдвигом карты, голосование «Ещё там / Уже нет».
- Вход по номеру и коду, профиль, выход и удаление аккаунта (требование App Store).
- Ссылка на условия Яндекс Карт — в профиле, в разделе «О приложении».
