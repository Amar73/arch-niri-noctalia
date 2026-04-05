# ArchLinux — Installation guide

### https://wiki.archlinux.org/title/Installation_guide_(Русский)

---

## Создание загрузочного USB

**Важно:** Это уничтожит безвозвратно все файлы на `/dev/sdx`. Чтобы восстановить USB-накопитель
после использования ISO-образа, удали подпись файловой системы:
`wipefs --all /dev/sdx`

```bash
dd bs=4M if=путь/до/archlinux.iso of=/dev/sdx status=progress oflag=sync
```

---

## Загрузка live-окружения

**Примечание:** Установочные образы Arch Linux не поддерживают Secure Boot —
необходимо отключить его в BIOS/UEFI перед загрузкой.

1. Загрузи компьютер с установочного носителя.
2. В меню выбери *Arch Linux install medium* → `Enter`.
3. После загрузки попадёшь в консоль Zsh от пользователя root.

Для переключения между виртуальными консолями в процессе установки: `Alt+←→`.
Для редактирования файлов: `mcedit`, `nano`, `vim`.

---

## Установка раскладки клавиатуры и шрифта

```bash
# Список доступных раскладок
localectl list-keymaps

# Загрузить русскую раскладку (Ctrl+Shift для переключения EN/RU)
loadkeys ru

# Шрифт с кириллицей для стандартного экрана
setfont cyr-sun16

# Шрифт для HiDPI
setfont ter-c32b
```

---

## Проверка режима загрузки

```bash
cat /sys/firmware/efi/fw_platform_size
# 64 → UEFI 64-bit (рекомендуется)
# 32 → UEFI 32-bit
# файл не существует → BIOS/Legacy
```

---

## Соединение с интернетом

### Ethernet

Подключи кабель — DHCP заработает автоматически. Проверь:

```bash
ip link                 # убедиться что интерфейс UP
ping -c 3 archlinux.org
```

### Wi-Fi (iwctl)

Live-окружение использует `iwd` для Wi-Fi. Подключение через интерактивную оболочку `iwctl`:

```bash
# Запустить iwctl
iwctl
```

Внутри оболочки `[iwd]#`:

```
# 1. Узнать имя беспроводного интерфейса (обычно wlan0)
device list

# 2. Если интерфейс выключен — включить
device wlan0 set-property Powered on

# 3. Запустить сканирование сетей
station wlan0 scan

# 4. Показать найденные сети
station wlan0 get-networks

# 5. Подключиться к нужной сети (введёт пароль интерактивно)
station wlan0 connect "ИМЯ_СЕТИ"

# 6. Проверить статус подключения
station wlan0 show

# 7. Выйти из iwctl
quit
```

Если адаптер заблокирован (rfkill):

```bash
# Проверить блокировку
rfkill list

# Разблокировать всё
rfkill unblock all

# Затем снова запустить iwctl
iwctl
```

Проверить соединение:

```bash
ping -c 3 archlinux.org
```


## Синхронизация системных часов

```bash
timedatectl set-ntp true
timedatectl status
```

---

## Разметка дисков

```bash
# Список всех дисков
fdisk -l

# Разметить диск
fdisk /dev/диск_для_разметки
```

### Рекомендуемые схемы разделов

**UEFI:**

| Точка монтирования | Раздел | Тип | Размер |
|--------------------|--------|-----|--------|
| `/boot/efi` | `/dev/sda1` | EFI System | 1 ГиБ |
| `[SWAP]` | `/dev/sda2` | Linux swap | ≥ 4 ГиБ |
| `/` | `/dev/sda3` | Linux x86-64 root | остаток, ≥ 32 ГиБ |

**BIOS/Legacy:**

| Точка монтирования | Раздел | Тип | Размер |
|--------------------|--------|-----|--------|
| `[SWAP]` | `/dev/sda1` | Linux swap | ≥ 4 ГиБ |
| `/` | `/dev/sda2` | Linux | остаток, ≥ 32 ГиБ |

---

## Моя конфигурация: два диска

**sda (SSD)** — boot, swap, root  
**sdb (HDD)** — home, data

⚠️ **Форматируем только `/dev/sda1` (EFI) и `/dev/sda3` (root).**  
`/dev/sdb1` и `/dev/sdb2` не трогаем — там живые данные.

```bash
# Форматирование (только для чистой установки)
mkfs.fat -F 32 /dev/sda1   # EFI раздел
mkswap /dev/sda2            # swap
mkfs.ext4 /dev/sda3         # root

# Активация swap
swapon /dev/sda2

# Монтирование root
mount /dev/sda3 /mnt

# Монтирование EFI
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

# Монтирование home (данные сохраняются — не форматируем!)
mkdir -p /mnt/home
mount /dev/sdb1 /mnt/home

# Монтирование раздела с данными
mkdir -p /mnt/data
mount /dev/sdb2 /mnt/data
```

Проверка:

```bash
lsblk -f
findmnt -R /mnt
```

---

## Выбор зеркал

```bash
# Опционально — переместить географически близкие зеркала выше в файле
vim /etc/pacman.d/mirrorlist

# Или использовать reflector для автоматического выбора быстрых зеркал
reflector --country Russia,Germany --sort rate --save /etc/pacman.d/mirrorlist
```

---

## Установка базовой системы

```bash
pacstrap -K /mnt \
  base linux linux-firmware \
  sudo vim git github-cli \
  base-devel \
  networkmanager \
  man-db man-pages texinfo \
  dbus polkit \
  inetutils openssh \
  mc
```

- `linux` — можно заменить на `linux-lts` для стабильности
- `mc` — Midnight Commander, удобен при работе в консоли после установки

---

## Настройка системы

### Fstab

```bash
genfstab -U /mnt >> /mnt/etc/fstab
vim /mnt/etc/fstab
```

Проверь что:
- `/dev/sda3` → `/`
- `/dev/sda1` → `/boot/efi`
- `/dev/sda2` → `swap`
- `/dev/sdb1` → `/home`
- `/dev/sdb2` → `/data` с опциями `defaults,noatime`

Пример строки для `/data`:
```
UUID=xxxx-xxxx  /data  ext4  defaults,noatime  0 2
```

Все UUID проверить через `blkid`.

---

### Chroot

```bash
arch-chroot /mnt /bin/bash
```

---

### Часовой пояс

```bash
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
```

---

### Локализация

```bash
# Раскомментировать нужные локали
vim /etc/locale.gen
```

Раскомментировать:
```
en_US.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
```

```bash
locale-gen
```

Создать `/etc/locale.conf`:

**Вариант А — английский интерфейс системы и приложений:**
```ini
LANG=en_US.UTF-8
LC_TIME=ru_RU.UTF-8
LC_COLLATE=C
```

**Вариант Б — русский интерфейс системы и приложений** (рекомендуется если
планируешь использовать русскоязычные программы — Яндекс.Браузер, LibreOffice и др.):
```ini
LANG=ru_RU.UTF-8
LC_COLLATE=C
```

> `LC_COLLATE=C` ускоряет сортировку в терминале и избегает проблем с регистром.

> **Важно:** `LANG` в `/etc/locale.conf` определяет язык интерфейса всех
> приложений. Если приложение отображается на английском вместо русского —
> первым делом проверь этот файл.

Создать `/etc/vconsole.conf`:
```ini
KEYMAP=us
FONT=cyr-sun16
```

> Используй `KEYMAP=us`, не `ru` — иначе в TTY не будет работать переключение раскладок.

---

### Настройка сети

`/etc/hostname`:
```
имявашегохоста
```

`/etc/hosts`:
```
127.0.0.1   localhost
::1         localhost
127.0.1.1   myhostname.localdomain myhostname
```

```bash
systemctl enable NetworkManager
systemctl enable dbus
```

Имя хоста: 1–63 символа, только строчные `a–z`, цифры `0–9` и дефис `-`.
Дефис не должен быть первым символом.

---

### Initramfs

Обычно пересборка не нужна — `mkinitcpio` запускается автоматически при установке ядра.
Если используешь LVM, шифрование или RAID:

```bash
mkinitcpio -P
```

---

### Пароль root и создание пользователя

```bash
passwd                          # пароль root

useradd -m -G wheel,audio,video,storage,power -s /bin/bash username
passwd username

# Разрешить sudo для группы wheel
EDITOR=vim visudo
# Раскомментировать строку: %wheel ALL=(ALL:ALL) ALL
```

> Группы `video` и `audio` нужны для доступа к устройствам без sudo.

---

### Загрузчик UEFI: GRUB + микрокод

```bash
pacman -S --needed grub efibootmgr dosfstools os-prober

# Микрокод — ОБЯЗАТЕЛЕН для стабильности
pacman -S --needed intel-ucode
# Для AMD:
# pacman -S --needed amd-ucode

# Установка GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg
```

`os-prober` автоматически найдёт другие ОС.
Микрокод подхватится в `grub.cfg` автоматически.

---

### Перезагрузка

```bash
exit              # выйти из chroot
umount -R /mnt    # размонтировать все разделы
reboot            # извлечь USB перед перезагрузкой
```

---

## После первого входа

```bash
# Проверить сеть
ping -c2 archlinux.org

# Установить yay (AUR helper)
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay && makepkg -si

# Клонировать репозиторий конфигов
mkdir -p ~/Amar73
cd ~/Amar73
git clone https://github.com/Amar73/arch-niri.git
cd arch-niri
chmod +x *.sh
make check-local
make install
```
