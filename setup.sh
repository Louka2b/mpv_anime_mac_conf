#!/usr/bin/env bash
# ==============================================================================
# mpv-macos-anime — Automated Build & Configuration Installer
# VapourSynth R72 LTS + MVTools + libplacebo (Vulkan/Metal) + Anime4K + ModernZ
# ==============================================================================

set -euo pipefail

LOG_FILE="/tmp/mpv_install.log"
: > "$LOG_FILE"

if [ -d "/opt/homebrew/bin" ]; then
    BREW_PREFIX="/opt/homebrew"
elif [ -d "/usr/local/bin" ]; then
    BREW_PREFIX="/usr/local"
else
    printf "[ERROR] Homebrew is not installed (https://brew.sh).\n" >&2
    exit 1
fi

export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PKG_CONFIG_PATH="$BREW_PREFIX/lib/pkgconfig:$BREW_PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export CFLAGS="-I$BREW_PREFIX/include -O3"
export CXXFLAGS="-I$BREW_PREFIX/include -O3"
export LDFLAGS="-L$BREW_PREFIX/lib"

MPV_DIR="$HOME/.config/mpv"
SHADER_DIR="$MPV_DIR/shaders"
SCRIPT_DIR="$MPV_DIR/scripts"
OPTS_DIR="$MPV_DIR/script-opts"
FONT_DIR="$MPV_DIR/fonts"
CACHE_DIR="$MPV_DIR/cache"
BUILD_TMP="/tmp/mpv_clean_build"

# ------------------------------------------------------------------------------
# Terminal Progress Bar Helper (hides background task output, logs to $LOG_FILE)
# ------------------------------------------------------------------------------
run_task() {
    local label="$1"
    shift
    local width=28
    local pos=0

    "$@" >>"$LOG_FILE" 2>&1 &
    local pid=$!

    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        pos=$(( (pos + 1) % (width + 1) ))
        local filled=""
        local empty=""
        for ((i=0; i<pos; i++)); do filled="${filled}#"; done
        for ((i=pos; i<width; i++)); do empty="${empty}-"; done
        printf "\r\033[K  [%-28s]  %s..." "${filled}${empty}" "$label"
        sleep 0.12
    done

    local status=0
    wait "$pid" || status=$?

    local full="############################"
    if [ "$status" -eq 0 ]; then
        printf "\r\033[K  [%s]  %s [OK]\n" "$full" "$label"
        tput cnorm 2>/dev/null || true
    else
        printf "\r\033[K  [FAILED                      ]  %s [ERROR]\n" "$label"
        tput cnorm 2>/dev/null || true
        printf "\n[ERROR] Task failed: %s. Last 20 lines of %s:\n" "$label" "$LOG_FILE" >&2
        tail -n 20 "$LOG_FILE" >&2
        exit "$status"
    fi
}

printf "\n==============================================================================\n"
printf "  mpv macOS Anime Setup (VapourSynth R72 + MVTools + Anime4K + ModernZ)\n"
printf "==============================================================================\n\n"

# ------------------------------------------------------------------------------
# Step 1: Homebrew Dependencies (visible output as requested)
# ------------------------------------------------------------------------------
printf "[1/7] Checking Homebrew dependencies...\n"
DEPS=(
    autoconf automake libtool pkg-config meson ninja cmake
    python3 cython zimg fftw ffmpeg libass little-cms2 luajit mujs
    uchardet molten-vk vulkan-headers vulkan-loader shaderc
)
for dep in "${DEPS[@]}"; do
    if ! brew list "$dep" >/dev/null 2>&1; then
        printf "  -> Installing %s via Homebrew...\n" "$dep"
        brew install "$dep"
    fi
done
printf "  [############################]  Homebrew dependencies verified [OK]\n\n"

PY_BIN="$BREW_PREFIX/bin/python3"
PY_VER=$($PY_BIN -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_SITE="$BREW_PREFIX/lib/python$PY_VER/site-packages"
mkdir -p "$PY_SITE"
export PYTHONPATH="$PY_SITE:${PYTHONPATH:-}"

# ------------------------------------------------------------------------------
# Step 2: Environment Reset
# ------------------------------------------------------------------------------
printf "[2/7] Preparing directories and cleaning old cache...\n"
clean_env() {
    killall mpv 2>/dev/null || true
    rm -rf "$MPV_DIR" "$BUILD_TMP" "$HOME/Library/Caches/io.mpv" "$HOME/.cache/mpv" 2>/dev/null || true
    mkdir -p "$MPV_DIR" "$SHADER_DIR" "$SCRIPT_DIR" "$OPTS_DIR" "$FONT_DIR" "$CACHE_DIR" "$BREW_PREFIX/lib/vapoursynth"
}
run_task "Resetting ~/.config/mpv and shader cache" clean_env
printf "\n"

# ------------------------------------------------------------------------------
# Step 3: Core Engine Compilation (VapourSynth R72, MVTools, libplacebo, mpv)
# ------------------------------------------------------------------------------
printf "[3/7] Building core video & motion engines...\n"

build_vapoursynth() {
    if ! pkg-config --exists vapoursynth-script 2>/dev/null; then
        rm -rf "$BUILD_TMP/vapoursynth" && mkdir -p "$BUILD_TMP"
        git clone --depth 1 --branch R72 https://github.com/vapoursynth/vapoursynth.git "$BUILD_TMP/vapoursynth"
        cd "$BUILD_TMP/vapoursynth"
        ./autogen.sh
        ./configure --prefix="$BREW_PREFIX" --with-plugindir="$BREW_PREFIX/lib/vapoursynth" --with-python_prefix="$BREW_PREFIX" PYTHON="$PY_BIN"
        make -j"$(sysctl -n hw.ncpu)"
        make install
        $PY_BIN -m pip install --break-system-packages --no-build-isolation --no-deps . 2>/dev/null || cp -Rf build/lib*/* "$PY_SITE/" 2>/dev/null || true
    fi
}
run_task "VapourSynth R72 LTS (libvapoursynth-script)" build_vapoursynth

build_mvtools() {
    if [ ! -f "$BREW_PREFIX/lib/vapoursynth/mvtools.dylib" ]; then
        rm -rf "$BUILD_TMP/mvtools" && mkdir -p "$BUILD_TMP"
        git clone --depth 1 https://github.com/dubhater/vapoursynth-mvtools.git "$BUILD_TMP/mvtools"
        cd "$BUILD_TMP/mvtools"
        $PY_BIN -c 'p="meson.build"; open(p,"w").write(open(p).read().replace("import vapoursynth as vs; print(vs.get_include())", "print(\"'$BREW_PREFIX'/include/vapoursynth\")"))'
        meson setup build --prefix="$BREW_PREFIX" --buildtype=release
        ninja -C build
        cp -f build/mvtools.dylib "$BREW_PREFIX/lib/vapoursynth/"
    fi
}
run_task "MVTools motion vector engine (mvtools.dylib)" build_mvtools

build_libplacebo() {
    if ! pkg-config --exists libplacebo 2>/dev/null; then
        rm -rf "$BUILD_TMP/libplacebo" && mkdir -p "$BUILD_TMP"
        git clone --depth 1 --recursive https://code.videolan.org/videolan/libplacebo.git "$BUILD_TMP/libplacebo"
        cd "$BUILD_TMP/libplacebo"
        meson setup build --prefix="$BREW_PREFIX" --buildtype=release -Dvulkan=enabled -Dshaderc=enabled -Dlcms=enabled -Dxxhash=disabled -Ddemos=false -Dtests=false
        ninja -C build
        ninja -C build install
    fi
}
run_task "libplacebo GPU renderer (Vulkan/Metal + shaderc)" build_libplacebo

build_mpv() {
    if ! "$BREW_PREFIX/bin/mpv" --vf=help 2>/dev/null | grep -qi "vapoursynth" || [ ! -d "/Applications/mpv.app" ]; then
        rm -rf "$BUILD_TMP/mpv" && mkdir -p "$BUILD_TMP"
        git clone --depth 1 https://github.com/mpv-player/mpv.git "$BUILD_TMP/mpv"
        cd "$BUILD_TMP/mpv"
        meson setup build --prefix="$BREW_PREFIX" --buildtype=release -Dlibmpv=true -Dlua=luajit -Dvapoursynth=enabled -Dvulkan=enabled -Dcoreaudio=enabled -Dcocoa=enabled -Dmacos-media-player=enabled -Dmacos-cocoa-cb=enabled
        ninja -C build
        ninja -C build install
        python3 TOOLS/osxbundle.py --skip-deps build/mpv
        rm -rf /Applications/mpv.app
        cp -Rf build/mpv.app /Applications/mpv.app
    fi

    if [ -d "/Applications/mpv.app/Contents/MacOS" ]; then
        if [ ! -f "/Applications/mpv.app/Contents/MacOS/mpv-bin" ] && [ -f "/Applications/mpv.app/Contents/MacOS/mpv" ]; then
            mv /Applications/mpv.app/Contents/MacOS/mpv /Applications/mpv.app/Contents/MacOS/mpv-bin
        fi
        cat << WRAPPER > /Applications/mpv.app/Contents/MacOS/mpv
#!/bin/sh
export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:/usr/bin:/bin:/usr/sbin:/sbin:\$PATH"
export PYTHONPATH="$PY_SITE:\${PYTHONPATH:-}"
export VAPOURSYNTH_CONF_PATH="$MPV_DIR/vapoursynth.conf"
exec "/Applications/mpv.app/Contents/MacOS/mpv-bin" "\$@"
WRAPPER
        chmod +x /Applications/mpv.app/Contents/MacOS/mpv
        /usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" /Applications/mpv.app/Contents/Info.plist 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :LSEnvironment:PATH string $BREW_PREFIX/bin:$BREW_PREFIX/sbin:/usr/bin:/bin:/usr/sbin:/sbin" /Applications/mpv.app/Contents/Info.plist 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :LSEnvironment:PATH $BREW_PREFIX/bin:$BREW_PREFIX/sbin:/usr/bin:/bin:/usr/sbin:/sbin" /Applications/mpv.app/Contents/Info.plist
        /usr/libexec/PlistBuddy -c "Add :LSEnvironment:PYTHONPATH string $PY_SITE" /Applications/mpv.app/Contents/Info.plist 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :LSEnvironment:PYTHONPATH $PY_SITE" /Applications/mpv.app/Contents/Info.plist
        /usr/libexec/PlistBuddy -c "Add :LSEnvironment:VAPOURSYNTH_CONF_PATH string $MPV_DIR/vapoursynth.conf" /Applications/mpv.app/Contents/Info.plist 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :LSEnvironment:VAPOURSYNTH_CONF_PATH $MPV_DIR/vapoursynth.conf" /Applications/mpv.app/Contents/Info.plist
        codesign --force --deep --sign - /Applications/mpv.app 2>/dev/null || true
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/mpv.app 2>/dev/null || true
    fi
    cd "$HOME" && rm -rf "$BUILD_TMP"
}
run_task "mpv binary & signed /Applications/mpv.app bundle" build_mpv
printf "\n"

MPV_BIN="$BREW_PREFIX/bin/mpv"

# ------------------------------------------------------------------------------
# Step 4: VapourSynth MVTools Pipelines & Anime4K Shaders
# ------------------------------------------------------------------------------
printf "[4/7] Installing VapourSynth pipelines and Anime4K v4.0.1 shaders...\n"

install_shaders_and_vpy() {
    cat << EOF > "$MPV_DIR/vapoursynth.conf"
SystemPluginDir=$BREW_PREFIX/lib/vapoursynth
EOF

    for mult in 2.0 2.5 3.0; do
        fname=$(echo "$mult" | tr -d '.')
        cat << VPY > "$MPV_DIR/fg_${fname}.vpy"
import vapoursynth as vs

core = vs.core
core.num_threads = $(sysctl -n hw.ncpu)

if not hasattr(core, "mv"):
    try:
        core.std.LoadPlugin(path="$BREW_PREFIX/lib/vapoursynth/mvtools.dylib")
    except Exception:
        pass

clip = video_in
mult = $mult

try:
    fps = float(container_fps) if container_fps else 23.976
except Exception:
    fps = 23.976
if fps <= 1.0:
    fps = 23.976

src_num = int(round(fps * 1000))
src_den = 1000
dst_num = int(round(src_num * mult))
dst_den = 1000

clip = core.std.AssumeFPS(clip, fpsnum=src_num, fpsden=src_den)

orig_format = clip.format
if orig_format.bits_per_sample > 8:
    clip = core.resize.Bicubic(clip, format=vs.YUV420P8)

blk_size = 16 if clip.width <= 1920 else 32
overlap = 4 if clip.width <= 1920 else 8

sup = core.mv.Super(clip, pel=1, sharp=1, rfilter=2)
bvec = core.mv.Analyse(sup, isb=True, blksize=blk_size, overlap=overlap, search=3, searchparam=2, badsad=1000)
fvec = core.mv.Analyse(sup, isb=False, blksize=blk_size, overlap=overlap, search=3, searchparam=2, badsad=1000)
clip = core.mv.BlockFPS(clip, sup, bvec, fvec, num=dst_num, den=dst_den, mode=3, thscd1=320, thscd2=110)

if orig_format.bits_per_sample > 8:
    clip = core.resize.Bicubic(clip, format=orig_format.id)

clip.set_output()
VPY
    done

    curl -fsSL --retry 3 -o /tmp/Anime4K.zip "https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip"
    unzip -qo /tmp/Anime4K.zip -d "$SHADER_DIR"
    rm -f /tmp/Anime4K.zip
}
run_task "MVTools scripts (fg_20/25/30) & Anime4K GLSL" install_shaders_and_vpy
printf "\n"

# ------------------------------------------------------------------------------
# Step 5: ModernZ OSC & Thumbfast
# ------------------------------------------------------------------------------
printf "[5/7] Installing ModernZ UI and Thumbfast thumbnail engine...\n"

install_ui() {
    curl -fsSL --retry 3 -o /tmp/ModernZ.zip "https://github.com/Samillion/ModernZ/archive/refs/heads/main.zip"
    mkdir -p /tmp/modernz_extract
    unzip -qo /tmp/ModernZ.zip -d /tmp/modernz_extract
    find /tmp/modernz_extract -name "modernz.lua" -exec cp -f {} "$SCRIPT_DIR/" \;
    find /tmp/modernz_extract -name "*.ttf" -exec cp -f {} "$FONT_DIR/" \;
    mkdir -p "$HOME/Library/Fonts"
    cp -f "$FONT_DIR"/*.ttf "$HOME/Library/Fonts/" 2>/dev/null || true
    rm -rf /tmp/ModernZ.zip /tmp/modernz_extract

    $PY_BIN - "$SCRIPT_DIR/modernz.lua" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    code = f.read()

hook_lua = """
local _sunset_icon = "m 0 0 m 24 26 m 2 15 l 22 15 l 22 17 l 2 17 m 6 19 l 18 19 l 18 21 l 6 21 m 5 13 b 5 9 8 6 12 6 b 16 6 19 9 19 13 m 11 1 l 13 1 l 13 4 l 11 4 m 4 5 l 6 3 l 8 5 l 6 7 m 18 3 l 20 5 l 18 7 l 16 5"

local function _custom_patch_elements()
    if type(elements) ~= "table" then return end
    for k, el in pairs(elements) do
        if type(el) == "table" and type(el.eventresponder) == "table" then
            local ename = tostring(el.name or k):lower()
            if ename:find("title") then
                el.eventresponder = {}
                el.tooltipF = nil
            elseif ename:find("speed") then
                el.visible = true
                el.eventresponder["mbtn_left_up"] = function()
                    mp.commandv("script-message", "toggle-speed-slider")
                end
                el.eventresponder["mbtn_left_down"] = nil
                el.eventresponder["mbtn_right_up"] = function()
                    mp.set_property_number("speed", 1.0)
                end
            elseif ename == "tog_fs" or ename:find("fullscreen") then
                el.visible = true
                el.eventresponder["mbtn_left_up"] = function()
                    mp.commandv("script-message", "toggle-max-window")
                end
                el.eventresponder["mbtn_left_down"] = nil
            elseif ename == "info" or ename == "tog_info" then
                el.visible = true
                el.content = function()
                    return "{\\\\fnHelvetica Neue\\\\b1\\\\fs18}4K"
                end
                el.tooltipF = "MVTools FrameGen & Anime4K Menu"
                el.eventresponder["mbtn_left_up"] = function()
                    mp.commandv("script-message", "toggle-shader-menu")
                end
                el.eventresponder["mbtn_right_up"] = function()
                    mp.commandv("script-message", "set-profile", "fg_2")
                end
            elseif ename:find("screenshot") or ename == "sh_btn" then
                el.visible = true
                el.content = function()
                    local af = mp.get_property("af", "")
                    if af and af:find("dynaudnorm") then
                        return "{\\\\p1\\\\bord0\\\\shad0\\\\1c&H55FF55&}" .. _sunset_icon .. "{\\\\p0}"
                    end
                    return "{\\\\p1\\\\bord0\\\\shad0}" .. _sunset_icon .. "{\\\\p0}"
                end
                el.tooltipF = function()
                    local af = mp.get_property("af", "")
                    if af and af:find("dynaudnorm") then
                        return "Night Audio Mode: ON (Click to disable)"
                    end
                    return "Night Audio Mode: OFF (Voice/Explosion Normalization)"
                end
                el.eventresponder["mbtn_left_up"] = function()
                    mp.commandv("script-message", "toggle-night-mode")
                end
                el.eventresponder["mbtn_left_down"] = nil
            end
        end
    end
end
"""

m = re.search(r'^(local\s+)?function\s+render_elements\s*\([^\)]*\)', code, re.M)
if m:
    idx = m.start()
    end_line = code.find("\n", idx) + 1
    code = code[:idx] + hook_lua + "\n" + code[idx:end_line] + "    _custom_patch_elements()\n" + code[end_line:]
else:
    code = code + "\n" + hook_lua + "\nmp.add_periodic_timer(0.25, _custom_patch_elements)\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(code)
PYEOF

    cat << 'EOF' > "$OPTS_DIR/modernz.conf"
window_controls=no
show_window_title=yes

title_mbtn_left_command=ignore
title_mbtn_right_command=ignore
title_mbtn_mid_command=ignore

chapter_skip_buttons=yes
track_nextprev_buttons=yes
jump_buttons=yes
subtitles_button=yes
speed_button=yes
screenshot_button=yes
info_button=yes
fullscreen_button=yes
loop_button=no
ontop_button=yes
EOF

    curl -fsSL --retry 3 -o /tmp/thumbfast.zip "https://github.com/po5/thumbfast/archive/refs/heads/master.zip"
    mkdir -p /tmp/thumbfast_extract
    unzip -qo /tmp/thumbfast.zip -d /tmp/thumbfast_extract
    find /tmp/thumbfast_extract -name "thumbfast.lua" -exec cp -f {} "$SCRIPT_DIR/" \;
    rm -rf /tmp/thumbfast.zip /tmp/thumbfast_extract

    cat << EOF > "$OPTS_DIR/thumbfast.conf"
mpv_path=$MPV_BIN
network=yes
hwdec=yes
direct_io=yes
max_height=180
max_width=320
EOF
}
run_task "ModernZ UI, custom buttons & Thumbfast" install_ui
printf "\n"

# ------------------------------------------------------------------------------
# Step 6: Lua Controllers & Configuration Files
# ------------------------------------------------------------------------------
printf "[6/7] Generating Lua controllers and mpv configuration...\n"

install_configs() {
    cat << 'EOF' > "$SCRIPT_DIR/framegen_menu.lua"
local mp = require 'mp'
local assdraw = require 'mp.assdraw'

local fg_mult = 2.0
local current_profile = "off"
local menu_open = false
local selected = 1
local fps_active = false
local fps_timer = nil
local pip_active = false
local max_win_active = false
local night_mode = false
local ov = mp.create_osd_overlay("ass-events")

local shd_idle_timer = nil
local last_shd_interact = 0

local SHADER_FG   = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"
local SHADER_HIGH = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_L.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"
local SHADER_MID  = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"
local SHADER_LOW  = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_S.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"
local SHADER_DEN  = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl"

local function sync_active_profile()
    local s = mp.get_property("glsl-shaders", "")
    local vf = mp.get_property("vf", "")
    if vf and vf:find("vapoursynth") then
        if math.abs(fg_mult - 2.5) < 0.05 then
            current_profile = "fg_2.5"
        elseif math.abs(fg_mult - 3.0) < 0.05 then
            current_profile = "fg_3"
        else
            current_profile = "fg_2"
        end
    elseif s == "" or s == nil then
        current_profile = "off"
    elseif s:find("Upscale_CNN_x2_L") then
        current_profile = "high"
    elseif s:find("Upscale_CNN_x2_M") then
        current_profile = "mid"
    elseif s:find("Upscale_CNN_x2_S") then
        current_profile = "low"
    elseif s:find("Restore_CNN_M") then
        current_profile = "den"
    end
end

local function apply_fg(mult)
    fg_mult = mult
    local suffix = "20"
    if math.abs(mult - 2.5) < 0.05 then
        current_profile = "fg_2.5"
        suffix = "25"
    elseif math.abs(mult - 3.0) < 0.05 then
        current_profile = "fg_3"
        suffix = "30"
    else
        current_profile = "fg_2"
        suffix = "20"
    end

    mp.set_property("hwdec", "videotoolbox-copy")
    local vpy_path = mp.command_native({"expand-path", string.format("~~/fg_%s.vpy", suffix)})
    mp.set_property("vf", string.format("vapoursynth=file=%s:buffered-frames=4:concurrent-frames=6", vpy_path))
    mp.commandv("no-osd", "change-list", "glsl-shaders", "set", SHADER_FG)

    local src_fps = mp.get_property_number("container-fps", 23.976)
    local target = src_fps * mult
    mp.osd_message(string.format("MVTools FrameGen x%.1f + Anime4K CNN_M (%.2f FPS)", mult, target), 2)
end

local function apply_shader_only(id, shaders, label)
    current_profile = id
    mp.set_property("vf", "")
    mp.set_property("hwdec", "videotoolbox-copy")
    if shaders == "" then
        mp.commandv("no-osd", "change-list", "glsl-shaders", "clr", "")
    else
        mp.commandv("no-osd", "change-list", "glsl-shaders", "set", shaders)
    end
    mp.osd_message(label, 2)
end

local function toggle_night_mode()
    night_mode = not night_mode
    if night_mode then
        mp.set_property("af", "lavfi=[dynaudnorm=f=150:g=13:p=0.90:m=5]")
        mp.osd_message("Night Audio Mode: ON (Dynamic Range Compression)", 2)
    else
        mp.set_property("af", "")
        mp.osd_message("Night Audio Mode: OFF (Native Audio)", 2)
    end
    if menu_open then render_shader_menu() end
end

mp.register_script_message("toggle-night-mode", toggle_night_mode)

local menu_items = {
    { id = "fg_2",   label = "MVTools FrameGen x2 (48 FPS)   [Ctrl+1]", action = function() apply_fg(2.0) end },
    { id = "fg_2.5", label = "MVTools FrameGen x2.5 (60 FPS)",          action = function() apply_fg(2.5) end },
    { id = "fg_3",   label = "MVTools FrameGen x3 (72 FPS)",            action = function() apply_fg(3.0) end },
    { id = "high",   label = "Anime4K: High CNN_L (24 FPS)   [Ctrl+2]", action = function() apply_shader_only("high", SHADER_HIGH, "Anime4K: High CNN_L (24 FPS)") end },
    { id = "mid",    label = "Anime4K: Mid CNN_M (24 FPS)    [Ctrl+3]", action = function() apply_shader_only("mid", SHADER_MID, "Anime4K: Mid CNN_M (24 FPS)") end },
    { id = "low",    label = "Anime4K: Low CNN_S (24 FPS)    [Ctrl+4]", action = function() apply_shader_only("low", SHADER_LOW, "Anime4K: Low CNN_S (24 FPS)") end },
    { id = "den",    label = "Anime4K: Denoise (24 FPS)      [Ctrl+5]", action = function() apply_shader_only("den", SHADER_DEN, "Anime4K: Denoise (24 FPS)") end },
    { id = "off",    label = "Disable Shaders & FrameGen     [Ctrl+0]", action = function() apply_shader_only("off", "", "Shaders & FrameGen: OFF") end },
    { id = "night",  label = "Night Audio Mode (Dynaudnorm)       [d]", action = function() toggle_night_mode() end },
    { id = "fps",    label = "Toggle FPS & GPU Telemetry     [Ctrl+9]", action = function() mp.commandv("script-message", "toggle-fps") end }
}

mp.register_script_message("set-profile", function(prof)
    for i, item in ipairs(menu_items) do
        if item.id == prof then
            selected = i
            item.action()
            break
        end
    end
    if menu_open then render_shader_menu() end
end)

local function get_menu_box()
    local real_w, real_h = mp.get_osd_size()
    if not real_w or real_w == 0 then real_w, real_h = 1280, 720 end
    local h = 920
    local w = math.floor(real_w * (h / real_h))
    local bw = 415
    local row_h = 30
    local bh = 44 + (#menu_items * row_h)
    local bx = math.max(20, w - bw - 35)
    local by = math.max(20, h - bh - 105)
    return w, h, bx, by, bw, bh, row_h, real_w, real_h
end

local function get_virtual_mouse()
    local mx, my = mp.get_mouse_pos()
    local w, h, _, _, _, _, _, real_w, real_h = get_menu_box()
    return mx * (w / real_w), my * (h / real_h)
end

local function is_mouse_near_shader_menu()
    local mx, my = get_virtual_mouse()
    local _, _, bx, by, bw, bh = get_menu_box()
    local pad = 45
    return (mx >= bx - pad and mx <= bx + bw + pad and my >= by - pad and my <= by + bh + pad)
end

function render_shader_menu()
    if not menu_open then
        ov:remove()
        return
    end
    sync_active_profile()
    local w, h, bx, by, bw, bh, row_h = get_menu_box()
    local ass = assdraw.ass_new()

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\bord1.2\\shad0\\1c&H181414&\\1a&H12&\\3c&H555555&}", bx, by))
    ass:draw_start()
    ass:round_rect_cw(0, 0, bw, bh, 10)
    ass:draw_stop()

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fnHelvetica Neue\\fs17\\b1\\bord0\\1c&HFF9E3D&}MVTools FrameGen & Anime4K", bx + 16, by + 11))

    for i, item in ipairs(menu_items) do
        local iy = by + 36 + (i - 1) * row_h
        local is_active = (current_profile == item.id) or (item.id == "fps" and fps_active) or (item.id == "night" and night_mode)

        if i == selected then
            ass:new_event()
            ass:append(string.format("{\\an7\\pos(%d,%d)\\bord0\\1c&H3A3228&}", bx + 8, iy - 2))
            ass:draw_start()
            ass:round_rect_cw(0, 0, bw - 16, row_h - 2, 6)
            ass:draw_stop()
        end

        local color = is_active and "&H55FF55&" or (i == selected and "&HFFFFFF&" or "&HCCCCCC&")
        local prefix = is_active and "*  " or "    "
        ass:new_event()
        ass:append(string.format("{\\an7\\pos(%d,%d)\\fnHelvetica Neue\\fs15\\b%d\\bord0\\1c%s}%s%s", bx + 14, iy + 4, is_active and 1 or 0, color, prefix, item.label))
    end

    ov.res_x = w
    ov.res_y = h
    ov.data = ass.text
    ov:update()
end

mp.observe_property("glsl-shaders", "string", function()
    sync_active_profile()
    if menu_open then render_shader_menu() end
end)

local close_shader_menu

local function open_shader_menu()
    if menu_open then close_shader_menu() return end
    sync_active_profile()
    for i, item in ipairs(menu_items) do
        if item.id == current_profile then selected = i break end
    end
    menu_open = true
    last_shd_interact = mp.get_time()
    render_shader_menu()

    if shd_idle_timer then shd_idle_timer:kill() end
    shd_idle_timer = mp.add_periodic_timer(0.2, function()
        if not menu_open then return end
        if is_mouse_near_shader_menu() then
            last_shd_interact = mp.get_time()
        elseif (mp.get_time() - last_shd_interact) >= 1.5 then
            close_shader_menu()
        end
    end)

    mp.add_timeout(0.05, function()
        if not menu_open then return end
        mp.add_forced_key_binding("MBTN_LEFT", "shd-click", function(ev)
            if ev.event == "down" or ev.event == "press" then
                local mx, my = get_virtual_mouse()
                local _, _, bx, by, bw, bh, row_h = get_menu_box()
                if mx >= bx and mx <= bx + bw and my >= by + 36 and my <= by + bh then
                    local idx = math.floor((my - (by + 36)) / row_h) + 1
                    if idx >= 1 and idx <= #menu_items then
                        selected = idx
                        local chosen = menu_items[idx]
                        close_shader_menu()
                        chosen.action()
                    end
                else
                    close_shader_menu()
                end
            end
        end, { complex = true })

        mp.add_forced_key_binding("MOUSE_MOVE", "shd-move", function()
            local mx, my = get_virtual_mouse()
            local _, _, bx, by, bw, bh, row_h = get_menu_box()
            if is_mouse_near_shader_menu() then
                last_shd_interact = mp.get_time()
            end
            if mx >= bx and mx <= bx + bw and my >= by + 36 and my <= by + bh then
                local idx = math.floor((my - (by + 36)) / row_h) + 1
                if idx >= 1 and idx <= #menu_items and idx ~= selected then
                    selected = idx
                    render_shader_menu()
                end
            end
        end)
    end)

    mp.add_forced_key_binding("UP", "shd-up", function()
        last_shd_interact = mp.get_time() + 1.0
        selected = (selected - 2) % #menu_items + 1
        render_shader_menu()
    end, { repeatable = true })

    mp.add_forced_key_binding("DOWN", "shd-down", function()
        last_shd_interact = mp.get_time() + 1.0
        selected = selected % #menu_items + 1
        render_shader_menu()
    end, { repeatable = true })

    mp.add_forced_key_binding("ENTER", "shd-enter", function()
        local chosen = menu_items[selected]
        close_shader_menu()
        chosen.action()
    end)

    mp.add_forced_key_binding("ESC", "shd-esc", function()
        close_shader_menu()
    end)
end

close_shader_menu = function()
    if not menu_open then return end
    menu_open = false
    if shd_idle_timer then shd_idle_timer:kill(); shd_idle_timer = nil end
    mp.remove_key_binding("shd-click")
    mp.remove_key_binding("shd-move")
    mp.remove_key_binding("shd-up")
    mp.remove_key_binding("shd-down")
    mp.remove_key_binding("shd-enter")
    mp.remove_key_binding("shd-esc")
    ov:remove()
end

mp.register_script_message("toggle-shader-menu", open_shader_menu)
mp.register_script_message("toggle-fg-menu", open_shader_menu)

local function toggle_max_window()
    if mp.get_property_bool("fullscreen", false) then
        mp.set_property_bool("fullscreen", false)
        return
    end
    max_win_active = not max_win_active
    if max_win_active then
        mp.set_property("autofit-larger", "100%x100%")
        mp.set_property("geometry", "100%x100%+50%+50%")
        mp.set_property_bool("window-maximized", true)
    else
        mp.set_property_bool("window-maximized", false)
        mp.set_property("autofit-larger", "85%x85%")
        mp.set_property("geometry", "75%x75%+50%+50%")
    end
end

mp.register_script_message("toggle-max-window", toggle_max_window)

local function get_gpu_shader_ms()
    local passes = mp.get_property_native("vo-passes")
    if not passes then return 0.0, 0 end
    local total_ns = 0
    local pass_count = 0
    if passes.fresh then
        for _, p in ipairs(passes.fresh) do
            total_ns = total_ns + (p.last or 0)
            pass_count = pass_count + 1
        end
    end
    return (total_ns / 1000000.0), pass_count
end

local function update_fps_osd()
    if menu_open then return end

    local paused = mp.get_property_bool("pause", false)
    local spd = mp.get_property_number("speed", 1.0)
    local vf = mp.get_property("vf", "")
    local fg_on = (vf and vf:find("vapoursynth") ~= nil)
    local gpu_ms, pass_cnt = get_gpu_shader_ms()

    if paused then
        local status = fg_on and "MVTools ACTIVE [PAUSED]" or "OFF [PAUSED]"
        mp.osd_message(string.format("Rendered FPS: 0.00 FPS (PAUSED) | Speed: %.2fx\nGPU Shaders: %.2f ms (%d passes) | FrameGen: %s", spd, gpu_ms, pass_cnt, status), 1.5)
        return
    end

    local vf_fps = mp.get_property_number("estimated-vf-fps", 0) or 0
    local src_fps = mp.get_property_number("container-fps", 23.976) or 23.976
    local drops = mp.get_property_number("frame-drop-count", 0) or 0
    local real_fps = vf_fps * spd

    local status = fg_on and string.format("MVTools x%.1f ACTIVE (Drops: %d)", fg_mult, drops) or "OFF (Native)"
    mp.osd_message(string.format("Rendered FPS: %.2f FPS | Source: %.2f FPS | Speed: %.2fx\nGPU Shaders: %.2f ms/frame (%d passes) | FrameGen: %s", real_fps, src_fps, spd, gpu_ms, pass_cnt, status), 1.5)
end

mp.observe_property("pause", "bool", function()
    if fps_active then update_fps_osd() end
end)

mp.observe_property("speed", "number", function()
    if fps_active then update_fps_osd() end
end)

mp.register_script_message("toggle-fps", function()
    fps_active = not fps_active
    if fps_active then
        update_fps_osd()
        fps_timer = mp.add_periodic_timer(0.35, update_fps_osd)
    else
        if fps_timer then fps_timer:kill() end
        mp.osd_message("", 0)
    end
end)

mp.register_script_message("toggle-pip", function()
    pip_active = not pip_active
    if pip_active then
        mp.set_property_bool("fullscreen", false)
        mp.set_property_bool("ontop", true)
        mp.set_property_bool("border", false)
        mp.set_property("geometry", "28%x28%+98%+95%")
        mp.osd_message("Picture-in-Picture: ON", 1.5)
    else
        mp.set_property_bool("ontop", false)
        mp.set_property_bool("border", true)
        mp.set_property("geometry", "75%x75%+50%+50%")
        mp.osd_message("Picture-in-Picture: OFF", 1.5)
    end
end)
EOF

    cat << 'EOF' > "$SCRIPT_DIR/speed_slider.lua"
local mp = require 'mp'
local assdraw = require 'mp.assdraw'

local open = false
local dragging = false
local ov = mp.create_osd_overlay("ass-events")
local spd_idle_timer = nil
local last_spd_interact = 0

local MIN_SPEED = 0.25
local MAX_SPEED = 10.0
local RATIO = MAX_SPEED / MIN_SPEED

local function speed_to_t(spd)
    spd = math.max(MIN_SPEED, math.min(MAX_SPEED, spd))
    return math.log(spd / MIN_SPEED) / math.log(RATIO)
end

local function t_to_speed(t)
    t = math.max(0.0, math.min(1.0, t))
    local raw = MIN_SPEED * (RATIO ^ t)
    if math.abs(raw - 1.0) < 0.03 then return 1.0 end
    if raw < 2.0 then
        return math.floor(raw * 20 + 0.5) / 20
    else
        return math.floor(raw * 10 + 0.5) / 10
    end
end

local function get_box()
    local real_w, real_h = mp.get_osd_size()
    if not real_w or real_w == 0 then real_w, real_h = 1280, 720 end
    local h = 920
    local w = math.floor(real_w * (h / real_h))
    local bw, bh = 310, 88
    local bx = math.max(20, w - bw - 35)
    local by = math.max(20, h - bh - 105)
    return w, h, bx, by, bw, bh, real_w, real_h
end

local function get_virtual_mouse()
    local mx, my = mp.get_mouse_pos()
    local w, h, _, _, _, _, real_w, real_h = get_box()
    return mx * (w / real_w), my * (h / real_h)
end

local function is_mouse_near_speed_box()
    local mx, my = get_virtual_mouse()
    local _, _, bx, by, bw, bh = get_box()
    local pad = 45
    return (mx >= bx - pad and mx <= bx + bw + pad and my >= by - pad and my <= by + bh + pad)
end

local function render()
    if not open then
        ov:remove()
        return
    end
    local w, h, bx, by, bw, bh = get_box()
    local spd = mp.get_property_number("speed", 1.0)
    local t = speed_to_t(spd)

    local sx = bx + 18
    local sw = bw - 36
    local sy = by + 50
    local kx = sx + t * sw

    local ass = assdraw.ass_new()
    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\bord1.2\\shad0\\1c&H181414&\\1a&H12&\\3c&H555555&}", bx, by))
    ass:draw_start()
    ass:round_rect_cw(0, 0, bw, bh, 10)
    ass:draw_stop()

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fnHelvetica Neue\\fs16\\b1\\bord0\\1c&HFFFFFF&}Speed: %.2fx", bx + 16, by + 10, spd))

    ass:new_event()
    ass:append(string.format("{\\an9\\pos(%d,%d)\\fnHelvetica Neue\\fs12\\bord0\\1c&HAAAAAA&}[Right-Click = 1.0x]", bx + bw - 14, by + 13))

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\bord0\\1c&H4A4A52&}", sx, sy - 2))
    ass:draw_start()
    ass:round_rect_cw(0, 0, sw, 4, 2)
    ass:draw_stop()

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\bord0\\1c&HFF9E3D&}", sx, sy - 2))
    ass:draw_start()
    ass:round_rect_cw(0, 0, math.max(4, t * sw), 4, 2)
    ass:draw_stop()

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\bord1.2\\1c&HFFFFFF&\\3c&HFF9E3D&}", kx - 5, sy - 6))
    ass:draw_start()
    ass:round_rect_cw(0, 0, 10, 10, 5)
    ass:draw_stop()

    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fnHelvetica Neue\\fs12\\bord0\\1c&H999999&}0.25x          1.0x                      10x", sx, sy + 11))

    ov.res_x = w
    ov.res_y = h
    ov.data = ass.text
    ov:update()
end

local function set_from_mouse()
    local mx, _ = get_virtual_mouse()
    local _, _, bx, _, bw, _ = get_box()
    local sx = bx + 18
    local sw = bw - 36
    local t = (mx - sx) / sw
    t = math.max(0.0, math.min(1.0, t))
    mp.set_property_number("speed", t_to_speed(t))
    last_spd_interact = mp.get_time()
    render()
end

local close_menu

local function open_menu()
    if open then close_menu() return end
    open = true
    last_spd_interact = mp.get_time()
    mp.set_property_bool("window-dragging", false)
    render()

    if spd_idle_timer then spd_idle_timer:kill() end
    spd_idle_timer = mp.add_periodic_timer(0.2, function()
        if not open then return end
        if dragging or is_mouse_near_speed_box() then
            last_spd_interact = mp.get_time()
        elseif (mp.get_time() - last_spd_interact) >= 1.5 then
            close_menu()
        end
    end)

    mp.add_timeout(0.05, function()
        if not open then return end
        mp.add_forced_key_binding("MBTN_LEFT", "spd-click", function(ev)
            if ev.event == "down" or ev.event == "press" then
                local mx, my = get_virtual_mouse()
                local _, _, bx, by, bw, bh = get_box()
                if mx >= bx and mx <= bx + bw and my >= by and my <= by + bh then
                    dragging = true
                    set_from_mouse()
                else
                    close_menu()
                end
            elseif ev.event == "up" then
                dragging = false
            end
        end, { complex = true })

        mp.add_forced_key_binding("MOUSE_MOVE", "spd-move", function()
            if is_mouse_near_speed_box() then
                last_spd_interact = mp.get_time()
            end
            if dragging then set_from_mouse() end
        end)
    end)

    mp.add_forced_key_binding("MBTN_RIGHT", "spd-reset", function()
        last_spd_interact = mp.get_time() + 1.0
        mp.set_property_number("speed", 1.0)
        render()
    end)

    mp.add_forced_key_binding("RIGHT", "spd-right", function()
        last_spd_interact = mp.get_time() + 1.0
        local t = speed_to_t(mp.get_property_number("speed", 1.0)) + 0.04
        mp.set_property_number("speed", t_to_speed(t))
        render()
    end, { repeatable = true })

    mp.add_forced_key_binding("LEFT", "spd-left", function()
        last_spd_interact = mp.get_time() + 1.0
        local t = speed_to_t(mp.get_property_number("speed", 1.0)) - 0.04
        mp.set_property_number("speed", t_to_speed(t))
        render()
    end, { repeatable = true })

    mp.add_forced_key_binding("ESC", "spd-esc", close_menu)
end

close_menu = function()
    if not open then return end
    open = false
    dragging = false
    if spd_idle_timer then spd_idle_timer:kill(); spd_idle_timer = nil end
    mp.remove_key_binding("spd-click")
    mp.remove_key_binding("spd-move")
    mp.remove_key_binding("spd-reset")
    mp.remove_key_binding("spd-right")
    mp.remove_key_binding("spd-left")
    mp.remove_key_binding("spd-esc")
    ov:remove()
end

mp.register_script_message("toggle-speed-slider", open_menu)
EOF

    cat << 'EOF' > "$MPV_DIR/mpv.conf"
# --- Video & Custom Compiled GPU Backend (libplacebo + shaderc + Vulkan/Metal) ---
vo=gpu-next
gpu-api=vulkan
hwdec=videotoolbox-copy
hwdec-codecs=all
keep-open=yes
gpu-shader-cache-dir="~~/cache"
watch-later-options-remove=sub-pos

# --- macOS Media Keys / AirPods & IPC Socket (Seanime / AniList) ---
input-media-keys=yes
input-ipc-server=/tmp/mpvsocket

# --- Demuxer & Memory Cache ---
cache=yes
demuxer-max-bytes=400MiB
demuxer-max-back-bytes=150MiB

# --- Window, UI & OSD Alignment ---
window-dragging=no
input-vo-keyboard=yes
autofit=75%
autofit-larger=85%x85%
geometry=50%:50%
keepaspect-window=yes
cursor-autohide=1000
osc=no
osd-bar=no
border=yes
osd-margin-x=28
osd-margin-y=24
osd-font="Helvetica Neue"
osd-font-size=26

# --- Default Shaders & Sync (Native 24fps at startup) ---
glsl-shaders=""
video-sync=audio
interpolation=no

# --- Audio (CoreAudio Glitch-Free Bluetooth/AirPods) ---
ao=coreaudio
audio-buffer=0.25
audio-pitch-correction=yes

# --- Subtitles & Languages ---
alang=fr,fre,fra,en,eng,ja,jpn
slang=forced,fr-forced,fra-forced,fre-forced,en-forced,eng-forced,fr,fre,fra,en,eng
sub-auto=fuzzy
sub-font="Helvetica Neue"
sub-font-size=46
sub-border-size=2.4
sub-shadow-offset=1
sub-blur=0.2
blend-subtitles=video

# --- High-Quality Scaling, Debanding & HDR Tone-Mapping ---
deband=yes
deband-iterations=1
deband-threshold=35
scale=spline36
cscale=spline36
dscale=mitchell
dither-depth=auto
target-trc=auto
tone-mapping=bt.2446a
gamut-mapping-mode=clip
EOF

    cat << 'EOF' > "$MPV_DIR/input.conf"
WHEEL_UP ignore
WHEEL_DOWN ignore
WHEEL_LEFT ignore
WHEEL_RIGHT ignore

i ignore
I ignore

MBTN_LEFT_DBL cycle fullscreen
f cycle fullscreen
p script-message toggle-pip
Ctrl+p script-message toggle-pip

g script-message toggle-shader-menu
Ctrl+f script-message toggle-shader-menu
v script-message toggle-speed-slider
d script-message toggle-night-mode

n add chapter 1
b add chapter -1
PGDWN add chapter 1
PGUP add chapter -1

1 script-message set-profile fg_2
Ctrl+1 script-message set-profile fg_2

2 script-message set-profile high
Ctrl+2 script-message set-profile high

3 script-message set-profile mid
Ctrl+3 script-message set-profile mid

4 script-message set-profile low
Ctrl+4 script-message set-profile low

5 script-message set-profile den
Ctrl+5 script-message set-profile den

0 script-message set-profile off
Ctrl+0 script-message set-profile off

9 script-message toggle-fps
Ctrl+9 script-message toggle-fps
EOF

    if command -v yabai >/dev/null 2>&1; then
        yabai -m rule --add app="^mpv$" manage=off 2>/dev/null || true
    fi
}
run_task "Lua controllers, mpv.conf & input.conf" install_configs
printf "\n"

# ------------------------------------------------------------------------------
# Step 7: Final Verification
# ------------------------------------------------------------------------------
printf "[7/7] Verifying installation...\n"

verify_setup() {
    "$MPV_BIN" --vf=help | grep -qi "vapoursynth"
    "$PY_BIN" -c "
import vapoursynth as vs
core = vs.core
if not hasattr(core, 'mv'):
    core.std.LoadPlugin(path='$BREW_PREFIX/lib/vapoursynth/mvtools.dylib')
assert hasattr(core, 'mv'), 'MVTools plugin missing'
"
}
run_task "Verifying VapourSynth bridge and MVTools plugin" verify_setup

printf "\n==============================================================================\n"
printf "  Installation complete. /Applications/mpv.app is ready.\n"
printf "  Build logs saved to: %s\n" "$LOG_FILE"
printf "==============================================================================\n"
