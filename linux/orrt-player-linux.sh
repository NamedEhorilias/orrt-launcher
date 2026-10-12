#!/bin/bash
SCRIPT_PATH="$(readlink -f "$0")"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
LOG_FILE="$HOME/.cache/orrt-launcher.log"
mkdir -p "$HOME/.cache"

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
res = {
    "ticket": "",
    "client_ver": "2017L",
    "placelauncher": "",
    "launchmode": "play",
    "place_id": ""
}

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
placelauncher = urllib.parse.unquote(res["placelauncher"]) if res["placelauncher"] else ""
launchmode = res["launchmode"]
place_id = res["place_id"]

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
print(f"LAUNCH_MODE={shlex.quote(launchmode)}")
print(f"PLACE_ID={shlex.quote(place_id)}")
' "$RAW_URI")"

WINE_PREFIX="${WINEPREFIX:-$HOME/.wine}"
CURRENT_USER="$(whoami)"
export DISPLAY="${DISPLAY:-:0}"

if [ "$LAUNCH_MODE" = "edit" ]; then
    export WINEDLLOVERRIDES=""
    echo "[*] Edit mode requested for Place ID: $PLACE_ID" >> "$LOG_FILE"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Old Roblox Return Today" "Запуск Roblox Studio 2017..." -i "applications-games" 2>/dev/null || true
    fi

    STUDIO_DIR="$WINE_PREFIX/drive_c/users/$CURRENT_USER/AppData/Local/ORRT/Studio/$CLIENT_VER"
    if [ ! -d "$STUDIO_DIR" ] || [ ! -f "$STUDIO_DIR/RobloxStudioBeta.exe" ]; then
        echo "[*] Studio $CLIENT_VER not found in $STUDIO_DIR, installing..." >> "$LOG_FILE"
        mkdir -p "$STUDIO_DIR"
        LOCAL_ZIP="$PROJECT_ROOT/setup/v1.0.0-Studio${CLIENT_VER}.zip"
        if [ -f "$LOCAL_ZIP" ]; then
            unzip -q -o "$LOCAL_ZIP" -d "$STUDIO_DIR"
        else
            TEMP_ZIP="/tmp/orrt_studio_${CLIENT_VER}.zip"
            curl -sSL "https://oldrrt.xyz/setup/v1.0.0-Studio${CLIENT_VER}.zip" -o "$TEMP_ZIP"
            unzip -q -o "$TEMP_ZIP" -d "$STUDIO_DIR"
            rm -f "$TEMP_ZIP"
        fi
    fi

    STUDIO_EXE=""
    if [ -f "$STUDIO_DIR/RobloxStudioBeta.exe" ]; then
        STUDIO_EXE="$STUDIO_DIR/RobloxStudioBeta.exe"
    else
        STUDIO_EXE=$(find "$WINE_PREFIX/drive_c" "$PROJECT_ROOT" "$HOME/Downloads" -type f -iname "RobloxStudioBeta.exe" 2>/dev/null | head -n 1)
    fi

    if [ -z "$STUDIO_EXE" ] || [ ! -f "$STUDIO_EXE" ]; then
        echo "[!] Error: RobloxStudioBeta.exe not found!" >> "$LOG_FILE"
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "ORRT Studio" "Ошибка: Roblox Studio не найден!" -i "dialog-error" 2>/dev/null || true
        fi
        exit 1
    fi

    # Ensure liborrt_hosts.so exists
    HOOK_LIB="$HOME/.cache/orrt/lib/liborrt_hosts.so"
    if [ ! -f "$HOOK_LIB" ]; then
        mkdir -p "$HOME/.cache/orrt/lib"
        cat << 'HOOK_EOF' > "$HOME/.cache/orrt/lib/hosts_redirect.c"
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <netdb.h>

static int (*real_getaddrinfo)(const char *node, const char *service,
                               const struct addrinfo *hints,
                               struct addrinfo **res) = NULL;
static int (*real_gethostbyname_r)(const char *name,
                                   struct hostent *ret,
                                   char *buf, size_t buflen,
                                   struct hostent **result,
                                   int *h_errnop) = NULL;
static struct hostent *(*real_gethostbyname)(const char *name) = NULL;

static int should_redirect(const char *name) {
    if (!name) return 0;
    if (strstr(name, "roblox.com") != NULL ||
        strstr(name, "rbxcdn.com") != NULL ||
        strstr(name, "oldrrt.xyz") != NULL ||
        strstr(name, "orrt.online") != NULL ||
        strstr(name, "pekora.rip") != NULL ||
        strstr(name, "pekora.zip") != NULL ||
        strstr(name, "projex.zip") != NULL) {
        return 1;
    }
    return 0;
}

int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints,
                struct addrinfo **res) {
    if (!real_getaddrinfo) real_getaddrinfo = dlsym(RTLD_NEXT, "getaddrinfo");
    if (should_redirect(node)) return real_getaddrinfo("74.248.20.23", service, hints, res);
    return real_getaddrinfo(node, service, hints, res);
}

int gethostbyname_r(const char *name, struct hostent *ret,
                    char *buf, size_t buflen,
                    struct hostent **result, int *h_errnop) {
    if (!real_gethostbyname_r) real_gethostbyname_r = dlsym(RTLD_NEXT, "gethostbyname_r");
    if (should_redirect(name)) return real_gethostbyname_r("74.248.20.23", ret, buf, buflen, result, h_errnop);
    return real_gethostbyname_r(name, ret, buf, buflen, result, h_errnop);
}

struct hostent *gethostbyname(const char *name) {
    if (!real_gethostbyname) real_gethostbyname = dlsym(RTLD_NEXT, "gethostbyname");
    if (should_redirect(name)) return real_gethostbyname("74.248.20.23");
    return real_gethostbyname(name);
}
HOOK_EOF
        gcc -O2 -fPIC -shared -o "$HOOK_LIB" "$HOME/.cache/orrt/lib/hosts_redirect.c" -ldl 2>/dev/null || true
    fi
    export LD_PRELOAD="$HOOK_LIB"

    STUDIO_ROOT="$(dirname "$STUDIO_EXE")"
    cat << 'EOF' > "$STUDIO_ROOT/AppSettings.xml"
<?xml version="1.0" encoding="UTF-8"?>
<Settings>
	<ContentFolder>content</ContentFolder>
	<BaseUrl>http://oldrrt.xyz/</BaseUrl>
</Settings>
EOF

    # Configure ClientSettings for Studio
    mkdir -p "$STUDIO_ROOT/ClientSettings"
    cat << 'EOF' > "$STUDIO_ROOT/ClientSettings/ClientAppSettings.json"
{
  "BaseUrl": "http://oldrrt.xyz/",
  "DFIntTaskSchedulerTargetFps": 180
}
EOF
    cp "$STUDIO_ROOT/ClientSettings/ClientAppSettings.json" "$STUDIO_ROOT/ClientSettings/StudioAppSettings.json" 2>/dev/null || true

    # Create cookies.txt for libcurl / Studio auth
    if [ -n "$TICKET" ]; then
        cat << EOF > "$STUDIO_ROOT/cookies.txt"
# Netscape HTTP Cookie File
.oldrrt.xyz	TRUE	/	TRUE	0	.ROBLOSECURITY	$TICKET
oldrrt.xyz	FALSE	/	TRUE	0	.ROBLOSECURITY	$TICKET
.oldrrt.xyz	TRUE	/	TRUE	0	.PEKOSECURITY	$TICKET
oldrrt.xyz	FALSE	/	TRUE	0	.PEKOSECURITY	$TICKET
EOF
        # Inject cookie into Wine WinINet
        wine rundll32.exe wininet.dll,InternetSetCookieA "https://oldrrt.xyz/" ".ROBLOSECURITY" "$TICKET" >/dev/null 2>&1 || true
        wine rundll32.exe wininet.dll,InternetSetCookieA "http://oldrrt.xyz/" ".ROBLOSECURITY" "$TICKET" >/dev/null 2>&1 || true
    fi

    USER_ID="1"
    USER_NAME="itsehorilias"
    if [ -n "$TICKET" ]; then
        USER_INFO=$(curl -s -H "Cookie: .ROBLOSECURITY=${TICKET}" "https://oldrrt.xyz/apisite/users/v1/users/authenticated" 2>/dev/null || echo "{}")
        USER_ID=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d.get('id', 1))" "$USER_INFO" 2>/dev/null || echo "1")
        USER_NAME=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d.get('name', 'itsehorilias'))" "$USER_INFO" 2>/dev/null || echo "itsehorilias")
    fi
    echo "[*] Studio active user: $USER_NAME (ID: $USER_ID)" >> "$LOG_FILE"

    PLUGINS_DIR="$WINE_PREFIX/drive_c/users/$CURRENT_USER/AppData/Local/Roblox/Plugins"
    mkdir -p "$PLUGINS_DIR"
    rm -f "$PLUGINS_DIR/test_plugin.lua" "$PLUGINS_DIR/ORRTPublisher.lua"

    python3 -c '
import sys, re, json, urllib.request

user_id = sys.argv[1]
user_name = sys.argv[2]
place_id = sys.argv[3]
plugin_path = sys.argv[4]

try:
    req_bc = urllib.request.Request(f"http://oldrrt.xyz/Asset/BodyColors.ashx?userId={user_id}", headers={"User-Agent": "Roblox/WinInet"})
    with urllib.request.urlopen(req_bc) as r:
        bc_xml = r.read().decode("utf-8", errors="ignore")
except Exception:
    bc_xml = ""

try:
    req_fetch = urllib.request.Request(f"http://oldrrt.xyz/asset/CharacterFetch.ashx?userId={user_id}", headers={"User-Agent": "Roblox/WinInet"})
    with urllib.request.urlopen(req_fetch) as r:
        fetch_str = r.read().decode("utf-8", errors="ignore")
except Exception:
    fetch_str = ""

def get_int(tag, default):
    m = re.search(r"<int name=\"" + tag + r"\">(\d+)</int>", bc_xml)
    return int(m.group(1)) if m else default

hc = get_int("HeadColor", 1001)
tc = get_int("TorsoColor", 1003)
la = get_int("LeftArmColor", 1001)
ra = get_int("RightArmColor", 1001)
ll = get_int("LeftLegColor", 1001)
rl = get_int("RightLegColor", 1001)

raw_urls = [u.strip() for u in fetch_str.split(";") if u.strip() and "BodyColors" not in u]
urls_lua = ",\n    ".join([json.dumps(u) for u in raw_urls])

lua_script = f"""print("[ORRT] Studio Customizer & Publisher Plugin Initializing...")

local USER_ID = {user_id}
local USER_NAME = {json.dumps(user_name)}
local PLACE_ID = {place_id}
local UPLOAD_URL = "https://oldrrt.xyz/Data/Upload.ashx?assetId=" .. tostring(PLACE_ID)

pcall(function()
    game:SetPlaceID(PLACE_ID)
    game:SetUniverseId(PLACE_ID)
    local visit = game:GetService("Visit")
    visit:SetUploadUrl(UPLOAD_URL)
end)

local BODY_COLORS = {{
    HeadColor = {hc},
    TorsoColor = {tc},
    LeftArmColor = {la},
    RightArmColor = {ra},
    LeftLegColor = {ll},
    RightLegColor = {rl},
}}

local ASSET_URLS = {{
    {urls_lua}
}}

local function ensureR6Attachments(char)
    if not char then return end
    local function addAtt(partName, attName, cf)
        local part = char:FindFirstChild(partName)
        if part and part:IsA("BasePart") and not part:FindFirstChild(attName) then
            local a = Instance.new("Attachment")
            a.Name = attName
            a.CFrame = cf
            a.Parent = part
        end
    end
    addAtt("Head", "HairAttachment", CFrame.new(0, 0.6, 0))
    addAtt("Head", "HatAttachment", CFrame.new(0, 0.6, 0))
    addAtt("Head", "FaceCenterAttachment", CFrame.new(0, 0, 0))
    addAtt("Head", "FaceFrontAttachment", CFrame.new(0, 0, -0.6))
    addAtt("Torso", "BodyFrontAttachment", CFrame.new(0, 0, -0.5))
    addAtt("Torso", "BodyBackAttachment", CFrame.new(0, 0, 0.5))
    addAtt("Torso", "LeftCollarAttachment", CFrame.new(-1, 1, 0))
    addAtt("Torso", "RightCollarAttachment", CFrame.new(1, 1, 0))
    addAtt("Torso", "NeckAttachment", CFrame.new(0, 1, 0))
    addAtt("Torso", "WaistCenterAttachment", CFrame.new(0, -1, 0))
    addAtt("Torso", "WaistFrontAttachment", CFrame.new(0, -1, -0.5))
    addAtt("Torso", "WaistBackAttachment", CFrame.new(0, -1, 0.5))
    addAtt("Left Arm", "LeftShoulderAttachment", CFrame.new(0, 1, 0))
    addAtt("Left Arm", "LeftGripAttachment", CFrame.new(0, -1, 0))
    addAtt("Right Arm", "RightShoulderAttachment", CFrame.new(0, 1, 0))
    addAtt("Right Arm", "RightGripAttachment", CFrame.new(0, -1, 0))
    addAtt("Left Leg", "LeftFootAttachment", CFrame.new(0, -1, 0))
    addAtt("Right Leg", "RightFootAttachment", CFrame.new(0, -1, 0))
end

local applied = {{}}

local function customizeCharacter(char)
    if not char or applied[char] then return end
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end
    applied[char] = true

    print("[ORRT] Customizing Character: " .. tostring(char.Name))

    pcall(function()
        char.Name = USER_NAME
        local p = game:GetService("Players"):GetPlayerFromCharacter(char)
        if p then p.Name = USER_NAME end
    end)

    local isR15 = char:FindFirstChild("UpperTorso") ~= nil
    if not isR15 then
        ensureR6Attachments(char)
    end

    -- 1. Apply BodyColors
    pcall(function()
        local bc = char:FindFirstChildOfClass("BodyColors")
        if not bc then
            bc = Instance.new("BodyColors")
            bc.Parent = char
        end
        bc.HeadColor = BrickColor.new(BODY_COLORS.HeadColor)
        bc.TorsoColor = BrickColor.new(BODY_COLORS.TorsoColor)
        bc.LeftArmColor = BrickColor.new(BODY_COLORS.LeftArmColor)
        bc.RightArmColor = BrickColor.new(BODY_COLORS.RightArmColor)
        bc.LeftLegColor = BrickColor.new(BODY_COLORS.LeftLegColor)
        bc.RightLegColor = BrickColor.new(BODY_COLORS.RightLegColor)

        local function colorPart(partName, col)
            local pt = char:FindFirstChild(partName)
            if pt and pt:IsA("BasePart") then
                pt.BrickColor = BrickColor.new(col)
            end
        end
        colorPart("Head", BODY_COLORS.HeadColor)
        colorPart("Torso", BODY_COLORS.TorsoColor)
        colorPart("UpperTorso", BODY_COLORS.TorsoColor)
        colorPart("LowerTorso", BODY_COLORS.TorsoColor)
        colorPart("Left Arm", BODY_COLORS.LeftArmColor)
        colorPart("LeftUpperArm", BODY_COLORS.LeftArmColor)
        colorPart("LeftLowerArm", BODY_COLORS.LeftArmColor)
        colorPart("LeftHand", BODY_COLORS.LeftArmColor)
        colorPart("Right Arm", BODY_COLORS.RightArmColor)
        colorPart("RightUpperArm", BODY_COLORS.RightArmColor)
        colorPart("RightLowerArm", BODY_COLORS.RightArmColor)
        colorPart("RightHand", BODY_COLORS.RightArmColor)
        colorPart("Left Leg", BODY_COLORS.LeftLegColor)
        colorPart("LeftUpperLeg", BODY_COLORS.LeftLegColor)
        colorPart("LeftLowerLeg", BODY_COLORS.LeftLegColor)
        colorPart("LeftFoot", BODY_COLORS.LeftLegColor)
        colorPart("Right Leg", BODY_COLORS.RightLegColor)
        colorPart("RightUpperLeg", BODY_COLORS.RightLegColor)
        colorPart("RightLowerLeg", BODY_COLORS.RightLegColor)
        colorPart("RightFoot", BODY_COLORS.RightLegColor)
        print("[ORRT] BodyColors applied for " .. USER_NAME)
    end)

    -- 2. Apply Clothes & Accessories
    spawn(function()
        for _, itemUrl in ipairs(ASSET_URLS) do
            pcall(function()
                local objs = game:GetObjects(itemUrl)
                if objs then
                    for _, obj in ipairs(objs) do
                        if obj:IsA("Accessory") or obj:IsA("Hat") then
                            hum:AddAccessory(obj)
                        elseif obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") or obj:IsA("CharacterMesh") then
                            obj.Parent = char
                        elseif obj:IsA("Decal") and string.lower(obj.Name) == "face" then
                            local head = char:FindFirstChild("Head")
                            if head then
                                local oldFace = head:FindFirstChild("face")
                                if oldFace then oldFace:Destroy() end
                                obj.Parent = head
                            end
                        elseif obj:IsA("SpecialMesh") then
                            local head = char:FindFirstChild("Head")
                            if head then
                                local oldMesh = head:FindFirstChildOfClass("SpecialMesh")
                                if oldMesh then oldMesh:Destroy() end
                                obj.Parent = head
                            end
                        end
                    end
                end
            end)
        end
        print("[ORRT] Appearance applied for " .. USER_NAME)
    end)
end

local RunService = game:GetService("RunService")
local function scan()
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child:FindFirstChild("Humanoid") and not applied[child] then
            customizeCharacter(child)
        end
    end
end

RunService.Heartbeat:connect(scan)
workspace.ChildAdded:connect(function(c)
    if c:IsA("Model") and c:FindFirstChild("Humanoid") then
        scan()
    end
end)

print("[ORRT] Studio Customizer Ready!")
"""

with open(plugin_path, "w", encoding="utf-8") as f:
    f.write(lua_script)
' "$USER_ID" "$USER_NAME" "$PLACE_ID" "$PLUGINS_DIR/ORRTCustomizer.lua"

    PLAY_SOLO_SCRIPT="$STUDIO_ROOT/content/scripts/CoreScripts/ServerCoreScripts/ORRTPlaySolo.lua"
    if [ -f "$PLAY_SOLO_SCRIPT" ]; then
        sed -i "s/local USER_ID = .*/local USER_ID = ${USER_ID}/" "$PLAY_SOLO_SCRIPT"
        sed -i "s/local USER_NAME = .*/local USER_NAME = \"${USER_NAME}\"/" "$PLAY_SOLO_SCRIPT"
    fi

    # Ensure Wine mouse warp settings are not forcing extreme sensitivity
    wine reg add "HKCU\Software\Wine\DirectInput" /v MouseWarpOverride /d enable /f >/dev/null 2>&1 || true
    wine reg add "HKCU\Software\Wine\X11 Driver" /v MouseWarpOverride /d enable /f >/dev/null 2>&1 || true

    PLACES_DIR="$HOME/.cache/orrt/places"
    mkdir -p "$PLACES_DIR"
    PLACE_FILE="$PLACES_DIR/place_${PLACE_ID}.rbxl"
    echo "[*] Pre-fetching place $PLACE_ID to $PLACE_FILE..." >> "$LOG_FILE"
    curl -sSL -H "Cookie: .ROBLOSECURITY=${TICKET}" "https://oldrrt.xyz/asset/?id=${PLACE_ID}" -o "$PLACE_FILE"
    WIN_PLACE_PATH="Z:${PLACE_FILE//\//\\}"

    echo "[*] Launching Studio: $STUDIO_EXE for place $PLACE_ID ($WIN_PLACE_PATH)" >> "$LOG_FILE"

    cd "$STUDIO_ROOT"
    wine "$STUDIO_EXE" "$WIN_PLACE_PATH" >> "$LOG_FILE" 2>&1 &
    STUDIO_PID=$!
    echo "[*] Studio process spawned (PID $STUDIO_PID)" >> "$LOG_FILE"

    WAIT_COUNT=0
    while ! pgrep -x "RobloxStudioBet" >/dev/null 2>&1; do
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
        if [ "$WAIT_COUNT" -ge 45 ]; then
            echo "[!] Timeout waiting for RobloxStudioBeta.exe to start" >> "$LOG_FILE"
            exit 1
        fi
    done

    LAST_HASH=$(md5sum "$PLACE_FILE" 2>/dev/null | awk '{print $1}')
    echo "[*] Studio sync watcher active for $PLACE_FILE (initial hash: $LAST_HASH)" >> "$LOG_FILE"

    while pgrep -x "RobloxStudioBet" >/dev/null 2>&1; do
        sleep 2
        if [ -f "$PLACE_FILE" ]; then
            CUR_HASH=$(md5sum "$PLACE_FILE" 2>/dev/null | awk '{print $1}')
            if [ -n "$CUR_HASH" ] && [ "$CUR_HASH" != "$LAST_HASH" ]; then
                echo "[*] File modification detected ($CUR_HASH)! Auto-publishing to ORRT..." >> "$LOG_FILE"
                RESP=$(curl -s -X POST "https://oldrrt.xyz/Data/Upload.ashx?assetId=${PLACE_ID}&suggest=${TICKET}" \
                    -H "Content-Type: application/octet-stream" \
                    --data-binary "@$PLACE_FILE")
                echo "[*] Upload response: $RESP" >> "$LOG_FILE"
                if command -v notify-send >/dev/null 2>&1; then
                    notify-send "ORRT Studio" "Плейс успешно опубликован на сайте!" -i "document-save" 2>/dev/null || true
                fi
                LAST_HASH="$CUR_HASH"
            fi
        fi
    done

    if [ -f "$PLACE_FILE" ]; then
        FINAL_HASH=$(md5sum "$PLACE_FILE" 2>/dev/null | awk '{print $1}')
        if [ -n "$FINAL_HASH" ] && [ "$FINAL_HASH" != "$LAST_HASH" ]; then
            echo "[*] Final save detected after Studio exit. Uploading..." >> "$LOG_FILE"
            RESP=$(curl -s -X POST "https://oldrrt.xyz/Data/Upload.ashx?assetId=${PLACE_ID}&suggest=${TICKET}" \
                -H "Content-Type: application/octet-stream" \
                --data-binary "@$PLACE_FILE")
            echo "[*] Final upload response: $RESP" >> "$LOG_FILE"
        fi
    fi
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "ORRT Studio" "Сессия редактирования завершена. Изменения синхронизированы!" -i "applications-games" 2>/dev/null || true
    fi

    exit 0
fi

export WINEDLLOVERRIDES="advapi32=n,b"
HOOK_LIB="$HOME/.cache/orrt/lib/liborrt_hosts.so"
if [ -f "$HOOK_LIB" ]; then
    export LD_PRELOAD="$HOOK_LIB"
fi

if command -v notify-send >/dev/null 2>&1; then
    notify-send "Old Roblox Return Today" "Запуск игры..." -i "applications-games" 2>/dev/null || true
fi

AUTH_URL="${BASE_URL}/Login/Negotiate.ashx"

echo "[*] Auth Ticket: $TICKET" >> "$LOG_FILE"
echo "[*] Base URL: $BASE_URL" >> "$LOG_FILE"
echo "[*] Client Version: $CLIENT_VER" >> "$LOG_FILE"
echo "[*] PlaceLauncher: $PLACELAUNCHER" >> "$LOG_FILE"

CLIENT_DIR="$WINE_PREFIX/drive_c/users/$CURRENT_USER/AppData/Local/ORRT/Versions/v1.0.0/$CLIENT_VER"

if [ -f "$CLIENT_DIR/RobloxPlayerBeta.exe" ] && grep -aq "pekora.rip" "$CLIENT_DIR/RobloxPlayerBeta.exe" 2>/dev/null; then
    echo "[*] Client contains legacy pekora.rip domain, refreshing to clean ORRT client..." >> "$LOG_FILE"
    rm -rf "$CLIENT_DIR"/*
fi

if [ ! -d "$CLIENT_DIR" ] || [ ! -f "$CLIENT_DIR/RobloxPlayerBeta.exe" -a ! -f "$CLIENT_DIR/ORRTPlayerBeta.exe" -a ! -f "$CLIENT_DIR/ProjectXPlayerBeta.exe" ]; then
    echo "[*] Client $CLIENT_VER not found, installing..." >> "$LOG_FILE"
    mkdir -p "$CLIENT_DIR"
    LOCAL_ZIP="$PROJECT_ROOT/setup/v1.0.0-ProjectXApp${CLIENT_VER}.zip"
    if [ -f "$LOCAL_ZIP" ]; then
        unzip -q -o "$LOCAL_ZIP" -d "$CLIENT_DIR"
    else
        TEMP_ZIP="/tmp/orrt_${CLIENT_VER}.zip"
        curl -sSL "${BASE_URL}/setup/v1.0.0-ProjectXApp${CLIENT_VER}.zip" -o "$TEMP_ZIP" || curl -sSL "${BASE_URL}/setup/ORRT_${CLIENT_VER}.zip" -o "$TEMP_ZIP" || curl -sSL "${BASE_URL}/download/client/${CLIENT_VER}" -o "$TEMP_ZIP"
        unzip -q -o "$TEMP_ZIP" -d "$CLIENT_DIR"
        rm -f "$TEMP_ZIP"
    fi
fi

ROBLOX_EXE=""
if [ -f "$CLIENT_DIR/ORRTPlayerBeta.exe" ]; then
    ROBLOX_EXE="$CLIENT_DIR/ORRTPlayerBeta.exe"
elif [ -f "$CLIENT_DIR/RobloxPlayerBeta.exe" ]; then
    ROBLOX_EXE="$CLIENT_DIR/RobloxPlayerBeta.exe"
elif [ -f "$CLIENT_DIR/ProjectXPlayerBeta.exe" ]; then
    ROBLOX_EXE="$CLIENT_DIR/ProjectXPlayerBeta.exe"
else
    ROBLOX_EXE=$(find "$WINE_PREFIX/drive_c" "$PROJECT_ROOT" -type f \( -iname "ORRTPlayerBeta.exe" -o -iname "RobloxPlayerBeta.exe" -o -iname "ProjectXPlayerBeta.exe" \) 2>/dev/null | head -n 1)
fi

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

printf '<Settings><ContentFolder>content</ContentFolder><BaseUrl>%s/</BaseUrl></Settings>' "${CLIENT_BASE_URL%/}" > "$CLIENT_DIR/AppSettings.xml"

mkdir -p "$CLIENT_DIR/ClientSettings"
cat <<EOF > "$CLIENT_DIR/ClientSettings/ClientAppSettings.json"
{
	"BaseUrl": "${CLIENT_BASE_URL}/",
	"DFIntTaskSchedulerTargetFps": 180
}
EOF

setsid nohup wine "$ROBLOX_EXE" --app -a "$CLIENT_AUTH_URL" -t "$TICKET" -j "$CLIENT_PLACELAUNCHER" >> "$LOG_FILE" 2>&1 </dev/null &
