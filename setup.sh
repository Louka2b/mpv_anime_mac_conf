#!/bin/bash
set -e

MPV_DIR="$HOME/.config/mpv"
SHADER_DIR="$MPV_DIR/shaders"
SCRIPT_DIR="$MPV_DIR/scripts"
FONT_DIR="$MPV_DIR/fonts"

mkdir -p "$MPV_DIR" "$SHADER_DIR" "$SCRIPT_DIR" "$FONT_DIR"

curl -sL -o /tmp/Anime4K.zip "https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip"
unzip -qo /tmp/Anime4K.zip -d "$SHADER_DIR"
rm -f /tmp/Anime4K.zip

curl -sL -o "$SCRIPT_DIR/modernx.lua" "https://raw.githubusercontent.com/cyl0/ModernX/main/modernx.lua"
curl -sL -o "$FONT_DIR/Material-Design-Iconic-Font.ttf" "https://raw.githubusercontent.com/cyl0/ModernX/main/Material-Design-Iconic-Font.ttf"

cat << 'EOF' > "$MPV_DIR/mpv.conf"
profile=gpu-hq
vo=gpu-next
hwdec=auto-safe
macos-force-dedicated-gpu=no
keep-open=yes
autofit-larger=90%x90%
cursor-autohide=1000

osc=no
osd-bar=no
border=yes

alang=fr,fre,fra,en,eng,ja,jpn

slang=forced,fr-forced,fra-forced,fre-forced,en-forced,eng-forced,fr,fre,fra,en,eng
sub-auto=fuzzy
sub-font="Helvetica Neue"
sub-font-size=46
sub-border-size=2.4
sub-shadow-offset=1
sub-blur=0.2

deband=yes
scale=ewa_lanczossharp
cscale=ewa_lanczossharp
EOF

cat << 'EOF' > "$MPV_DIR/input.conf"
Ctrl+1 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_VL.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K : Max"
Ctrl+2 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_L.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"; show-text "Anime4K : High"
Ctrl+3 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_S.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"; show-text "Anime4K : Mid"
Ctrl+4 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_S.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl"; show-text "Anime4K : Low"
Ctrl+5 no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_M.glsl"; show-text "Anime4K : Denoise"
Ctrl+0 no-osd change-list glsl-shaders clr; show-text "Anime4K : Off"
Ctrl+` no-osd change-list glsl-shaders clr; show-text "Anime4K : Off"
EOF
