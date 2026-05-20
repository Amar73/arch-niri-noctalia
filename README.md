# Arch Linux + Niri

Bootstrap-репозиторий для воспроизводимой установки Arch Linux.
Стек: **niri** (tiling Wayland compositor) + **Waybar** + **Alacritty** + **Catppuccin Mocha**.

Одна команда `make install` — и система готова к работе. Конфиги, пакеты, сервисы,
SSH-инфраструктура и обои деплоятся автоматически с учётом hostname машины.

**Проверено с:** niri 25.11 · waybar 0.10.x · alacritty 0.14.x · Arch Linux (rolling, апрель 2025)

---

## Что умеет этот репозиторий

| Возможность | Как работает |
|-------------|--------------|
| **Полная установка с нуля** | `make install` — пакеты, конфиги, сервисы, greetd, niri |
| **Идемпотентная переустановка** | Прогресс сохраняется в `~/.install-progress`; повторный запуск пропускает выполненные шаги |
| **Синхронизация конфигов** | `make sync` — rsync только управляемых директорий + автобэкап перед изменениями |
| **Параметризованный деплой** | `REPO_USER`, `INSTALLED_REPO_PATH` и др. из `config.sh` — нет хардкода путей |
| **Per-hostname конфиги** | Мониторы и обои деплоятся по hostname из `outputs/` и `wallpapers/` |
| **SSH без IP-адресов** | `deploy-ssh-config.sh` генерирует конфиг по контексту машины, хосты из `/etc/hosts` |
| **Claude Code** | `make claude-proxy` — SSH SOCKS5 туннель + privoxy + wrapper |
| **Проверка без Arch** | `make check-local` — bash syntax + структура файлов, работает в CI |
| **Полная проверка** | `make check` — команды, пакеты, сервисы, niri config на живой системе |
| **Обновление** | `make update` — pacman → yay → orphans → валидация конфигов |
| **Резервная копия** | `make backup` — только управляемые директории ~/.config, .bashrc, .ssh/config |

---

## Структура репозитория

```
arch-niri/
├── Makefile                        — все точки входа: make <target>
├── config.sh                       — централизованные переменные (REPO_USER, пути)
│
├── install.sh                      — полная установка с нуля (с прогресс-трекингом)
├── sync.sh                         — синхронизация конфигов + автобэкап + перезапуск сервисов
├── update.sh                       — pacman → yay → orphans → daemon-reload
├── check-local.sh                  — синтаксис + структура, без pacman/systemctl
├── post-install-check.sh           — полная проверка на живой Arch системе
├── deploy-outputs.sh               — деплой конфигов мониторов и обоев по hostname
├── deploy-ssh-config.sh            — генерация ~/.ssh/config по контексту машины
├── deploy-claude-proxy.sh          — установка Claude Code через SSH SOCKS5 + privoxy
├── install-packages.sh             — установка пакетов из packages/*.txt
├── bootstrap-dotfiles.sh           — деплой dotfiles из репо или git URL
├── logs.sh                         — логи сервисов текущей загрузки
├── backup.sh                       — резервная копия управляемых конфигов
│
├── packages/
│   ├── base.txt                    — базовый набор пакетов для всех машин
│   ├── niri.txt                    — пакеты niri-стека
│   └── aur.txt                     — пакеты из AUR
│
├── Wallpapers/                     — обои (пути генерируются deploy-outputs.sh)
│
└── files/                          — конфиги, деплоятся в систему как есть
    ├── etc/
    │   ├── greetd/config.toml      — display manager (tuigreet → niri-start)
    │   └── systemd/system/
    │       └── ssh-proxy.service   — ШАБЛОН; актуальный файл генерируется при деплое
    └── home/
        ├── .bashrc                 — PS1, алиасы, keychain, git-функции
        ├── .ssh/config             — ШАБЛОН; актуальный файл генерируется deploy-ssh-config.sh
        ├── bin/
        │   └── claude              — wrapper Claude Code (HTTPS_PROXY → privoxy)
        └── .config/
            ├── niri/
            │   ├── config.kdl      — главный конфиг (include conf.d/*)
            │   ├── conf.d/
            │   │   ├── 45-wallpaper.kdl  ← PLACEHOLDER; генерируется deploy-outputs.sh
            │   │   ├── 60-outputs.kdl    ← PLACEHOLDER; генерируется deploy-outputs.sh
            │   │   └── ...
            │   ├── outputs/        — конфиги мониторов по hostname
            │   └── wallpapers/     — шаблоны для генерации kdl обоев
            ├── waybar/             — статусбар: config.jsonc + style.css
            ├── alacritty/          — терминал: Catppuccin Mocha
            ├── swaylock/           — блокировщик: Catppuccin Mocha
            ├── mako/               — уведомления
            ├── fuzzel/             — лончер
            ├── mc/                 — Midnight Commander (скин: nicedark)
            ├── gtk-3.0/ gtk-4.0/  — GTK тема и иконки
            ├── qt6ct/              — Qt6 тема и шрифты
            └── systemd/user/       — user-сервисы: cliphist (swayidle — только документация)
```

### config.sh — параметризация деплоя

Все скрипты подключают `config.sh` как источник истины. Переменные можно переопределить
через окружение без редактирования файлов:

```bash
# Установка для другого пользователя (если текущий USER совпадает):
INSTALLED_REPO_PATH=/home/bob/dotfiles make install

# Переопределить путь к репозиторию на целевой машине (для генерации путей к обоям):
INSTALLED_REPO_PATH=/opt/configs/arch-niri make outputs
```

| Переменная | По умолчанию | Назначение |
|------------|-------------|------------|
| `REPO_USER` | `$USER` | Имя пользователя (для systemd-сервисов, SSH) |
| `REPO_HOME` | `~$REPO_USER` | Домашняя директория |
| `REPO_ROOT` | Директория репо | Корень репозитория |
| `INSTALLED_REPO_PATH` | `$HOME/Amar73/arch-niri` | Путь к репо на целевой машине (для путей обоев) |
| `VPS_USER` | `$REPO_USER` | Пользователь на VPS для SSH-туннеля |

### Как работает деплой по hostname

`deploy-outputs.sh` определяет hostname и:

1. Копирует `outputs/<hostname>.kdl` → `conf.d/60-outputs.kdl`
2. **Генерирует** `conf.d/45-wallpaper.kdl` с реальными путями к обоям (не копирует статический файл)

Файлы в `wallpapers/` — шаблоны для определения hostname'а, не для прямого деплоя.
При этом `set-wallpapers` и kdl-файлы всегда содержат корректный `$HOME`.

### swayidle: почему не через systemd

swayidle запускается через `spawn-at-startup` в `40-startup.kdl`, а **не** через
`systemctl --user enable`. Причина: при `dbus-run-session niri` переменные
`WAYLAND_DISPLAY` и `NIRI_SOCKET` не импортируются в systemd user instance —
swayidle не сможет управлять мониторами.

`swayidle.service` хранится в репо как документация, но `install.sh` намеренно
его не включает. Это предотвращает двойной запуск swayidle.

### SSH без IP-адресов

Все хосты резолвятся через `/etc/hosts`:

```
# /etc/hosts (заполни под свою инфраструктуру)
192.168.1.100  amar    # jump-хост amar224
10.0.0.1       wn75    # рабочий сервер
10.0.0.2       ui      # UI-сервер
1.2.3.4        vps     # зарубежный VPS (для Claude Code / VLESS туннеля)
```

`deploy-ssh-config.sh` генерирует разные конфиги по hostname:

| Hostname | Контекст | wn75 подключается через |
|----------|----------|------------------------|
| `amar224` | jump_host | напрямую (из /etc/hosts) |
| `amar319`, `amar319-1`, ноутбуки | home_net | напрямую (из /etc/hosts) |
| всё остальное | external | конфиг не трогается |

---

## Перед запуском make install

### 1. Базовые требования

- Установленный Arch Linux (base, linux, linux-firmware)
- Пользователь в группе `wheel` с настроенным sudo
- Подключение к интернету: `ping -c2 archlinux.org`

### 2. Предустановка минимального набора

```bash
sudo pacman -S --needed git rsync base-devel
```

### 3. Клонирование репозитория

```bash
mkdir -p ~/Amar73
cd ~/Amar73
git clone https://github.com/Amar73/arch-niri.git
cd arch-niri
chmod +x *.sh
```

### 4. Если репозиторий клонируется в нестандартное место

```bash
# Указать путь, который будет использоваться для генерации путей к обоям:
export INSTALLED_REPO_PATH="$PWD"
```

### 5. Проверка до запуска

```bash
make check-local
```

Проверяет: синтаксис bash, наличие всех файлов, цели Makefile, отсутствие
хардкода `/home/amar` в скриптах.

---

## Установка

```bash
make install
```

При повторном запуске выполненные шаги пропускаются (прогресс в `~/.install-progress`).
Для полной переустановки с нуля:

```bash
rm ~/.install-progress && make install
```

После завершения:

```bash
sudo reboot
```

> **Если после reboot greeter не пускает:**
> ```bash
> sudo rm -f /var/cache/tuigreet/*
> sudo systemctl restart greetd
> ```

После входа в niri:

```bash
make check    # полная проверка
make logs     # логи сервисов
```

---

## Что делает make install

`install.sh` выполняет шаги последовательно, каждый логируется с меткой времени.
Прогресс сохраняется — при повторном запуске выполненные шаги пропускаются.

| Шаг | Действие |
|-----|----------|
| `packages` | `pacman -Syu` + установка из `packages/base.txt` и `niri.txt` |
| `services` | NetworkManager, seatd, greetd |
| `locale` | `/etc/locale.conf` с `LANG=ru_RU.UTF-8` |
| `groups` | video, input, seat — с проверкой существования группы |
| `yay` | Сборка AUR-хелпера из исходников (с trap для очистки tmpdir) |
| `aur` | bibata-cursor-theme, qt5-wayland через `yay --answerdiff=None` |
| `niri_start` | `/usr/local/bin/niri-start` = `dbus-run-session niri` |
| `files` | Синхронизация **только** управляемых директорий `~/.config/` (не весь каталог) |
| `alacritty_themes` | `git clone alacritty-theme` (с fallback при недоступном GitHub) |
| `user_services` | cliphist-text, cliphist-images (swayidle — только spawn-at-startup) |
| `ssh_proxy_svc` | `/etc/systemd/system/ssh-proxy.service` с реальным `User=` |

### Пакеты (make install)

Пакеты читаются из `packages/base.txt` + `packages/niri.txt`. Список в одном
месте — нет расхождения между скриптом и txt-файлами.

---

## Цели Makefile

| Команда | Действие |
|---------|----------|
| `make install` | Полная установка с нуля — пакеты, конфиги, сервисы |
| `make packages` | Установка дополнительных пакетов из `packages/` |
| `make check` | Post-install проверка (требует живой Arch) |
| `make check-local` | Синтаксис + структура файлов, работает везде |
| `make sync` | Синхронизация конфигов + автобэкап + smoke-check |
| `make update` | Обновление: pacman → yay → orphans → daemon-reload |
| `make logs` | Логи всех сервисов (включая ssh-proxy, privoxy) |
| `make backup` | Резервная копия управляемых директорий |
| `make dots-local` | Деплой только `.bashrc` и `.ssh/config` |
| `make outputs` | Деплой конфига мониторов и обоев по hostname |
| `make validate` | Валидация niri config через `niri validate` |
| `make reload` | Reload niri config без перезапуска сессии |
| `make ssh-config` | Деплой `~/.ssh/config` по контексту hostname |
| `make claude-proxy` | Установка Claude Code с SSH-туннелем и privoxy |
| `make claude-check` | Проверка цепочки Claude Code без установки |

---

## Настройка после установки

### Мониторы

```bash
niri msg outputs                    # посмотреть текущие выходы
make outputs                        # задеплоить конфиг для текущего hostname
```

Добавить конфиг для новой машины:

```bash
niri msg outputs
nano files/home/.config/niri/outputs/$(hostname).kdl
make outputs
```

Файлы мониторов:

| Файл | Машина | Конфигурация |
|------|--------|--------------|
| `amar224.kdl` | amar224 | 3× 1920×1080 @ DP-2, DP-3, DP-4 |
| `amar319.kdl` | amar319 | 2× 1920×1080 @ DVI-I-1, HDMI-A-1 |
| `amar319-1.kdl` | amar319-1 | 1× 2560×1600 @ DVI-I-2 |
| `default.kdl` | ноутбуки, прочие | auto/preferred |

### Обои

`deploy-outputs.sh` генерирует `45-wallpaper.kdl` с реальными путями к `Wallpapers/`.
Обои ищутся в `${INSTALLED_REPO_PATH}/Wallpapers/` — путь задаётся в `config.sh`.

Добавить обои для новой машины:

```bash
niri msg outputs                                          # узнать имена выходов
nano files/home/.config/niri/wallpapers/$(hostname).kdl  # добавить шаблон
make outputs                                              # задеплоить
```

### SSH config

```bash
make ssh-config                         # применить конфиг для текущей машины
./deploy-ssh-config.sh --dry-run        # посмотреть без применения
```

### Claude Code

```bash
# Предварительно:
ssh ${VPS_USER}@vps echo ok             # добавить VPS в known_hosts
make claude-proxy                       # установить всю цепочку
claude                                  # первый запуск (авторизация через браузер)
make claude-check                       # проверка цепочки
```

### Waybar: температура CPU

```bash
for f in /sys/class/hwmon/hwmon*/temp1_input; do
    echo "$f: $(( $(cat $f) / 1000 ))°C"
done
```

Добавить путь в `~/.config/waybar/config.jsonc`:

```jsonc
"temperature": {
    "hwmon-path": "/sys/class/hwmon/hwmon0/temp1_input"
}
```

### Waybar: раскладка клавиатуры

```bash
niri msg --json keyboard-layouts | jq .
```

Стандартные имена для `us+ru`: `"English (US)"` и `"Russian"`. При отличии —
отредактировать `~/.config/waybar/config.jsonc`:

```jsonc
"niri/language": {
    "format-English (US)": "󰌌 EN",
    "format-Russian":      "󰌌 RU"
}
```

---

## Биндинги Niri

`Mod` = Super (клавиша Windows/Command).

### Приложения

| Клавиша | Действие |
|---------|----------|
| `Mod+Return` | Alacritty |
| `Mod+D` | Fuzzel (лончер) |
| `Mod+B` | Яндекс.Браузер |
| `Mod+Q` | Закрыть окно |
| `Mod+Shift+E` | Выйти из niri |

### Навигация

| Клавиша | Действие |
|---------|----------|
| `Mod+←→` | Фокус между колонками |
| `Mod+↑↓` | Фокус между окнами в колонке |
| `Mod+Shift+←→` | Переместить колонку |
| `Mod+Shift+↑↓` | Переместить окно в колонке |

### Размер и компоновка

| Клавиша | Действие |
|---------|----------|
| `Mod+F` | Развернуть колонку |
| `Mod+Shift+F` | Полноэкранный режим |
| `Mod+C` | Центрировать колонку |
| `Mod+R` | Переключить пресеты ширины (33%/50%/67%/100%) |
| `Mod+−` / `Mod+=` | Ширина −10% / +10% |

### Воркспейсы (независимые на каждом мониторе)

| Клавиша | Действие |
|---------|----------|
| `Mod+1..9`, `Mod+0` | Переключить воркспейс 1-10 |
| `Mod+Shift+1..9`, `Mod+Shift+0` | Перенести колонку на воркспейс |
| `Mod+Page_Up/Down` | Воркспейс выше/ниже |

### Мониторы

| Клавиша | Действие |
|---------|----------|
| `Mod+Tab` | Фокус на монитор вправо |
| `Mod+Shift+Tab` | Фокус на монитор влево |
| `Mod+Shift+,` / `Mod+Shift+.` | Переместить окно на монитор |

### Блокировка и экран

| Клавиша | Действие |
|---------|----------|
| `Mod+L` | Заблокировать (swaylock) |
| `Mod+Shift+L` | Выключить мониторы |
| `Mod+Ctrl+L` | Заблокировать + выключить мониторы |

### Утилиты и звук

| Клавиша | Действие |
|---------|----------|
| `Mod+V` | История буфера обмена (cliphist + fuzzel) |
| `Print` | Скриншот области → `~/Screenshots/` |
| `Mod+Print` | Скриншот экрана → `~/Screenshots/` |
| `Shift+F1` | Mute/unmute |
| `Shift+F2` / `Shift+F3` | Громкость −5% / +5% |

---

## Для владельца репозитория

### SSH-ключ для GitHub

```bash
ssh-keygen -t ed25519 -C "user@email" -f ~/.ssh/id_ed25519
gh auth login       # через GitHub CLI
# или curl + Personal Access Token (см. старый README)
```

### Клонирование по SSH (с правом на push)

```bash
cd ~/Amar73
git clone git@github.com:Amar73/arch-niri.git
cd arch-niri && chmod +x *.sh
```

### /etc/hosts для SSH-инфраструктуры

```bash
sudo tee -a /etc/hosts << 'EOF'
192.168.1.100  amar
192.168.1.101  wn75
192.168.1.110  ui
1.2.3.4        vps
EOF
ping -c1 amar
```

---

## Changelog

### v7.0 — рефакторинг надёжности

**Критические исправления:**

- `sync.sh` и `install.sh`: заменён `rsync --delete ~/.config/` на синхронизацию
  конкретных поддиректорий — больше не уничтожает данные приложений
- `sync.sh`: автоматический бэкап через `backup.sh` перед любыми изменениями
- Хардкод `/home/amar` устранён из всех скриптов; введён `config.sh`

**Высокоприоритетные исправления:**

- `install.sh`: `swayidle.service` больше не включается через systemd —
  устранён риск двойного запуска (управляется только через `spawn-at-startup`)
- `install_yay()`: добавлен `trap EXIT` для очистки tmpdir при ошибке
- `yay` вызовы: добавлены `--answerdiff=None --answerdiff=None` для неинтерактивной установки

**Новое:**

- `config.sh` — централизованные переменные, переопределяемые через окружение
- `~/.install-progress` — трекинг прогресса для идемпотентного повторного запуска
- `deploy-outputs.sh` генерирует `45-wallpaper.kdl` динамически (нет хардкода путей)
- `logs.sh`: добавлены `ssh-proxy.service` и `privoxy.service`
- `post-install-check.sh`: исправлен jq-парсер keyboard-layouts, проверка хардкода
- `backup.sh`: бэкапит только управляемые директории, не весь `~/.config/`
- `swayidle.service`: документирован как резервный (не активируется)
- `ssh-proxy.service` в `files/`: шаблон с placeholders; актуальный — генерируется скриптами
- `waybar/config.jsonc`: добавлены версии совместимости в комментарий
- `alacritty.toml`: исправлен комментарий к фоновому цвету (`custom dark`, не `crust`)
