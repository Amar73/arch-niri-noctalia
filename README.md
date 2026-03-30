# Arch Linux + Niri + Noctalia v6.3

Bootstrap-репозиторий для чистого Arch Linux.

## Что изменилось в v6.3

### Исправлено (багфиксы)

- **git-алиасы `gp`/`gl`/`gpf`** → переведены в функции.
  В v6.2 `$()` в алиасах вычислялся при `source .bashrc`, а не при вызове —
  ветка фиксировалась в момент загрузки оболочки. Теперь читается в runtime.

- **`rsync --delete` в `sync.sh` и `install.sh`** → добавлена защита.
  Пустой или несуществующий источник при `--delete` уничтожал весь `~/.config`.
  Теперь скрипт падает с ошибкой до `rsync`, если src не найден или пуст.

- **`trap EXIT` в `install_paru()`** → заменён на явную очистку tmpdir.
  `trap EXIT` глобален в bash — перезаписывал любой последующий trap.

- **`paru`** → заменён на **`yay`** во всех скриптах и проверках.

- **Мёртвая переменная `REPO_URL="${2:-}"`** убрана из `bootstrap-dotfiles.sh`.

- **`autoremove()`** — добавлен `# shellcheck disable=SC2086` с объяснением.

- **`gp`/`gpf`/`gl` добавлены в `unset -f`** внутри функции `reload()`.

### Новое

| Файл | Описание |
|------|----------|
| `files/home/.config/alacritty/` | Конфиг терминала alacritty, палитра Catppuccin Mocha |
| `files/home/.config/swaylock/config` | Конфиг блокировщика, та же палитра |
| `files/home/.config/waybar/config.jsonc` | Waybar: niri/workspaces, niri/window, cpu, mem, disk, temp, audio, net, lang |
| `files/home/.config/waybar/style.css` | Waybar CSS, Catppuccin Mocha, прозрачный фон |
| `files/home/.config/systemd/user/cliphist-text.service` | История текстового буфера (переименован из `cliphist.service`) |
| `files/home/.config/systemd/user/cliphist-images.service` | История буфера изображений |
| `update.sh` | Комплексное обновление: pacman → yay → orphans → daemon-reload → валидация |
| `make update` | Новая цель в Makefile |
| `50-binds.kdl` | Добавлены: `Mod+F`, `Mod+Shift+F`, `Mod+C`, `Mod+R`, `Mod+±`, медиаклавиши, `Mod+V` (cliphist picker), `Mod+Print` (полный скриншот) |

### Примечание по SSH

Перед деплоем убедись что `amar`, `wn75`, `ui` резолвятся:

```
# /etc/hosts
192.168.1.100  amar
192.168.1.101  wn75
192.168.1.110  ui
```

---

## Waybar vs Noctalia

В репо оба варианта. По умолчанию запускается **waybar** (через `40-startup.kdl`).

**Переключиться на noctalia:**
```bash
# Убрать waybar из автозапуска — закомментировать строку в 40-startup.kdl:
# spawn-at-startup "waybar"

# Включить noctalia service:
systemctl --user enable --now noctalia.service

# Перезагрузить niri конфиг:
niri msg action reload-config
```

**Вернуться на waybar:**
```bash
systemctl --user disable --now noctalia.service
# Раскомментировать spawn-at-startup "waybar" в 40-startup.kdl
niri msg action reload-config
```

## Настройка waybar

Если `#temperature` не показывает температуру — найди нужный hwmon:
```bash
for f in /sys/class/hwmon/hwmon*/temp1_input; do
  echo "$f: $(cat $f)"
done
```
Затем укажи явно в `config.jsonc`:
```json
"temperature": {
  "hwmon-path": "/sys/class/hwmon/hwmon2/temp1_input",
  ...
}
```

Если `#language` показывает не то — проверь:
```bash
niri msg event-stream | grep keyboard
```

## Установка

```bash
git clone <YOUR_REPO_URL> arch-niri-noctalia
cd arch-niri-noctalia
chmod +x *.sh
make install
sudo reboot
```

## Цели Makefile

| Команда | Действие |
|---------|----------|
| `make install` | Полная установка с нуля |
| `make check` | Post-install проверка всех компонентов |
| `make sync` | Синхронизация конфигов из репо в систему |
| `make update` | Обновление системы (pacman + yay + orphans) |
| `make logs` | Просмотр логов всех сервисов |
| `make backup` | Резервная копия конфигов |
| `make dots-local` | Деплой только `.bashrc` и `.ssh/config` |
| `make validate` | Валидация niri config |
| `make reload` | Reload niri config без перезапуска |

## Структура репозитория

```
arch-niri-noctalia/
├── Makefile
├── install.sh
├── post-install-check.sh
├── sync.sh
├── update.sh                          ← NEW
├── logs.sh
├── backup.sh
├── bootstrap-dotfiles.sh
└── files/
    ├── etc/greetd/config.toml
    └── home/
        ├── .bashrc
        ├── .ssh/config
        └── .config/
            ├── niri/
            │   ├── config.kdl
            │   └── conf.d/
            │       ├── 10-input.kdl
            │       ├── 20-layout.kdl
            │       ├── 30-environment.kdl
            │       ├── 40-startup.kdl
            │       ├── 50-binds.kdl   ← расширен
            │       └── keymap.xkb
            ├── alacritty          ← NEW
            ├── swaylock/config        ← NEW
            ├── waybar/
            │   ├── config.jsonc       ← NEW
            │   └── style.css          ← NEW
            ├── mako/config
            ├── fuzzel/fuzzel.ini
            ├── qt6ct/qt6ct.conf
            ├── gtk-3.0/settings.ini
            ├── gtk-4.0/settings.ini
            └── systemd/user/
                ├── noctalia.service
                ├── swayidle.service
                ├── cliphist-text.service    ← переименован
                └── cliphist-images.service  ← NEW
```
