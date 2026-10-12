#!/bin/bash
# ORRT Fedora Installer
set -e

echo "Installing ORRT for Fedora..."

# 1. Проверка и установка пакетов
echo "[1/5] Установка системных зависимостей (Wine, Python, Curl, Unzip)..."
sudo dnf install -y wine wine-dxvk python3 curl unzip libnotify xdg-utils

# 2. Создание папки для запускающего скрипта
echo "[2/5] Создание скрипта запуска..."
mkdir -p "$HOME/bin"
mkdir -p "$HOME/.cache"
mkdir -p "$HOME/.local/share/applications"

LAUNCHER_SCRIPT="$HOME/bin/orrt-player-linux"

cat << '__ORRT_LAUNCHER_EOF__' > "$LAUNCHER_SCRIPT"
#!/bin/bash
LOG_FILE="$HOME/.cache/orrt-launcher.log"
mkdir -p "$HOME/.cache"

RAW_URI="$1"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching ORRT with URI: $RAW_URI" >> "$LOG_FILE"

if command -v notify-send >/dev/null 2>&1; then
    notify-send "ORRT" "Запуск игры..." -i "applications-games" 2>/dev/null || true
fi

# Извлекаем параметры из URI
eval "$(python3 -c '
import urllib.parse, sys, shlex

raw = sys.argv[1] if len(sys.argv) > 1 else ""
unquoted = urllib.parse.unquote(raw)

parts = unquoted.split("+")
ticket = ""
client_ver = "2017L"
placelauncher = ""

for part in parts:
    if part.startswith("gameinfo:"):
        ticket = part[len("gameinfo:"):]
    elif part.startswith("clientversion:"):
        client_ver = part[len("clientversion:"):]
    elif part.startswith("placelauncherurl:"):
        placelauncher = part[len("placelauncherurl:"):]

if not placelauncher:
    placelauncher = "http://oldrrt.xyz/Game/PlaceLauncher.ashx"

placelauncher = (placelauncher
    .replace("https://www.roblox.com", "http://oldrrt.xyz")
    .replace("http://www.roblox.com", "http://oldrrt.xyz")
    .replace("https://roblox.com", "http://oldrrt.xyz")
    .replace("http://roblox.com", "http://oldrrt.xyz")
    .replace("https://oldrrt.xyz", "http://oldrrt.xyz"))

p = urllib.parse.urlparse(placelauncher)
base_url = f"http://{p.netloc}" if p.netloc else "http://oldrrt.xyz"

print(f"TICKET={shlex.quote(ticket)}")
print(f"CLIENT_VER={shlex.quote(client_ver)}")
print(f"PLACELAUNCHER={shlex.quote(placelauncher)}")
print(f"BASE_URL={shlex.quote(base_url)}")
' "$RAW_URI")"

AUTH_URL="${BASE_URL}/Login/Negotiate.ashx"

echo "[*] Auth Ticket: $TICKET" >> "$LOG_FILE"
echo "[*] Base URL: $BASE_URL" >> "$LOG_FILE"
echo "[*] Client Version: $CLIENT_VER" >> "$LOG_FILE"
echo "[*] PlaceLauncher: $PLACELAUNCHER" >> "$LOG_FILE"

WINE_PREFIX="${WINEPREFIX:-$HOME/.wine}"
CURRENT_USER="$(whoami)"
CLIENT_DIR="$WINE_PREFIX/drive_c/users/$CURRENT_USER/AppData/Local/ORRT/Versions/v1.0.0/$CLIENT_VER"

if [ ! -d "$CLIENT_DIR" ] || [ ! -f "$CLIENT_DIR/RobloxPlayerBeta.exe" -a ! -f "$CLIENT_DIR/ProjectXPlayerBeta.exe" ]; then
    echo "[*] Клиент $CLIENT_VER не найден, скачиваем..." >> "$LOG_FILE"
    mkdir -p "$CLIENT_DIR"
    TEMP_ZIP="/tmp/orrt_${CLIENT_VER}.zip"
    curl -sSL "${BASE_URL}/download/client/${CLIENT_VER}" -o "$TEMP_ZIP" || curl -sSL "http://oldrrt.xyz/download/client/2017L" -o "$TEMP_ZIP"
    unzip -q -o "$TEMP_ZIP" -d "$CLIENT_DIR"
    rm -f "$TEMP_ZIP"
fi

ROBLOX_EXE=""
if [ -f "$CLIENT_DIR/RobloxPlayerBeta.exe" ]; then
    ROBLOX_EXE="$CLIENT_DIR/RobloxPlayerBeta.exe"
elif [ -f "$CLIENT_DIR/ProjectXPlayerBeta.exe" ]; then
    ROBLOX_EXE="$CLIENT_DIR/ProjectXPlayerBeta.exe"
else
    ROBLOX_EXE=$(find "$WINE_PREFIX/drive_c" -type f \( -iname "RobloxPlayerBeta.exe" -o -iname "ProjectXPlayerBeta.exe" \) 2>/dev/null | head -n 1)
fi

CLIENT_DIR="$(dirname "$ROBLOX_EXE")"
cd "$CLIENT_DIR"

printf '<Settings><ContentFolder>content</ContentFolder><BaseUrl>%s/</BaseUrl></Settings>' "${BASE_URL%/}" > "$CLIENT_DIR/AppSettings.xml"

mkdir -p "$CLIENT_DIR/ClientSettings"
printf '{\n\t"BaseUrl": "%s/",\n\t"DFIntTaskSchedulerTargetFps": 180\n}\n' "$BASE_URL" > "$CLIENT_DIR/ClientSettings/ClientAppSettings.json"

export DISPLAY="${DISPLAY:-:0}"
export WINEDLLOVERRIDES="advapi32=n,b"

setsid nohup wine "$ROBLOX_EXE" --app -a "$AUTH_URL" -t "$TICKET" -j "$PLACELAUNCHER" >> "$LOG_FILE" 2>&1 </dev/null &
__ORRT_LAUNCHER_EOF__

chmod +x "$LAUNCHER_SCRIPT"

# 3. Создание ассоциации протокола в системе (.desktop)
echo "[3/5] Регистрация протокола orrt-player в системе..."
DESKTOP_FILE="$HOME/.local/share/applications/orrt-player.desktop"

cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=ORRT Player
Exec=$LAUNCHER_SCRIPT %u
Type=Application
MimeType=x-scheme-handler/orrt-player;x-scheme-handler/orrt-studio;x-scheme-handler/pekora-player;x-scheme-handler/pekora2-player;
NoDisplay=true
Categories=Game;
EOF

xdg-mime default orrt-player.desktop x-scheme-handler/orrt-player
xdg-mime default orrt-player.desktop x-scheme-handler/pekora-player
xdg-mime default orrt-player.desktop x-scheme-handler/pekora2-player
xdg-mime default orrt-player.desktop x-scheme-handler/orrt-studio
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true

# 4. Предварительная загрузка клиента игры
echo "[4/5] Скачивание и распаковка файлов игры (2017L)..."
CURRENT_USER="$(whoami)"
TARGET_DIR="$HOME/.wine/drive_c/users/$CURRENT_USER/AppData/Local/ORRT/Versions/v1.0.0/2017L"
mkdir -p "$TARGET_DIR"

if [ ! -f "$TARGET_DIR/RobloxPlayerBeta.exe" ]; then
    echo "    Загрузка архива клиента (~95 МБ)..."
    curl -L --progress-bar "https://oldrrt.xyz/download/client/2017L" -o "/tmp/orrt_2017L.zip"
    echo "    Распаковка..."
    unzip -q -o "/tmp/orrt_2017L.zip" -d "$TARGET_DIR"
    rm -f "/tmp/orrt_2017L.zip"
    echo "    Клиент успешно установлен в $TARGET_DIR"
else
    echo "    Клиент уже скачан, пропускаем."
fi

# 5. Инициализация Wine (если ещё не создан префикс)
echo "[5/5] Проверка Wine окружения..."
wineboot -u 2>/dev/null || true

echo "Installation complete!"
