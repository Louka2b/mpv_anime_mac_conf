#!/usr/bin/env bash
# ==============================================================================
# mpv-macos-anime — High-Performance Anime4K & FrameGen Setup for macOS (M-Series)
# ==============================================================================

set -euo pipefail

if [ -d "/opt/homebrew/bin" ]; then
    BREW_PREFIX="/opt/homebrew"
elif [ -d "/usr/local/bin" ]; then
    BREW_PREFIX="/usr/local"
else
    echo "❌ Erreur : Homebrew n'est pas installé (https://brew.sh)."
    exit 1
fi

export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
MPV_BIN="$BREW_PREFIX/bin/mpv"

MPV_DIR="$HOME/.config/mpv"
SHADER_DIR="$MPV_DIR/shaders"
SCRIPT_DIR="$MPV_DIR/scripts"
OPTS_DIR="$MPV_DIR/script-opts"
FONT_DIR="$MPV_DIR/fonts"
CACHE_DIR="$MPV_DIR/cache"

echo "▶ [1/6] Nettoyage de l'ancienne configuration mpv..."
killall mpv 2>/dev/null || true
rm -rf "$MPV_DIR" "$HOME/Library/Caches/io.mpv" "$HOME/.cache/mpv" 2>/dev/null || true
mkdir -p "$MPV_DIR" "$SHADER_DIR" "$SCRIPT_DIR" "$OPTS_DIR" "$FONT_DIR" "$CACHE_DIR"

echo "▶ [2/6] Vérification de mpv via Homebrew..."
brew uninstall --cask mpv 2>/dev/null || true
if ! brew list mpv >/dev/null 2>&1; then
    brew install mpv
fi

echo "▶ [3/6] Création de l'application native /Applications/mpv.app..."
mkdir -p /Applications/mpv.app/Contents/MacOS
cat << EOF > /Applications/mpv.app/Contents/MacOS/mpv
#!/bin/sh
export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:/usr/local/bin:\$PATH"
exec "$MPV_BIN" --player-operation-mode=pseudo-gui --config-dir="\$HOME/.config/mpv" "\$@"
EOF
chmod +x /Applications/mpv.app/Contents/MacOS/mpv

cat << 'EOF' > /Applications/mpv.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>mpv</string>
    <key>CFBundleIdentifier</key>
    <string>io.mpv</string>
    <key>CFBundleName</key>
    <string>mpv</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
EOF

echo "▶ [4/6] Installation des shaders Anime4K v4.0.1 & Optical Flow..."
curl -fsSL --retry 3 -o /tmp/Anime4K.zip "https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip"
unzip -qo /tmp/Anime4K.zip -d "$SHADER_DIR"
rm -f /tmp/Anime4K.zip

# Shader Optical Flow Ultra-Fast (Single-Pass Horizontal + Vertical Luma Flow < 1.5ms sur M5 Air)
cat << 'EOF' > "$SHADER_DIR/MotionInterpolation.glsl"
//!HOOK MAIN
//!BIND HOOKED
//!BIND PREV
//!DESC Ultra-Fast Luma Optical Flow (M5 Air 60fps)

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 pt = HOOKED_pt * 1.5;

    vec4 cur = HOOKED_tex(uv);
    vec4 prev_c = PREV_tex(uv);

    float diff = abs(cur.g - prev_c.g);
    if (diff < 0.015 || diff > 0.32) {
        return cur;
    }

    vec4 prev_l = PREV_tex(uv - vec2(pt.x, 0.0));
    vec4 prev_r = PREV_tex(uv + vec2(pt.x, 0.0));
    vec4 best_prev = prev_c;
    float min_d = diff;

    float dl = abs(cur.g - prev_l.g);
    if (dl < min_d) { min_d = dl; best_prev = prev_l; }

    float dr = abs(cur.g - prev_r.g);
    if (dr < min_d) { best_prev = prev_r; }

    return mix(cur, best_prev, 0.30);
}
EOF

echo "▶ [5/6] Installation de ModernZ UI & Thumbfast..."
curl -fsSL --retry 3 -o /tmp/ModernZ.zip "https://github.com/Samillion/ModernZ/archive/refs/heads/main.zip"
mkdir -p /tmp/modernz_extract
unzip -qo /tmp/ModernZ.zip -d /tmp/modernz_extract
find /tmp/modernz_extract -name "modernz.lua" -exec cp -f {} "$SCRIPT_DIR/" \;
find /tmp/modernz_extract -name "*.ttf" -exec cp -f {} "$FONT_DIR/" \;
mkdir -p "$HOME/Library/Fonts"
cp -f "$FONT_DIR"/*.ttf "$HOME/Library/Fonts/" 2>/dev/null || true
rm -rf /tmp/ModernZ.zip /tmp/modernz_extract

python3 - "$SCRIPT_DIR/modernz.lua" << 'PYEOF'
import sys

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
                el.tooltipF = "Menu FrameGen & Shaders Anime4K"
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
                        return "Mode Nuit Audio : ON (Clic pour désactiver)"
                    end
                    return "Mode Nuit Audio : OFF (Normalisation voix/explosions)"
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

target = "function render_elements("
if target in code:
    idx = code.find(target)
    line_start = code.rfind("\n", 0, idx) + 1
    newline_after = code.find("\n", idx) + 1
    code = code[:line_start] + hook_lua + "\n" + code[line_start:newline_after] + "    _custom_patch_elements()\n" + code[newline_after:]
    with open(path, "w", encoding="utf-8") as f:
        f.write(code)
PYEOF

cat << 'EOF' > "$OPTS_DIR/modernz.conf"
window_controls=no
show_window_title=yes
bottomhover=yes
seekbarhandlesize=0.8

title_mbtn_left_command=ignore
title_mbtn_right_command=ignore
title_mbtn_mid_command=ignore

chapter_skip_buttons=yes
track_nextprev_buttons=yes
jump_buttons=yes
subtitles_button=yes
audio_button=yes
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

echo "▶ [6/6] Génération des scripts Lua et des fichiers de configuration..."

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

-- Chaîne FrameGen optimisée M5 Air (< 5ms GPU/frame -> 2.50 VSync Ratio & 0 Mistimed)
local SHADER_FG   = "~~/shaders/MotionInterpolation.glsl:~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_S.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"
-- High (24 FPS natif -> budget de 41ms/frame, supporte le CNN_M sans aucun drop)
local SHADER_HIGH = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"
-- Mid : Restore_CNN_S + Upscale_CNN_x2_S
local SHADER_MID  = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_S.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"
-- Low : Upscale_CNN_x2_S
local SHADER_LOW  = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"
-- Denoise : Restore_CNN_S
local SHADER_DEN  = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_S.glsl"

local function sync_active_profile()
    local s = mp.get_property("glsl-shaders", "")
    local interp = mp.get_property_bool("interpolation", false)
    if s == "" or s == nil then
        current_profile = "off"
    elseif s:find("MotionInterpolation") and interp then
        if math.abs(fg_mult - 2.5) < 0.05 then
            current_profile = "fg_2.5"
        elseif math.abs(fg_mult - 3.0) < 0.05 then
            current_profile = "fg_3"
        else
            current_profile = "fg_2"
        end
    elseif s:find("Upscale_CNN_x2_M") then
        current_profile = "high"
    elseif s:find("Restore_CNN_S") and s:find("Upscale_CNN_x2_S") then
        current_profile = "mid"
    elseif s:find("Upscale_CNN_x2_S") then
        current_profile = "low"
    elseif s:find("Restore_CNN_S") then
        current_profile = "den"
    end
end

local function apply_fg(mult)
    fg_mult = mult
    if math.abs(mult - 2.5) < 0.05 then
        current_profile = "fg_2.5"
        mp.set_property("tscale", "linear")
    elseif math.abs(mult - 3.0) < 0.05 then
        current_profile = "fg_3"
        mp.set_property("tscale", "mitchell")
    else
        current_profile = "fg_2"
        mp.set_property("tscale", "oversample")
    end
    mp.set_property("override-display-fps", "0")
    mp.commandv("no-osd", "change-list", "glsl-shaders", "set", SHADER_FG)
    mp.set_property("video-sync", "display-resample")
    mp.set_property_bool("interpolation", true)
    local src_fps = mp.get_property_number("container-fps", 23.976)
    local disp_fps = mp.get_property_number("display-fps", 60.0)
    local target = math.min(disp_fps, src_fps * mult)
    mp.osd_message(string.format("Anime4K + FrameGen x%.1f (%.2f FPS)", mult, target), 2)
end

local function apply_shader_only(id, shaders, label)
    current_profile = id
    mp.set_property("override-display-fps", "0")
    mp.set_property_bool("interpolation", false)
    mp.set_property("video-sync", "audio")
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
        mp.osd_message("Mode Nuit Audio : ON (Voix équilibrées / Explosions réduites)", 2)
    else
        mp.set_property("af", "")
        mp.osd_message("Mode Nuit Audio : OFF (Audio dynamique natif)", 2)
    end
    if menu_open then render_shader_menu() end
end

mp.register_script_message("toggle-night-mode", toggle_night_mode)

local menu_items = {
    { id = "fg_2",   label = "FrameGen x2 (48 FPS - Défaut)  [Ctrl+1]", action = function() apply_fg(2.0) end },
    { id = "fg_2.5", label = "FrameGen x2.5 (60 FPS Natif)",            action = function() apply_fg(2.5) end },
    { id = "fg_3",   label = "FrameGen x3 (Smooth Max)",                action = function() apply_fg(3.0) end },
    { id = "high",   label = "Anime4K : High (24 FPS)        [Ctrl+2]", action = function() apply_shader_only("high", SHADER_HIGH, "Anime4K : High (24 FPS)") end },
    { id = "mid",    label = "Anime4K : Mid (24 FPS)         [Ctrl+3]", action = function() apply_shader_only("mid", SHADER_MID, "Anime4K : Mid (24 FPS)") end },
    { id = "low",    label = "Anime4K : Low (24 FPS)         [Ctrl+4]", action = function() apply_shader_only("low", SHADER_LOW, "Anime4K : Low (24 FPS)") end },
    { id = "den",    label = "Anime4K : Denoise (24 FPS)     [Ctrl+5]", action = function() apply_shader_only("den", SHADER_DEN, "Anime4K : Denoise (24 FPS)") end },
    { id = "off",    label = "Désactiver Shaders + FrameGen  [Ctrl+0]", action = function() apply_shader_only("off", "", "Shaders + FrameGen : Off") end },
    { id = "night",  label = "Mode Nuit Audio (Dynaudnorm)        [d]", action = function() toggle_night_mode() end },
    { id = "fps",    label = "Afficher / Masquer FPS         [Ctrl+9]", action = function() mp.commandv("script-message", "toggle-fps") end }
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
    local bw = 410
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
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fnHelvetica Neue\\fs17\\b1\\bord0\\1c&HFF9E3D&}Menu Frame Generation & Shaders", bx + 16, by + 11))

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
        local prefix = is_active and "●  " or "     "
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

local last_mistimed = 0
local last_check_t = mp.get_time()

local function update_fps_osd()
    if menu_open then return end

    local paused = mp.get_property_bool("pause", false)
    local spd = mp.get_property_number("speed", 1.0)
    local shaders = mp.get_property("glsl-shaders", "")
    local interp = mp.get_property_bool("interpolation", false)
    local fg_on = (string.find(shaders, "MotionInterpolation") ~= nil) and interp

    if paused then
        local status = fg_on and "ON [PAUSE]" or "OFF [PAUSE]"
        mp.osd_message(string.format("FPS Rendus GPU : 0.00 FPS (PAUSE) | Vitesse : %.2fx\nDécodage Source : 0.00 FPS | FrameGen : %s", spd, status), 1.5)
        return
    end

    local vf_fps = mp.get_property_number("estimated-vf-fps", 0) or 0
    local disp_fps = mp.get_property_number("estimated-display-fps", 60.0) or 60.0
    local vsync_ratio = mp.get_property_number("vsync-ratio", 1.0) or 1.0
    local mistimed = mp.get_property_number("mistimed-frame-count", 0) or 0

    local now = mp.get_time()
    local dt = math.max(0.1, now - last_check_t)
    local mistimed_per_sec = math.max(0, (mistimed - last_mistimed) / dt)
    last_mistimed = mistimed
    last_check_t = now

    local decoded_live = vf_fps * spd
    local gpu_rendered_fps

    if fg_on then
        local target_mult = (fg_mult == 2.0) and 2.0 or math.max(fg_mult, vsync_ratio)
        local raw_interp_fps = math.min(disp_fps, decoded_live * target_mult)
        gpu_rendered_fps = math.max(decoded_live, raw_interp_fps - mistimed_per_sec)
    else
        gpu_rendered_fps = math.min(disp_fps, decoded_live)
    end

    local status = fg_on and string.format("ACTIF x%.1f (Ratio VSync : %.2f | Mistimed : %d)", fg_mult, vsync_ratio, mistimed) or "OFF (Natif)"
    mp.osd_message(string.format("FPS Rendus GPU : %.2f FPS | Vitesse : %.2fx\nDécodage Source : %.2f FPS | FrameGen : %s", gpu_rendered_fps, spd, decoded_live, status), 1.5)
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
        last_check_t = mp.get_time()
        last_mistimed = mp.get_property_number("mistimed-frame-count", 0) or 0
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
        mp.osd_message("Picture-in-Picture : ON", 1.5)
    else
        mp.set_property_bool("ontop", false)
        mp.set_property_bool("border", true)
        mp.set_property("geometry", "75%x75%+50%+50%")
        mp.osd_message("Picture-in-Picture : OFF", 1.5)
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
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fnHelvetica Neue\\fs16\\b1\\bord0\\1c&HFFFFFF&}Vitesse : %.2fx", bx + 16, by + 10, spd))

    ass:new_event()
    ass:append(string.format("{\\an9\\pos(%d,%d)\\fnHelvetica Neue\\fs12\\bord0\\1c&HAAAAAA&}[Clic droit = 1.0x]", bx + bw - 14, by + 13))

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

# Core mpv.conf (Vulkan/Metal gpu-next backend + OSD margin fix + Fast M5 scaling)
cat << 'EOF' > "$MPV_DIR/mpv.conf"
# --- Video & Metal/Vulkan Acceleration (M5 Air 60fps Zero-Mistimed) ---
vo=gpu-next
gpu-api=vulkan
hwdec=videotoolbox
hwdec-codecs=all
keep-open=yes
gpu-shader-cache-dir="~~/cache"

# --- macOS Media Keys / AirPods & IPC Socket (Seanime / AniList) ---
input-media-keys=yes
input-ipc-server=/tmp/mpvsocket

# --- Demuxer & Memory Cache ---
cache=yes
demuxer-max-bytes=400MiB
demuxer-max-back-bytes=150MiB

# --- Window, UI & OSD Alignment (fixes clipped left text) ---
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
osd-font-size=28

# --- Default Shaders & Sync (Native 24fps at startup) ---
glsl-shaders=""
video-sync=audio
interpolation=no
tscale=oversample

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
blend-subtitles=no

# --- Fast Scaling, Debanding & Zero-Lag HDR Tone-Mapping ---
deband=no
scale=bilinear
cscale=bilinear
dscale=bilinear
dither-depth=no
target-trc=auto
tone-mapping=spline
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
& script-message set-profile fg_2
Ctrl+1 script-message set-profile fg_2

2 script-message set-profile high
é script-message set-profile high
Ctrl+2 script-message set-profile high

3 script-message set-profile mid
" script-message set-profile mid
Ctrl+3 script-message set-profile mid

4 script-message set-profile low
' script-message set-profile low
Ctrl+4 script-message set-profile low

5 script-message set-profile den
( script-message set-profile den
Ctrl+5 script-message set-profile den

0 script-message set-profile off
à script-message set-profile off
Ctrl+0 script-message set-profile off

9 script-message toggle-fps
ç script-message toggle-fps
Ctrl+9 script-message toggle-fps
EOF

if command -v yabai >/dev/null 2>&1; then
    yabai -m rule --add app="^mpv$" manage=off 2>/dev/null || true
fi

echo "✅ Installation terminée avec succès ! mpv.app est prêt dans /Applications."
