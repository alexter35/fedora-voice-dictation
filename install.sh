#!/bin/bash

# ============================================================
# fedora-voice-dictation - Script d'installation automatique
# Testé sur Fedora 43 KDE Plasma avec GTX 1070 Ti
#
# ⚠️ RÉFÉRENCE FEDORA UNIQUEMENT — ne pas lancer tel quel sur
# Kubuntu (dnf/rpm, akmods, driver 470xx légataire tous
# spécifiques Fedora). Voir README pour les points à refaire
# pour la reconstruction Kubuntu (driver, xdotool/Wayland,
# torch/faster-whisper).
# ============================================================

set -e

USER_HOME=$HOME
VENV_PATH="$USER_HOME/whisper-env"
REPO_PATH="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  Fedora Voice Dictation - Installation"
echo "============================================"
echo ""

# ------------------------------------------------------------
# Étape 1 — RPM Fusion
# ------------------------------------------------------------
echo "[1/8] Activation de RPM Fusion..."
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
  2>/dev/null || echo "RPM Fusion déjà activé, on continue."

# ------------------------------------------------------------
# Étape 2 — Drivers NVIDIA 470xx
# ------------------------------------------------------------
echo "[2/8] Installation des drivers NVIDIA 470xx..."
sudo bash -c 'echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf' 2>/dev/null || true
sudo bash -c 'echo "install nouveau /bin/false" >> /etc/modprobe.d/nouveau-blacklist.conf' 2>/dev/null || true
sudo dnf install -y akmod-nvidia-470xx xorg-x11-drv-nvidia-470xx \
  xorg-x11-drv-nvidia-470xx-cuda xorg-x11-drv-nvidia-470xx-cuda-libs

echo "  Compilation du module kernel (peut prendre 5 minutes)..."
sudo akmods --force
sudo dracut --force

# ------------------------------------------------------------
# Étape 3 — Règle udev nvidia-uvm
# ------------------------------------------------------------
echo "[3/8] Configuration udev nvidia-uvm..."
sudo bash -c 'echo "KERNEL==\"nvidia_uvm\", RUN+=\"/usr/bin/nvidia-modprobe -u\"" > /etc/udev/rules.d/70-nvidia.rules'
sudo udevadm control --reload-rules

# ------------------------------------------------------------
# Étape 4 — Dépendances système
# ------------------------------------------------------------
echo "[4/8] Installation des dépendances système..."
sudo dnf install -y python3.11 sox xdotool wl-clipboard socat ffmpeg --allowerasing

# ------------------------------------------------------------
# Étape 5 — Environnement Python
# ------------------------------------------------------------
echo "[5/8] Création de l'environnement Python 3.11..."
python3.11 -m venv "$VENV_PATH"
source "$VENV_PATH/bin/activate"

echo "  Installation de PyTorch CUDA 11.7..."
pip install torch==2.0.1+cu117 torchvision==0.15.2+cu117 torchaudio==2.0.2+cu117 \
  --extra-index-url https://download.pytorch.org/whl/cu117 --quiet

echo "  Installation de Whisper..."
pip install openai-whisper "numpy<2" --quiet

deactivate

# ------------------------------------------------------------
# Étape 6 — Copie des fichiers
# ------------------------------------------------------------
echo "[6/8] Copie des fichiers..."
cp "$REPO_PATH/whisper-server.py" "$USER_HOME/"
cp "$REPO_PATH/whisper-dictee.sh" "$USER_HOME/"
chmod +x "$USER_HOME/whisper-dictee.sh"

# Adapter le chemin utilisateur dans les fichiers
sed -i "s|/home/alexter33|$USER_HOME|g" "$USER_HOME/whisper-server.py"
sed -i "s|/home/alexter33|$USER_HOME|g" "$USER_HOME/whisper-dictee.sh"

# ------------------------------------------------------------
# Étape 7 — Service systemd
# ------------------------------------------------------------
echo "[7/8] Configuration du service systemd..."
mkdir -p "$USER_HOME/.config/systemd/user"
cp "$REPO_PATH/whisper-server.service" "$USER_HOME/.config/systemd/user/"
sed -i "s|/home/alexter33|$USER_HOME|g" "$USER_HOME/.config/systemd/user/whisper-server.service"

systemctl --user daemon-reload
systemctl --user enable whisper-server.service

# ------------------------------------------------------------
# Étape 8 — Résumé
# ------------------------------------------------------------
echo ""
echo "[8/8] Installation terminée !"
echo ""
echo "============================================"
echo "  IMPORTANT — Actions manuelles requises"
echo "============================================"
echo ""
echo "1. Dans le BIOS MSI B550-A PRO :"
echo "   Advanced → AMD CBS → NBIO → IOMMU → Disabled"
echo ""
echo "2. Raccourci clavier KDE :"
echo "   Paramètres → Raccourcis → Ajouter un nouveau → Commande :"
echo "   /bin/bash -c '$USER_HOME/whisper-dictee.sh'"
echo ""
echo "3. Redémarrer la machine :"
echo "   sudo reboot"
echo ""
echo "Après le redémarrage, le service Whisper démarrera automatiquement."
echo "Vérifie avec : systemctl --user status whisper-server.service"
echo ""
