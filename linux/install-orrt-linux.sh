#!/bin/bash
# ORRT Linux Installer
set -e

echo "Installing ORRT for Linux..."
echo "[1/6] Проверка и установка зависимостей (Wine, Python, gcc, curl, unzip)..."

if command -v dnf >/dev/null 2>&1; then
    echo "Обнаружен пакетный менеджер DNF (Fedora / RHEL)..."
    sudo dnf install -y wine python3 gcc curl unzip libnotify xdg-utils
elif command -v apt-get >/dev/null 2>&1; then
    echo "Обнаружен пакетный менеджер APT (Ubuntu / Debian / Linux Mint)..."
    sudo apt-get update -y
    sudo dpkg --add-architecture i386 2>/dev/null || true
    sudo apt-get install -y wine python3 gcc curl unzip libnotify-bin xdg-utils 2>/dev/null \
        || sudo apt-get install -y wine python3 gcc curl unzip libnotify-bin xdg-utils
elif command -v pacman >/dev/null 2>&1; then
    echo "Обнаружен пакетный менеджер Pacman (Arch / Manjaro / EndeavourOS)..."
    sudo pacman -S --noconfirm --needed wine python gcc curl unzip libnotify xdg-utils
elif command -v zypper >/dev/null 2>&1; then
    echo "Обнаружен пакетный менеджер Zypper (openSUSE)..."
    sudo zypper install -y wine python3 gcc curl unzip libnotify-tools xdg-utils
elif command -v wine >/dev/null 2>&1; then
    echo "Wine уже установлен в системе, продолжаем..."
else
    echo "Внимание: не удалось определить пакетный менеджер."
    echo "Установи Wine, Python3, GCC вручную, затем перезапусти скрипт."
    exit 1
fi

# Clean hosts
if grep -qE "roblox\.com|rbxcdn\.com|pekora\.rip|oldrrt\.xyz" /etc/hosts 2>/dev/null; then
    echo "[*] Очистка /etc/hosts от устаревших записей..."
    sudo sed -i '/roblox\.com/d; /rbxcdn\.com/d; /pekora\.rip/d; /oldrrt\.xyz/d' /etc/hosts 2>/dev/null || true
    echo "    [+] /etc/hosts очищен от сторонних записей."
fi

# Build DNS interceptor
echo "[2/6] Сборка модуля перехвата DNS (liborrt_hosts.so)..."
mkdir -p "$HOME/.cache/orrt/lib"

cat << 'HOOK_EOF' > "$HOME/.cache/orrt/lib/hosts_redirect.c"
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <netdb.h>

static int (*real_getaddrinfo)(const char*,const char*,const struct addrinfo*,struct addrinfo**) = NULL;
static int (*real_gethostbyname_r)(const char*,struct hostent*,char*,size_t,struct hostent**,int*) = NULL;
static struct hostent *(*real_gethostbyname)(const char*) = NULL;

static int should_redirect(const char *name) {
    if (!name) return 0;
    return (strstr(name, "roblox.com") || strstr(name, "rbxcdn.com") ||
            strstr(name, "oldrrt.xyz") || strstr(name, "orrt.online") ||
            strstr(name, "pekora.rip") || strstr(name, "pekora.zip") ||
            strstr(name, "projex.zip")) ? 1 : 0;
}

int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    if (!real_getaddrinfo) real_getaddrinfo = dlsym(RTLD_NEXT, "getaddrinfo");
    return real_getaddrinfo(should_redirect(node) ? "74.248.20.23" : node, service, hints, res);
}

int gethostbyname_r(const char *name, struct hostent *ret, char *buf, size_t buflen, struct hostent **result, int *h_errnop) {
    if (!real_gethostbyname_r) real_gethostbyname_r = dlsym(RTLD_NEXT, "gethostbyname_r");
    return real_gethostbyname_r(should_redirect(name) ? "74.248.20.23" : name, ret, buf, buflen, result, h_errnop);
}

struct hostent *gethostbyname(const char *name) {
    if (!real_gethostbyname) real_gethostbyname = dlsym(RTLD_NEXT, "gethostbyname");
    return real_gethostbyname(should_redirect(name) ? "74.248.20.23" : name);
}
HOOK_EOF

if gcc -O2 -fPIC -shared -o "$HOME/.cache/orrt/lib/liborrt_hosts.so" \
       "$HOME/.cache/orrt/lib/hosts_redirect.c" -ldl 2>/dev/null; then
    echo "    [+] liborrt_hosts.so успешно скомпилирован."
else
    echo "    [!] Предупреждение: не удалось скомпилировать liborrt_hosts.so."
fi

# 3. Create launcher script
echo "[3/6] Создание скрипта запуска..."
mkdir -p "$HOME/bin"
mkdir -p "$HOME/.local/share/applications"

LAUNCHER_SCRIPT="$HOME/bin/orrt-player-linux"

python3 << 'PYEOF'
import os, sys

launcher = r"""#!/bin/bash
# ORRT Player/Studio Linux Launcher v2.0
LOG_FILE="$HOME/.cache/orrt-launcher.log"
mkdir -p "$HOME/.cache/orrt/lib"

RAW_URI="$1"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching ORRT with URI: $RAW_URI" >> "$LOG_FILE"

eval "$(python3 -c '
import urllib.parse, sys, shlex
raw = sys.argv[1] if len(sys.argv) > 1 else ""
clean = raw.strip().strip("\"'\''")
colon_idx = clean.find(":")
body = clean[colon_idx+1:] if colon_idx >= 0 else clean
parts = body.split("+")
current_key = None
current_tokens = []
res = {"ticket": "", "client_ver": "2017L", "placelauncher": "", "launchmode": "play", "place_id": ""}
def flush():
    global current_key, current_tokens
    if not current_key: return
    val = "+".join(current_tokens)
    if current_key in ("gameinfo", "ticket"): res["ticket"] = val
    elif current_key in ("clientversion", "client"): res["client_ver"] = val
    elif current_key == "placelauncherurl": res["placelauncher"] = val
    elif current_key == "launchmode": res["launchmode"] = val
    elif current_key == "placeid": res["place_id"] = val
known = {"clientversion", "gameinfo", "placelauncherurl", "launchmode", "placeid", "ticket", "k", "suggest", "client"}
for part in parts:
    c = part.find(":")
    if c > 0 and part[:c].lower() in known:
        flush()
        current_key = part[:c].lower()
        current_tokens = [part[c+1:]]
    elif current_key:
        current_tokens.append(part)
flush()
ticket = urllib.parse.unquote(res["ticket"]) if res["ticket"] else ""
client_ver = res["client_ver"] or "2017L"
placelauncher = urllib.parse.unquote(res["placelauncher"]) if res["placelauncher"] else "http://oldrrt.xyz/Game/PlaceLauncher.ashx"
placelauncher = (placelauncher
    .replace("https://www.roblox.com","http://oldrrt.xyz")
    .replace("http://www.roblox.com","http://oldrrt.xyz")
    .replace("https://roblox.com","http://oldrrt.xyz")
    .replace("http://roblox.com","http://oldrrt.xyz")
    .replace("https://oldrrt.xyz","http://oldrrt.xyz"))
p = urllib.parse.urlparse(placelauncher)
base_url = f"http://{p.netloc}" if p.netloc else "http://oldrrt.xyz"
print(f"TICKET={shlex.quote(ticket)}")
print(f"CLIENT_VER={shlex.quote(client_ver)}")
print(f"PLACELAUNCHER={shlex.quote(placelauncher)}")
print(f"BASE_URL={shlex.quote(base_url)}")
print(f"LAUNCH_MODE={shlex.quote(res[\"launchmode\"])}")
print(f"PLACE_ID={shlex.quote(res[\"place_id\"])}")
' "$RAW_URI")"

WINE_PREFIX="${WINEPREFIX:-$HOME/.wine}"
CURRENT_USER="$(whoami)"
export DISPLAY="${DISPLAY:-:0}"
HOOK_LIB="$HOME/.cache/orrt/lib/liborrt_hosts.so"

# Build DNS hook if missing
if [ ! -f "$HOOK_LIB" ]; then
    cat << 'HOOK_EOF' > "$HOME/.cache/orrt/lib/hosts_redirect.c"
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <netdb.h>
static int (*real_getaddrinfo)(const char*,const char*,const struct addrinfo*,struct addrinfo**) = NULL;
static int (*real_gethostbyname_r)(const char*,struct hostent*,char*,size_t,struct hostent**,int*) = NULL;
static struct hostent *(*real_gethostbyname)(const char*) = NULL;
static int should_redirect(const char *n) { return (n&&(strstr(n,"roblox.com")||strstr(n,"rbxcdn.com")||strstr(n,"oldrrt.xyz")||strstr(n,"orrt.online")||strstr(n,"pekora.rip")||strstr(n,"pekora.zip")||strstr(n,"projex.zip")))?1:0; }
int getaddrinfo(const char *node,const char *service,const struct addrinfo *hints,struct addrinfo **res){
    if(!real_getaddrinfo) real_getaddrinfo=dlsym(RTLD_NEXT,"getaddrinfo");
    return real_getaddrinfo(should_redirect(node)?"74.248.20.23":node,service,hints,res);}
int gethostbyname_r(const char *name,struct hostent *ret,char *buf,size_t buflen,struct hostent **result,int *h_errnop){
    if(!real_gethostbyname_r) real_gethostbyname_r=dlsym(RTLD_NEXT,"gethostbyname_r");
    return real_gethostbyname_r(should_redirect(name)?"74.248.20.23":name,ret,buf,buflen,result,h_errnop);}
struct hostent *gethostbyname(const char *name){
    if(!real_gethostbyname) real_gethostbyname=dlsym(RTLD_NEXT,"gethostbyname");
    return real_gethostbyname(should_redirect(name)?"74.248.20.23":name);}
HOOK_EOF
    gcc -O2 -fPIC -shared -o "$HOOK_LIB" "$HOME/.cache/orrt/lib/hosts_redirect.c" -ldl 2>/dev/null || true
fi

# ══════════════════════════════════════════════════════════════════════════════
# STUDIO (edit) mode
# ══════════════════════════════════════════════════════════════════════════════
if [ "$LAUNCH_MODE" = "edit" ]; then
    export WINEDLLOVERRIDES=""
    echo "[*] Edit mode for Place ID: $PLACE_ID" >> "$LOG_FILE"
    command -v notify-send >/dev/null 2>&1 && notify-send "ORRT" "Запуск Roblox Studio 2017..." -i applications-games 2>/dev/null || true

    STUDIO_DIR="$WINE_PREFIX/drive_c/users/$CURRENT_USER/AppData/Local/ORRT/Studio/$CLIENT_VER"
    if [ ! -f "$STUDIO_DIR/RobloxStudioBeta.exe" ]; then
        mkdir -p "$STUDIO_DIR"
        TEMP_ZIP="/tmp/orrt_studio_${CLIENT_VER}.zip"
        curl -sSL "${BASE_URL}/setup/v1.0.0-Studio${CLIENT_VER}.zip" -o "$TEMP_ZIP" \
            || curl -sSL "http://oldrrt.xyz/setup/v1.0.0-Studio${CLIENT_VER}.zip" -o "$TEMP_ZIP"
        unzip -q -o "$TEMP_ZIP" -d "$STUDIO_DIR"
        rm -f "$TEMP_ZIP"
    fi

    STUDIO_EXE="$STUDIO_DIR/RobloxStudioBeta.exe"
    if [ ! -f "$STUDIO_EXE" ]; then
        STUDIO_EXE=$(find "$WINE_PREFIX/drive_c" "$HOME/Downloads" -type f -iname "RobloxStudioBeta.exe" 2>/dev/null | head -n 1)
    fi
    if [ -z "$STUDIO_EXE" ] || [ ! -f "$STUDIO_EXE" ]; then
        command -v notify-send >/dev/null 2>&1 && notify-send "ORRT Studio" "Ошибка: Studio не найден!" -i dialog-error 2>/dev/null || true
        exit 1
    fi

    export LD_PRELOAD="$HOOK_LIB"
    STUDIO_ROOT="$(dirname "$STUDIO_EXE")"

    printf '<Settings><ContentFolder>content</ContentFolder><BaseUrl>http://oldrrt.xyz/</BaseUrl></Settings>' > "$STUDIO_ROOT/AppSettings.xml"
    mkdir -p "$STUDIO_ROOT/ClientSettings"
    printf '{\n  "BaseUrl": "http://oldrrt.xyz/",\n  "DFIntTaskSchedulerTargetFps": 180\n}\n' > "$STUDIO_ROOT/ClientSettings/ClientAppSettings.json"
    cp "$STUDIO_ROOT/ClientSettings/ClientAppSettings.json" "$STUDIO_ROOT/ClientSettings/StudioAppSettings.json" 2>/dev/null || true

    if [ -n "$TICKET" ]; then
        printf "# Netscape HTTP Cookie File\n.oldrrt.xyz\tTRUE\t/\tTRUE\t0\t.ROBLOSECURITY\t%s\noldrrt.xyz\tFALSE\t/\tTRUE\t0\t.ROBLOSECURITY\t%s\n" "$TICKET" "$TICKET" > "$STUDIO_ROOT/cookies.txt"
        wine rundll32.exe wininet.dll,InternetSetCookieA "https://oldrrt.xyz/" ".ROBLOSECURITY" "$TICKET" >/dev/null 2>&1 || true
        wine rundll32.exe wininet.dll,InternetSetCookieA "http://oldrrt.xyz/" ".ROBLOSECURITY" "$TICKET" >/dev/null 2>&1 || true
    fi

    USER_ID="1"; USER_NAME="Player"
    if [ -n "$TICKET" ]; then
        USER_INFO=$(curl -s -H "Cookie: .ROBLOSECURITY=${TICKET}" "${BASE_URL}/apisite/users/v1/users/authenticated" 2>/dev/null || echo "{}")
        USER_ID=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('id',1))" "$USER_INFO" 2>/dev/null || echo "1")
        USER_NAME=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('name','Player'))" "$USER_INFO" 2>/dev/null || echo "Player")
    fi
    echo "[*] Studio user: $USER_NAME (ID: $USER_ID)" >> "$LOG_FILE"

    PLUGINS_DIR="$WINE_PREFIX/drive_c/users/$CURRENT_USER/AppData/Local/Roblox/Plugins"
    mkdir -p "$PLUGINS_DIR"
    rm -f "$PLUGINS_DIR/test_plugin.lua" "$PLUGINS_DIR/ORRTPublisher.lua"

    python3 << PYEOF2
import sys, re, json, urllib.request

user_id = "$USER_ID"
user_name = "$USER_NAME"
place_id = "$PLACE_ID"
plugin_path = "$PLUGINS_DIR/ORRTCustomizer.lua"
base_url = "$BASE_URL"

try:
    req = urllib.request.Request(f"{base_url}/Asset/BodyColors.ashx?userId={user_id}", headers={"User-Agent":"Roblox/WinInet"})
    with urllib.request.urlopen(req) as r: bc_xml = r.read().decode("utf-8","ignore")
except: bc_xml = ""

try:
    req = urllib.request.Request(f"{base_url}/asset/CharacterFetch.ashx?userId={user_id}", headers={"User-Agent":"Roblox/WinInet"})
    with urllib.request.urlopen(req) as r: fetch_str = r.read().decode("utf-8","ignore")
except: fetch_str = ""

def get_int(tag, default):
    m = re.search(r'<int name="' + tag + r'">(\d+)</int>', bc_xml)
    return int(m.group(1)) if m else default

hc=get_int("HeadColor",1001); tc=get_int("TorsoColor",1003)
la=get_int("LeftArmColor",1001); ra=get_int("RightArmColor",1001)
ll=get_int("LeftLegColor",1001); rl=get_int("RightLegColor",1001)

raw_urls=[u.strip() for u in fetch_str.split(";") if u.strip() and "BodyColors" not in u]
urls_lua=",\n    ".join([json.dumps(u) for u in raw_urls])
pid = int(place_id) if place_id else 0

lua = f'''print("[ORRT] Studio Customizer & Publisher Plugin Initializing...")
local USER_ID = {user_id}
local USER_NAME = {json.dumps(user_name)}
local PLACE_ID = {pid}
local UPLOAD_URL = "{base_url}/Data/Upload.ashx?assetId={pid}"
pcall(function()
    game:SetPlaceID(PLACE_ID); game:SetUniverseId(PLACE_ID)
    local visit = game:GetService("Visit")
    visit:SetUploadUrl(UPLOAD_URL)
end)
local BODY_COLORS = {{ HeadColor={hc}, TorsoColor={tc}, LeftArmColor={la}, RightArmColor={ra}, LeftLegColor={ll}, RightLegColor={rl} }}
local ASSET_URLS = {{
    {urls_lua}
}}
local function ensureR6Attachments(char)
    if not char then return end
    local function addAtt(p,n,cf) local pt=char:FindFirstChild(p); if pt and pt:IsA("BasePart") and not pt:FindFirstChild(n) then local a=Instance.new("Attachment"); a.Name=n; a.CFrame=cf; a.Parent=pt end end
    addAtt("Head","HairAttachment",CFrame.new(0,0.6,0)); addAtt("Head","HatAttachment",CFrame.new(0,0.6,0))
    addAtt("Head","FaceCenterAttachment",CFrame.new(0,0,0)); addAtt("Head","FaceFrontAttachment",CFrame.new(0,0,-0.6))
    addAtt("Torso","BodyFrontAttachment",CFrame.new(0,0,-0.5)); addAtt("Torso","BodyBackAttachment",CFrame.new(0,0,0.5))
    addAtt("Torso","LeftCollarAttachment",CFrame.new(-1,1,0)); addAtt("Torso","RightCollarAttachment",CFrame.new(1,1,0))
    addAtt("Torso","NeckAttachment",CFrame.new(0,1,0)); addAtt("Torso","WaistCenterAttachment",CFrame.new(0,-1,0))
    addAtt("Left Arm","LeftShoulderAttachment",CFrame.new(0,1,0)); addAtt("Left Arm","LeftGripAttachment",CFrame.new(0,-1,0))
    addAtt("Right Arm","RightShoulderAttachment",CFrame.new(0,1,0)); addAtt("Right Arm","RightGripAttachment",CFrame.new(0,-1,0))
    addAtt("Left Leg","LeftFootAttachment",CFrame.new(0,-1,0)); addAtt("Right Leg","RightFootAttachment",CFrame.new(0,-1,0))
end
local applied={{}}
local function customizeCharacter(char)
    if not char or applied[char] then return end
    local hum=char:WaitForChild("Humanoid",10); if not hum then return end
    applied[char]=true
    print("[ORRT] Customizing Character: "..tostring(char.Name))
    pcall(function() char.Name=USER_NAME; local p=game:GetService("Players"):GetPlayerFromCharacter(char); if p then p.Name=USER_NAME end end)
    if not char:FindFirstChild("UpperTorso") then ensureR6Attachments(char) end
    pcall(function()
        local bc=char:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors",char)
        bc.HeadColor=BrickColor.new(BODY_COLORS.HeadColor); bc.TorsoColor=BrickColor.new(BODY_COLORS.TorsoColor)
        bc.LeftArmColor=BrickColor.new(BODY_COLORS.LeftArmColor); bc.RightArmColor=BrickColor.new(BODY_COLORS.RightArmColor)
        bc.LeftLegColor=BrickColor.new(BODY_COLORS.LeftLegColor); bc.RightLegColor=BrickColor.new(BODY_COLORS.RightLegColor)
        local function cp(n,c) local pt=char:FindFirstChild(n); if pt and pt:IsA("BasePart") then pt.BrickColor=BrickColor.new(c) end end
        cp("Head",BODY_COLORS.HeadColor); cp("Torso",BODY_COLORS.TorsoColor)
        cp("Left Arm",BODY_COLORS.LeftArmColor); cp("Right Arm",BODY_COLORS.RightArmColor)
        cp("Left Leg",BODY_COLORS.LeftLegColor); cp("Right Leg",BODY_COLORS.RightLegColor)
        print("[ORRT] BodyColors applied for "..USER_NAME)
    end)
    spawn(function()
        for _,itemUrl in ipairs(ASSET_URLS) do
            pcall(function()
                local objs=game:GetObjects(itemUrl)
                if objs then for _,obj in ipairs(objs) do
                    if obj:IsA("Accessory") or obj:IsA("Hat") then hum:AddAccessory(obj)
                    elseif obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") or obj:IsA("CharacterMesh") then obj.Parent=char
                    elseif obj:IsA("Decal") and string.lower(obj.Name)=="face" then
                        local h=char:FindFirstChild("Head"); if h then local o=h:FindFirstChild("face"); if o then o:Destroy() end; obj.Parent=h end
                    elseif obj:IsA("SpecialMesh") then
                        local h=char:FindFirstChild("Head"); if h then local o=h:FindFirstChildOfClass("SpecialMesh"); if o then o:Destroy() end; obj.Parent=h end
                    end
                end end
            end)
        end
        print("[ORRT] Appearance applied for "..USER_NAME)
    end)
end
local RunService=game:GetService("RunService")
local function scan() for _,c in ipairs(workspace:GetChildren()) do if c:IsA("Model") and c:FindFirstChild("Humanoid") and not applied[c] then customizeCharacter(c) end end end
RunService.Heartbeat:connect(scan)
workspace.ChildAdded:connect(function(c) if c:IsA("Model") and c:FindFirstChild("Humanoid") then scan() end end)
print("[ORRT] Studio Customizer Ready!")
'''
with open(plugin_path,"w",encoding="utf-8") as f: f.write(lua)
PYEOF2

    wine reg add "HKCU\Software\Wine\DirectInput" /v MouseWarpOverride /d enable /f >/dev/null 2>&1 || true
    wine reg add "HKCU\Software\Wine\X11 Driver" /v MouseWarpOverride /d enable /f >/dev/null 2>&1 || true

    PLACES_DIR="$HOME/.cache/orrt/places"
    mkdir -p "$PLACES_DIR"
    PLACE_FILE="$PLACES_DIR/place_${PLACE_ID}.rbxl"
    curl -sSL -H "Cookie: .ROBLOSECURITY=${TICKET}" "${BASE_URL}/asset/?id=${PLACE_ID}" -o "$PLACE_FILE"
    WIN_PLACE_PATH="Z:${PLACE_FILE//\//\\}"

    cd "$STUDIO_ROOT"
    wine "$STUDIO_EXE" "$WIN_PLACE_PATH" >> "$LOG_FILE" 2>&1 &
    STUDIO_PID=$!

    WAIT_COUNT=0
    while ! pgrep -x "RobloxStudioBet" >/dev/null 2>&1; do
        sleep 1; WAIT_COUNT=$((WAIT_COUNT+1))
        [ "$WAIT_COUNT" -ge 45 ] && exit 1
    done

    LAST_HASH=$(md5sum "$PLACE_FILE" 2>/dev/null | awk '{print $1}')
    while pgrep -x "RobloxStudioBet" >/dev/null 2>&1; do
        sleep 2
        CUR_HASH=$(md5sum "$PLACE_FILE" 2>/dev/null | awk '{print $1}')
        if [ -n "$CUR_HASH" ] && [ "$CUR_HASH" != "$LAST_HASH" ]; then
            curl -s -X POST "${BASE_URL}/Data/Upload.ashx?assetId=${PLACE_ID}&suggest=${TICKET}" \
                -H "Content-Type: application/octet-stream" --data-binary "@$PLACE_FILE" >> "$LOG_FILE"
            command -v notify-send >/dev/null 2>&1 && notify-send "ORRT Studio" "Плейс опубликован!" -i document-save 2>/dev/null || true
            LAST_HASH="$CUR_HASH"
        fi
    done

    FINAL_HASH=$(md5sum "$PLACE_FILE" 2>/dev/null | awk '{print $1}')
    if [ -n "$FINAL_HASH" ] && [ "$FINAL_HASH" != "$LAST_HASH" ]; then
        curl -s -X POST "${BASE_URL}/Data/Upload.ashx?assetId=${PLACE_ID}&suggest=${TICKET}" \
            -H "Content-Type: application/octet-stream" --data-binary "@$PLACE_FILE" >> "$LOG_FILE"
    fi
    command -v notify-send >/dev/null 2>&1 && notify-send "ORRT Studio" "Сессия завершена." -i applications-games 2>/dev/null || true
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# GAME (play) mode
# ══════════════════════════════════════════════════════════════════════════════
export WINEDLLOVERRIDES="advapi32=n,b"
[ -f "$HOOK_LIB" ] && export LD_PRELOAD="$HOOK_LIB"
command -v notify-send >/dev/null 2>&1 && notify-send "ORRT" "Запуск игры..." -i applications-games 2>/dev/null || true

AUTH_URL="${BASE_URL}/Login/Negotiate.ashx"
CLIENT_DIR="$WINE_PREFIX/drive_c/users/$CURRENT_USER/AppData/Local/ORRT/Versions/v1.0.0/$CLIENT_VER"

if [ -f "$CLIENT_DIR/RobloxPlayerBeta.exe" ] && grep -aq "pekora.rip" "$CLIENT_DIR/RobloxPlayerBeta.exe" 2>/dev/null; then
    echo "[*] Client contains legacy pekora.rip domain, refreshing to clean ORRT client..." >> "$LOG_FILE"
    rm -rf "$CLIENT_DIR"/*
fi

if [ ! -f "$CLIENT_DIR/RobloxPlayerBeta.exe" ] && [ ! -f "$CLIENT_DIR/ORRTPlayerBeta.exe" ] && [ ! -f "$CLIENT_DIR/ProjectXPlayerBeta.exe" ]; then
    mkdir -p "$CLIENT_DIR"
    TEMP_ZIP="/tmp/orrt_${CLIENT_VER}.zip"
    curl -fsSL "${BASE_URL}/download/client/${CLIENT_VER}" -o "$TEMP_ZIP" \
        || curl -fsSL "http://oldrrt.xyz/download/client/${CLIENT_VER}" -o "$TEMP_ZIP" \
        || curl -fsSL "${BASE_URL}/setup/v1.0.0-ProjectXApp${CLIENT_VER}.zip" -o "$TEMP_ZIP" \
        || curl -fsSL "http://oldrrt.xyz/setup/ORRT_${CLIENT_VER}.zip" -o "$TEMP_ZIP"
    unzip -q -o "$TEMP_ZIP" -d "$CLIENT_DIR"
    rm -f "$TEMP_ZIP"
fi

ROBLOX_EXE=""
[ -f "$CLIENT_DIR/ORRTPlayerBeta.exe" ] && ROBLOX_EXE="$CLIENT_DIR/ORRTPlayerBeta.exe"
[ -z "$ROBLOX_EXE" ] && [ -f "$CLIENT_DIR/RobloxPlayerBeta.exe" ] && ROBLOX_EXE="$CLIENT_DIR/RobloxPlayerBeta.exe"
[ -z "$ROBLOX_EXE" ] && [ -f "$CLIENT_DIR/ProjectXPlayerBeta.exe" ] && ROBLOX_EXE="$CLIENT_DIR/ProjectXPlayerBeta.exe"
[ -z "$ROBLOX_EXE" ] && ROBLOX_EXE=$(find "$WINE_PREFIX/drive_c" -type f \( -iname "ORRTPlayerBeta.exe" -o -iname "RobloxPlayerBeta.exe" -o -iname "ProjectXPlayerBeta.exe" \) 2>/dev/null | head -n 1)

CLIENT_DIR="$(dirname "$ROBLOX_EXE")"
cd "$CLIENT_DIR"

CLIENT_BASE_URL="$BASE_URL"
CLIENT_AUTH_URL="$AUTH_URL"
CLIENT_PLACELAUNCHER="$PLACELAUNCHER"

if [ "$CLIENT_VER" = "2020L" ] || [ "$CLIENT_VER" = "2018L" ]; then
    CLIENT_BASE_URL="http://oldrrt.xyz"
    CLIENT_AUTH_URL="http://oldrrt.xyz/Login/Negotiate.ashx"
    CLIENT_PLACELAUNCHER=$(echo "$PLACELAUNCHER" | sed 's|https\?://[^/]*|http://oldrrt.xyz|')
fi

printf '<?xml version="1.0" encoding="UTF-8"?>\n<Settings>\n\t<ContentFolder>content</ContentFolder>\n\t<BaseUrl>%s/</BaseUrl>\n</Settings>\n' "${CLIENT_BASE_URL%/}" > "$CLIENT_DIR/AppSettings.xml"
mkdir -p "$CLIENT_DIR/ClientSettings"
printf '{\n\t"BaseUrl": "%s/",\n\t"DFIntTaskSchedulerTargetFps": 180\n}\n' "$CLIENT_BASE_URL" > "$CLIENT_DIR/ClientSettings/ClientAppSettings.json"

setsid nohup wine "$ROBLOX_EXE" --app -a "$CLIENT_AUTH_URL" -t "$TICKET" -j "$CLIENT_PLACELAUNCHER" >> "$LOG_FILE" 2>&1 </dev/null &
"""

home = os.path.expanduser("~")
launcher_path = os.path.join(home, "bin", "orrt-player-linux")
os.makedirs(os.path.join(home, "bin"), exist_ok=True)
with open(launcher_path, "w") as f:
    f.write(launcher)
os.chmod(launcher_path, 0o755)
print(f"Written: {launcher_path}")
PYEOF

echo "    [+] Скрипт запуска создан."

# 4. Register URI protocol
echo "[4/6] Регистрация протокола orrt-player в системе..."
DESKTOP_FILE="$HOME/.local/share/applications/orrt-player.desktop"
LAUNCHER_SCRIPT="$HOME/bin/orrt-player-linux"

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
echo "    [+] Протокол зарегистрирован."

# 5. Download game clients
echo "[5/6] Скачивание и установка клиентов игры (2017L, 2018L и 2020L)..."
CURRENT_USER="$(whoami)"

for VER in "2017L" "2018L" "2020L"; do
    TARGET_DIR="$HOME/.wine/drive_c/users/$CURRENT_USER/AppData/Local/ORRT/Versions/v1.0.0/$VER"
    mkdir -p "$TARGET_DIR"
    if [ -f "$TARGET_DIR/RobloxPlayerBeta.exe" ] && grep -aq "pekora.rip" "$TARGET_DIR/RobloxPlayerBeta.exe" 2>/dev/null; then
        echo "    Обнаружен устаревший клиент $VER (содержит pekora.rip), удаляем для чистой установки..."
        rm -rf "$TARGET_DIR"/*
    fi
    if [ ! -f "$TARGET_DIR/RobloxPlayerBeta.exe" ] && [ ! -f "$TARGET_DIR/ORRTPlayerBeta.exe" ] && [ ! -f "$TARGET_DIR/ProjectXPlayerBeta.exe" ]; then
        echo "    Загрузка клиента $VER (~90 МБ)..."
        curl -fL --progress-bar "https://oldrrt.xyz/download/client/${VER}" -o "/tmp/orrt_${VER}.zip" \
            || curl -fL --progress-bar "http://oldrrt.xyz/download/client/${VER}" -o "/tmp/orrt_${VER}.zip" \
            || curl -fL --progress-bar "https://oldrrt.xyz/setup/v1.0.0-ProjectXApp${VER}.zip" -o "/tmp/orrt_${VER}.zip" \
            || curl -fL --progress-bar "http://oldrrt.xyz/setup/ORRT_${VER}.zip" -o "/tmp/orrt_${VER}.zip"
        echo "    Распаковка $VER..."
        unzip -q -o "/tmp/orrt_${VER}.zip" -d "$TARGET_DIR"
        rm -f "/tmp/orrt_${VER}.zip"
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<Settings>\n\t<ContentFolder>content</ContentFolder>\n\t<BaseUrl>http://oldrrt.xyz/</BaseUrl>\n</Settings>\n' > "$TARGET_DIR/AppSettings.xml"
        mkdir -p "$TARGET_DIR/ClientSettings"
        printf '{\n\t"BaseUrl": "http://oldrrt.xyz/",\n\t"DFIntTaskSchedulerTargetFps": 180\n}\n' > "$TARGET_DIR/ClientSettings/ClientAppSettings.json"
        echo "    [+] Клиент $VER успешно установлен в $TARGET_DIR"
    else
        echo "    Клиент $VER уже установлен в $TARGET_DIR"
    fi
done

# 6. Initialize Wine
echo "[6/6] Проверка Wine окружения..."
wineboot -u 2>/dev/null || true

[[ ":$PATH:" != *":$HOME/bin:"* ]] && echo "    [!] Добавь в ~/.bashrc: export PATH=\"\$HOME/bin:\$PATH\""

echo "Installation complete!"
