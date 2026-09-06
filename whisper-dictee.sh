#!/bin/bash
# Dictée vocale — script "toggle" (Wayland / Kubuntu).
#
# 1er appel  : démarre l'enregistrement du micro.
# 2e appel   : arrête, envoie l'audio au serveur Whisper, injecte le texte
#              dans la fenêtre active via ydotool.
#
# À lier à un raccourci clavier KDE (voir README).
#
# Config optionnelle : ~/.config/whisper-dictee.conf (paires VAR=valeur), ou
# variables d'environnement :
#   WHISPER_SOCKET   socket du serveur   (défaut : $XDG_RUNTIME_DIR/whisper.sock)
#   DICTEE_SOURCE    source PipeWire     (défaut : source par défaut du système)
#   DICTEE_INJECT    type | clipboard | keys   (défaut : type = presse-papier + Ctrl+V ;
#                    clipboard = copie seule ; keys = frappe ydotool brute, US-QWERTY)
#   DICTEE_NOTIFY    1 pour les notifications KDE, 0 pour rien  (défaut : 1)

set -u

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/whisper-dictee.conf"
[ -f "$CONF" ] && . "$CONF"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
WHISPER_SOCKET="${WHISPER_SOCKET:-$RUNTIME_DIR/whisper.sock}"
DICTEE_INJECT="${DICTEE_INJECT:-type}"
DICTEE_NOTIFY="${DICTEE_NOTIFY:-1}"
export YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-$RUNTIME_DIR/.ydotool_socket}"

PID_FILE="$RUNTIME_DIR/whisper-dictee.pid"
WAV_FILE="$RUNTIME_DIR/whisper-dictee.wav"

notify() {
    [ "$DICTEE_NOTIFY" = "1" ] || return 0
    command -v notify-send >/dev/null || return 0
    notify-send -a "Dictée" -t "${2:-2000}" -h string:x-canonical-private-synchronous:dictee "$1"
}

# ---------------------------------------------------------------- arrêt + transcription
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    REC_PID="$(cat "$PID_FILE")"
    kill -INT "$REC_PID" 2>/dev/null || kill -TERM "$REC_PID" 2>/dev/null
    for _ in $(seq 1 20); do kill -0 "$REC_PID" 2>/dev/null || break; sleep 0.1; done
    kill -0 "$REC_PID" 2>/dev/null && kill -KILL "$REC_PID" 2>/dev/null
    rm -f "$PID_FILE"

    if [ ! -s "$WAV_FILE" ]; then
        notify "❌ Aucun son enregistré"
        exit 1
    fi
    if [ ! -S "$WHISPER_SOCKET" ]; then
        notify "❌ Serveur Whisper injoignable — systemctl --user status whisper-server" 4000
        exit 1
    fi

    notify "✍️  Transcription…"
    TEXTE="$(printf '%s\n' "$WAV_FILE" | socat -t 120 - "UNIX-CONNECT:$WHISPER_SOCKET" 2>/dev/null)"
    rm -f "$WAV_FILE"

    TEXTE="${TEXTE#"${TEXTE%%[![:space:]]*}"}"   # trim gauche
    TEXTE="${TEXTE%"${TEXTE##*[![:space:]]}"}"   # trim droite
    if [ -z "$TEXTE" ]; then
        notify "🤷 Rien compris"
        exit 0
    fi

    # Injection. Défaut ("type") : presse-papier + collage Ctrl+V simulé.
    #   - KWin n'expose pas virtual-keyboard → wtype KO sur ce poste.
    #   - `ydotool type` frappe en positions US-QWERTY → texte mélangé en AZERTY.
    #   - Ctrl+V par keycodes evdev (29=Ctrl, 47=V) est indépendant du layout.
    # "clipboard" = copie seule (collage manuel) ; "keys" = ancienne frappe ydotool.
    case "$DICTEE_INJECT" in
        clipboard)
            printf '%s' "$TEXTE" | wl-copy
            ;;
        keys)
            printf '%s' "$TEXTE" | ydotool type --key-delay 2 --file -
            ;;
        type|both|*)
            printf '%s' "$TEXTE" | wl-copy
            sleep 0.15
            ydotool key 29:1 47:1 47:0 29:0
            ;;
    esac
    notify "✅ $TEXTE" 3000
    exit 0
fi

# ---------------------------------------------------------------- démarrage de l'enregistrement
rm -f "$PID_FILE" "$WAV_FILE"
REC_ARGS=(--rate=16000 --channels=1 --format=s16)
[ -n "${DICTEE_SOURCE:-}" ] && REC_ARGS+=(--target="$DICTEE_SOURCE")
setsid pw-record "${REC_ARGS[@]}" "$WAV_FILE" >/dev/null 2>&1 &
echo $! > "$PID_FILE"
notify "🎙️  Enregistrement… (raccourci à nouveau pour arrêter)" 5000
