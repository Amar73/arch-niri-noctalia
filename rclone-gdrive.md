# rclone Google Drive — Production Mount на Arch Linux

> Tested on Arch Linux + systemd. Никаких GUI, только терминал и здравый смысл.

## Конфигурация этой машины

```
/dev/sdb2  1.3T  /data          — HDD, здесь живут данные и точка монтирования
/data/Googl.Drive               — точка монтирования Google Drive
~/Googl.Drive -> /data/Googl.Drive  — симлинк для удобного доступа
~/.cache/rclone/gdrive          — VFS кэш (на SSD root, до 5G)
~/.local/log/                   — логи
```

---

## 1. Установка

```bash
sudo pacman -S rclone fuse2
```

> `fuse2` — нужен для `--allow-other`. Именно `fuse2`, не `fuse3`.

Проверь версию (должна быть ≥ 1.60):

```bash
rclone version
```

---

## 2. FUSE: разрешить монтирование другими пользователями

Без этого `--allow-other` молча падает.

```bash
sudo nano /etc/fuse.conf
```

Раскомментировать строку:

```
user_allow_other
```

---

## 3. Авторизация в Google Drive

```bash
rclone config
```

Пошагово:

```
n  → новый remote
name: gdrive
type: drive
client_id:           (Enter — использовать встроенный)
client_secret:       (Enter)
scope: 1             → полный доступ к диску
root_folder_id:      (Enter)
service_account_file:(Enter)
Edit advanced config? n
Use auto config? y   → откроется браузер, авторизуйся
Configure as Shared Drive? n
```

Проверка:

```bash
rclone lsd gdrive:
```

---

## 4. Подготовка директорий

```bash
# Точка монтирования на HDD (уже существует)
sudo mkdir -p /data/Googl.Drive
sudo chown amar:amar /data/Googl.Drive

# Симлинк из домашней директории (уже существует)
# ln -s /data/Googl.Drive ~/Googl.Drive

# VFS кэш — на SSD (root), лимит 5G
mkdir -p ~/.cache/rclone/gdrive

# Логи
mkdir -p ~/.local/log
```

---

## 5. Systemd user service

```bash
mkdir -p ~/.config/systemd/user
nano ~/.config/systemd/user/rclone-gdrive.service
```

```ini
[Unit]
Description=Rclone Google Drive Mount
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

# Создать точку монтирования если нет
ExecStartPre=/bin/mkdir -p /data/Googl.Drive

ExecStart=/usr/bin/rclone mount gdrive: /data/Googl.Drive \
  --config         %h/.config/rclone/rclone.conf \
  \
  --vfs-cache-mode      full \
  --vfs-cache-max-size  5G \
  --vfs-cache-max-age   12h \
  --vfs-read-chunk-size 128M \
  --cache-dir           %h/.cache/rclone/gdrive \
  \
  --dir-cache-time      72h \
  --poll-interval       30s \
  \
  --drive-chunk-size    128M \
  --drive-acknowledge-abuse \
  \
  --allow-other \
  --umask 022 \
  \
  --transfers   8 \
  --checkers    16 \
  --buffer-size 512M \
  --bwlimit     50M \
  \
  --log-level   INFO \
  --log-file    %h/.local/log/rclone-gdrive.log

ExecStop=/bin/fusermount -u /data/Googl.Drive

Restart=on-failure
RestartSec=30
StartLimitIntervalSec=300
StartLimitBurst=5

MemoryMax=1G
CPUQuota=50%

[Install]
WantedBy=default.target
```

---

## 6. Активация

```bash
systemctl --user daemon-reload
systemctl --user enable --now rclone-gdrive.service
```

Проверка:

```bash
systemctl --user status rclone-gdrive.service
ls ~/Googl.Drive
```

---

## 7. Ротация логов

```bash
nano ~/.config/logrotate-user.conf
```

```
/home/amar/.local/log/rclone-gdrive.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
```

Добавь в crontab:

```bash
crontab -e
```

```
0 4 * * * /usr/sbin/logrotate /home/amar/.config/logrotate-user.conf
```

---

## 8. Health-check скрипт

```bash
mkdir -p ~/bin
nano ~/bin/gdrive-check.sh
chmod +x ~/bin/gdrive-check.sh
```

```bash
#!/usr/bin/env bash
MOUNT="/data/Googl.Drive"
LOG="$HOME/.local/log/rclone-gdrive.log"
SERVICE="rclone-gdrive.service"

if ! mountpoint -q "$MOUNT"; then
    echo "[$(date '+%F %T')] WARN: $MOUNT не смонтирован. Перезапускаю..." | tee -a "$LOG"
    systemctl --user restart "$SERVICE"
    sleep 10
fi

if ! ls "$MOUNT" &>/dev/null; then
    echo "[$(date '+%F %T')] ERROR: ls $MOUNT завис. Форсирую unmount + restart..." | tee -a "$LOG"
    fusermount -u "$MOUNT" 2>/dev/null || true
    systemctl --user restart "$SERVICE"
fi

echo "[$(date '+%F %T')] OK: $MOUNT доступен."
```

Добавь в crontab:

```
*/15 * * * * ~/bin/gdrive-check.sh >> ~/.local/log/gdrive-check.log 2>&1
```

---

## 9. Параметры: что и зачем

| Параметр | Значение | Смысл |
|---|---|---|
| `--vfs-cache-mode full` | full | Полный кэш: чтение + запись без тормозов seek |
| `--vfs-cache-max-size` | 5G | Лимит VFS кэша на SSD (root-разделе) |
| `--vfs-cache-max-age` | 12h | Протухание кэша |
| `--vfs-read-chunk-size` | 128M | Чанк чтения, ускоряет большие файлы |
| `--cache-dir` | `~/.cache/rclone/gdrive` | VFS кэш на SSD — быстрее чем HDD |
| `--drive-chunk-size` | 128M | Чанк загрузки на Drive |
| `--buffer-size` | 512M | RAM-буфер между mount и сетью |
| `--transfers` | 8 | Параллельные передачи |
| `--checkers` | 16 | Параллельные проверки метаданных |
| `--bwlimit` | 50M | Лимит пропускной способности |
| `--poll-interval` | 30s | Как часто проверять изменения на Drive |
| `--dir-cache-time` | 72h | Кэш списков директорий |
| `--allow-other` | — | Доступ к mount другим пользователям/процессам |
| `--umask 022` | — | Права на файлы: 644/755 |

> **Почему `--cache-dir` на SSD, а mount на HDD:**  
> VFS кэш — это рабочий буфер для активных файлов (seek, random write).  
> Ему нужна скорость → SSD (`~/.cache/`).  
> Смонтированный Drive — это холодное хранилище → HDD (`/data/`).

---

## 10. Тюнинг под сценарий

### Медленный интернет / лимит трафика

```bash
--bwlimit       5M
--transfers     2
--checkers      4
--buffer-size   64M
--vfs-cache-mode writes
```

### Большие медиафайлы (видео, архивы)

```bash
--vfs-read-chunk-size        256M
--vfs-read-chunk-size-limit  0
--drive-chunk-size           256M
--buffer-size                1G
--bwlimit                    0
```

### Только резервное копирование (без mount)

```bash
rclone sync /local/path gdrive:Backups \
  --transfers 8 \
  --drive-chunk-size 128M \
  --progress \
  --log-file ~/.local/log/rclone-sync.log
```

---

## 11. Шифрование (опционально)

Если в Drive лежат приватные данные — оберни в `crypt` remote:

```bash
rclone config
```

```
n → новый remote
name: gdrive-crypt
type: crypt
remote: gdrive:Encrypted
filename_encryption: standard
directory_name_encryption: true
password: (задай надёжный пароль)
```

Используй `gdrive-crypt:` вместо `gdrive:` в service файле.  
Файлы на диске будут нечитаемы без пароля.

---

## 12. Двусторонняя синхронизация (bisync)

Для сценария «работаю локально, синхронизирую с Drive»:

```bash
# Первый запуск — обязательно с --resync
rclone bisync ~/Documents/Sync gdrive:Sync \
  --resync \
  --drive-chunk-size 128M \
  --progress

# Последующие запуски
rclone bisync ~/Documents/Sync gdrive:Sync \
  --drive-chunk-size 128M \
  --log-file ~/.local/log/rclone-bisync.log
```

В crontab:

```
0 */2 * * * /usr/bin/rclone bisync ~/Documents/Sync gdrive:Sync \
  --drive-chunk-size 128M >> ~/.local/log/rclone-bisync.log 2>&1
```

---

## 13. Диагностика

```bash
# Статус service
systemctl --user status rclone-gdrive.service

# Живой хвост лога
tail -f ~/.local/log/rclone-gdrive.log

# Смонтировано?
mountpoint /data/Googl.Drive

# Доступно через симлинк?
ls ~/Googl.Drive

# Кэш (на SSD)
du -sh ~/.cache/rclone/gdrive

# Принудительный unmount (если завис)
fusermount -u /data/Googl.Drive

# Жёсткий unmount
sudo umount -l /data/Googl.Drive
```

---

## Итоговый чеклист

- [ ] `fuse.conf` → `user_allow_other` раскомментирован
- [ ] `rclone config` → remote `gdrive` создан и проверен (`rclone lsd gdrive:`)
- [ ] Директории: `/data/Googl.Drive`, `~/.cache/rclone/gdrive`, `~/.local/log`
- [ ] Симлинк `~/Googl.Drive → /data/Googl.Drive` существует
- [ ] `rclone-gdrive.service` создан и активирован
- [ ] `logrotate` настроен
- [ ] `gdrive-check.sh` в crontab каждые 15 минут
- [ ] (опц.) `crypt` remote для приватных данных
- [ ] (опц.) `bisync` для двусторонней синхронизации

---

*Если что-то не стартует — сначала `journalctl --user -u rclone-gdrive.service -n 50`, потом уже паника.*