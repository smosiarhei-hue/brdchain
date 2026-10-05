# MLBB Server Picker

Измеряет реальный TCP-пинг до гейтвеев Mobile Legends: Bang Bang прямо с iPhone,
сортирует серверы, подсвечивает лучший и запускает игру.

## Что это умеет

- Меряет пинг до каждого региона параллельно, ограничивая конкурентность
- Сортирует по задержке, красит: `<60 ms` зелёный, `<120 ms` жёлтый, дальше красный
- Автовыбор лучшего сервера + ручной выбор любого региона
- Показывает, какой регион выбрать на стартовом экране MLBB
- Кнопка запуска игры (`mobilelegends://`), фолбэк на App Store если не установлена
- Ручной ввод своего хоста и порта с проверкой пинга

## Чего это НЕ умеет

**Переключить сервер внутри уже установленной MLBB нельзя.** Песочница iOS
запрещает приложению читать и писать контейнер другой игры. У MLBB нет
публичного URL scheme, который принимает регион. Единственный способ сменить
регион в установленной игре — сбросить данные приложения.

Приложение решает задачу, которую реально можно решить: **подбирает правильный
сервер до первого входа** и говорит, что выбрать.

## Структура

```
MLBBServerPicker/
├── Project.yml                    # XcodeGen — источник истины для проекта
└── Sources/
    ├── App/MLBBServerPickerApp.swift
    ├── Models/Region.swift
    ├── Services/
    │   ├── PingService.swift      # TCP handshake, замер латентности
    │   ├── RegionCatalog.swift    # 14 регионов + кастомные из UserDefaults
    │   ├── ServerScanner.swift    # параллельный скан, лучший результат на регион
    │   └── GameLauncher.swift
    └── Views/
        ├── ContentView.swift
        └── CustomHostView.swift
```

`Info.plist` генерируется XcodeGen из `Project.yml` — руками его не трогай.

## Сборка

### CI (без подписи)

Workflow `.github/workflows/build-ios.yml` собирает **unsigned** ipa на
`macos-15` / Xcode 16.2 и отдаёт артефактом. Никаких секретов в репозитории нет,
Apple-креды в CI не попадают.

Сборка локально:

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

### Установка

1. Открыть `MLBBServerPicker.ipa` в **GBox Esign**
2. Подписать своим сертификатом (`Apple Development: <твой Team ID>`)
3. Экспорт в GBox → установка
4. Настройки → Основные → VPN и управление устройством → **доверие сертификату**

Приложение требует iOS 16+. Сеть нужна только для замера пинга.

## Калибровка серверов

Хосты в `RegionCatalog.swift` — **кандидаты**, а не выверенные адреса. Реальные
гейтвеи отличаются от региона к региону и версии к версии, и в открытых
источниках их достоверного списка нет.

Как откалибровать:

1. Открыть **GameKit → Network** или Console.app на macOS, пока телефон и MLBB
   в одной сети
2. Запустить MLBB, дойти до выбора региона, выбрать нужный
3. В логах найти фактический хост гейтвея
4. Добавить его в приложении через **+**, проверить пинг
5. Если пинг адекватный — перенести хост в `RegionCatalog.defaults`

Пока калибровка не сделана, часть регионов покажет «нет ответа». Это ожидаемо,
не баг.

## Как это работает

`PingService` замеряет время до состояния `.ready` у `NWConnection` — то есть
полный TCP three-way handshake. HTTP-запрос не используется: гейтвей может
отвечать только на игровом порту и вернуть 404 на `/`, что дало бы ложные
цифры. Таймаут 4 секунды, `OneShot` защищает от двойного resume, потому что
`NWConnection` шлёт `failed`, а затем `cancelled`.

`ServerScanner` гоняет все хосты через `withTaskGroup` с лимитом в 8 задач и
сводит к лучшему результату на регион. Регионы без ответа остаются в списке с
пометкой — молчаливый пробел выглядит как баг.