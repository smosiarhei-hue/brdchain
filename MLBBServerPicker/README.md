# MLBB Server Picker

Меряет реальную задержку до хостов Mobile Legends: Bang Bang прямо с iPhone,
показывает, что отвечает, и помогает выбрать сервер до первого входа в игру.

## Честно о главном

Приложение **не знает адреса серверов MLBB заранее**. У каждого региона свой
гейтвей, они меняются между версиями игры, и Moonton их не публикует. Первая
версия приложения содержала выдуманные адреса — выглядели правдоподобно, но не
резолвились, и скан показывал «нет ответа» везде.

Поэтому сейчас встроенные хосты — это **проверочные адреса инфраструктуры**
Moonton и Garena. Их роль — проверить, что сам телефон ходит в сеть, и показать,
какие домены вообще живы. Настоящие игровые гейтвеи ты приносишь из логов игры
через «Импортировать хосты из логов».

**Смена региона в уже установленной MLBB невозможна.** iOS не даёт приложению
писать в файлы другой игры, а публичного способа задать регион при запуске у
MLBB нет. Только сброс данных приложения, с потерей привязки аккаунта.

## Как узнать настоящие хосты

1. Подключи iPhone к Mac кабелем, открой Xcode
2. Window → Devices and Simulators → вкладка с логами → запусти запись
3. Запусти MLBB, дойди до выбора региона, выбери нужный сервер
4. Останови запись, найди домены `moonton.com` / `garena.com`
5. Вставь их в приложение через «Импортировать хосты из логов»

Быстрее: приложение для снятия сетевых логов на самом телефоне (HTTP Catcher,
Stream) покажет все домены, к которым обращается игра, без кабеля и Xcode.

Приложение принимает хосты в любом виде: по одному на строку, через запятую, с
портом или без, с `https://` или без. Лишнее отбрасывается, дубликаты
игнорируются.

## Что умеет

- TCP handshake замер через `NWConnection`, а не HTTP — гейтвей отвечает только на
  игровом порту и вернул бы 404 на `/`, дав бессмысленное число
- Параллельный скан всех известных хостов с лимитом в 8 задач
- Цветовая маркировка: <60 ms зелёный, <120 ms жёлтый, дальше красный
- Разделение хостов на встроенные и подтверждённые из логов — приложение
  рекомендует **только подтверждённые**
- Явный вердикт: «нужен список хостов» / «никто не ответил» / найден рабочий
- Запуск MLBB, фолбэк на App Store если игра не установлена
- Иконка приложения

## Структура

```
MLBBServerPicker/
├── Project.yml                      # XcodeGen, источник истины
└── Sources/
    ├── App/MLBBServerPickerApp.swift
    ├── Models/Host.swift            # хост + происхождение (заглушка/из логов)
    ├── Services/
    │   ├── PingService.swift        # TCP handshake, таймаут, OneShot
    │   ├── HostCatalog.swift        # проверочные адреса Moonton/Garena
    │   ├── HostStore.swift          # персистентность импортированного
    │   ├── ServerScanner.swift      # параллельный скан + вердикт
    │   └── GameLauncher.swift
    └── Views/
        ├── ContentView.swift
        ├── HostImporterView.swift   # вставка хостов из логов
        └── HowItWorksView.swift     # инструкция

tools/make_icon.py                   # генерация иконки, без внешних зависимостей
```

`Info.plist` генерируется XcodeGen из `Project.yml`, руками не трогай.
`.xcodeproj` в `.gitignore` — он артефакт сборки.

## Сборка

### CI

`.github/workflows/build-ios.yml` собирает unsigned ipa на macos-15 / Xcode 16.2,
публикует в скользящий релиз `latest` и отдельный релиз для тегов `v*`. Никаких
Apple-кред в CI нет — подпись локальная.

Артефакт: `releases/latest` в репозитории. Дублируется в Artifacts прогона со
сроком жизни 30 дней.

Локально:

```bash
brew install xcodegen
cd MLBBServerPicker
xcodegen generate
xcodebuild -project MLBBServerPicker.xcodeproj -scheme MLBBServerPicker \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build build

cd build/Build/Products/Release-iphoneos
rm -rf Payload MLBBServerPicker.ipa && mkdir Payload
cp -R MLBBServerPicker.app Payload/
rm -rf Payload/MLBBServerPicker.app/_CodeSignature
rm -f Payload/MLBBServerPicker.app/embedded.mobileprovision
zip -qry MLBBServerPicker.ipa Payload
```

### Иконка

```bash
python tools/make_icon.py
```

Пишет 11 размеров в `Sources/Assets.xcassets/AppIcon.appiconset`. Зависимостей
нет, PNG собирается через `zlib` и `struct`. Каждая строка PNG prefixed байтом
фильтра — без него файл выглядит валидным, но не декодируется.

### Установка

1. Открыть `MLBBServerPicker.ipa` в GBox Esign
2. Подписать сертификатом `Apple Development: <твой Team ID>`
3. Экспорт в GBox → установка
4. Настройки → Основные → VPN и управление устройством → доверить сертификату

iOS 16+. Сеть нужна только для замера.