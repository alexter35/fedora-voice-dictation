#!/bin/bash
# ============================================================
#  Voice dictation — installation Kubuntu (Ubuntu 26.04, KDE/Wayland)
#  Portage du repo Fedora d'origine.
#  Cible testée : Ryzen 5700G + GTX 1070 Ti, NVIDIA 580, Python 3.14.
# ============================================================
set -euo pipefail

REPO_PATH="$(cd "$(dirname "$0")" && pwd)"
VENV="$HOME/whisper-env"
PYBIN="${PYBIN:-python3}"

echo "== [1/6] Paquets système (apt) =="
sudo apt-get update
sudo apt-get install -y \
  "$($PYBIN -c 'import sys;print(f"python{sys.version_info.major}.{sys.version_info.minor}-venv")')" \
  pipewire-bin socat ffmpeg ydotool wl-clipboard libnotify-bin

echo "== [2/6] Service ydotool (injection clavier Wayland) =="
systemctl --user enable --now ydotool.service || true
if ! test -w /dev/uinput; then
  echo "  /dev/uinput non accessible -> règle udev + groupe input"
  echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' \
    | sudo tee /etc/udev/rules.d/80-uinput.rules >/dev/null
  sudo udevadm control --reload-rules && sudo udevadm trigger /dev/uinput || true
  sudo usermod -aG input "$USER"
  echo "  ⚠️  déconnecte/reconnecte ta session pour que le groupe 'input' prenne effet"
fi

echo "== [3/6] Environnement Python ($($PYBIN --version)) =="
[ -d "$VENV" ] || "$PYBIN" -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip wheel
"$VENV/bin/pip" install -r "$REPO_PATH/requirements.txt"

echo "== [4/6] Fichiers =="
install -m 644 "$REPO_PATH/whisper-server.py"  "$HOME/whisper-server.py"
install -m 755 "$REPO_PATH/whisper-dictee.sh" "$HOME/whisper-dictee.sh"
if [ ! -f "$HOME/.config/whisper-dictee.conf" ]; then
  mkdir -p "$HOME/.config"
  cat > "$HOME/.config/whisper-dictee.conf" <<'EOF'
# Config dictée vocale — lignes VAR=valeur (lues par le service ET le script).
WHISPER_MODEL=small
WHISPER_DEVICE=cuda
WHISPER_COMPUTE_TYPE=int8
WHISPER_LANGUAGE=fr
# DICTEE_INJECT=type        # type | clipboard | both
# DICTEE_SOURCE=            # nom d'une source PipeWire précise (pw-record --list-targets)
# DICTEE_NOTIFY=1
EOF
fi

echo "== [5/6] Service systemd utilisateur =="
mkdir -p "$HOME/.config/systemd/user"
install -m 644 "$REPO_PATH/whisper-server.service" \
  "$HOME/.config/systemd/user/whisper-server.service"
systemctl --user daemon-reload
systemctl --user enable --now whisper-server.service

echo "== [6/6] Vérification =="
sleep 2
systemctl --user --no-pager --lines=15 status whisper-server.service || true

cat <<EOF

────────────────────────────────────────────────────────────
Installation terminée.

Raccourci clavier KDE :
  Configuration du système → Raccourcis → Raccourcis personnalisés
  → Modifier → Nouveau → Commande/URL
  Action :  $HOME/whisper-dictee.sh
  Déclencheur : la touche de ton choix (ex. Méta+D)

Utilisation : raccourci pour parler, raccourci à nouveau pour
transcrire et injecter le texte dans le champ actif.

Changer de modèle (medium/large-v3) : éditer
  ~/.config/whisper-dictee.conf   puis
  systemctl --user restart whisper-server.service

Logs : journalctl --user -u whisper-server.service -f
────────────────────────────────────────────────────────────
EOF
