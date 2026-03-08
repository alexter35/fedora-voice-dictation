# fedora-voice-dictation 🎙️

Dictée vocale locale en français sur Fedora avec Whisper (OpenAI) et CUDA.

## Fonctionnalités

- Transcription vocale 100% locale (aucune donnée envoyée sur internet)
- Accélération GPU via CUDA (testé sur GTX 1070 Ti)
- Modèle Whisper chargé en permanence en VRAM (réponse quasi instantanée)
- Mode toggle : un raccourci pour démarrer, un autre pour arrêter et transcrire
- Injection automatique du texte dans le champ actif
- Démarrage automatique au login via systemd

## Prérequis matériel

- GPU NVIDIA (testé sur GTX 1070 Ti)
- Fedora 43 avec KDE Plasma

## Installation

### 1. Drivers NVIDIA

Activer RPM Fusion :
```bash
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

Blacklister nouveau et installer les drivers :
```bash
sudo bash -c 'echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf'
sudo dnf install akmod-nvidia-470xx xorg-x11-drv-nvidia-470xx xorg-x11-drv-nvidia-470xx-cuda
sudo akmods --force
sudo dracut --force
sudo reboot
```

> ⚠️ La GTX 1070 Ti nécessite le driver **470xx** et non le 580 (open source) qui ne supporte pas cette carte.

### 2. Désactiver l'IOMMU

Dans le BIOS : **Advanced → AMD CBS → NBIO → IOMMU → Disabled**

Créer la règle udev pour nvidia-uvm :
```bash
sudo bash -c 'echo "KERNEL==nvidia_uvm, RUN+=/usr/bin/nvidia-modprobe -u" > /etc/udev/rules.d/70-nvidia.rules'
sudo udevadm control --reload-rules
```

### 3. Dépendances système

```bash
sudo dnf install python3.11 sox xdotool wl-clipboard socat ffmpeg --allowerasing
```

### 4. Environnement Python et Whisper

```bash
python3.11 -m venv ~/whisper-env
source ~/whisper-env/bin/activate
pip install torch==2.0.1+cu117 torchvision==0.15.2+cu117 torchaudio==2.0.2+cu117 \
  --extra-index-url https://download.pytorch.org/whl/cu117
pip install openai-whisper "numpy<2"
```

### 5. Installer les fichiers

```bash
cp whisper-server.py ~/
cp whisper-dictee.sh ~/
chmod +x ~/whisper-dictee.sh
mkdir -p ~/.config/systemd/user
cp whisper-server.service ~/.config/systemd/user/
```

### 6. Activer les services

```bash
systemctl --user daemon-reload
systemctl --user enable --now whisper-server.service
```

### 7. Raccourci clavier KDE

Paramètres → Raccourcis → Ajouter un nouveau → Commande :
```
/bin/bash -c '/home/TON_USER/whisper-dictee.sh'
```
Assigner à la touche de ton choix (ex: Ctrl+Alt+S).

> ⚠️ Remplace `TON_USER` par ton nom d'utilisateur.

## Utilisation

1. Clique dans n'importe quel champ de texte
2. Appuie sur le raccourci → l'enregistrement démarre
3. Parle
4. Appuie à nouveau sur le raccourci → transcription et injection automatique

## Architecture

```
whisper-server.py     - Serveur socket qui garde le modèle en VRAM
whisper-dictee.sh     - Script toggle enregistrement/transcription
whisper-server.service - Service systemd utilisateur
```

## Modèles disponibles

| Modèle | Qualité | VRAM |
|--------|---------|------|
| tiny   | Correct | ~1Go |
| small  | Bon     | ~2Go |
| medium | Très bon| ~5Go |
| large  | Excellent| ~10Go|

Modifier `whisper-server.py` ligne `load_model("small", ...)` pour changer de modèle.

## Dépannage

**Le service ne démarre pas :**
```bash
systemctl --user status whisper-server.service
journalctl --user -u whisper-server.service
```

**CUDA non détecté :**
```bash
ls /dev/nvidia-uvm  # doit exister
nvidia-smi          # doit afficher la carte
```

**Reboot nécessaire** si `/dev/nvidia-uvm` est absent.
