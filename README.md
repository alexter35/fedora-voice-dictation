# fedora-voice-dictation 🎙️

Dictée vocale locale en français sur Fedora avec Whisper (OpenAI) et CUDA.

> ⚠️ **État actuel : cassé sur Fedora.** Le service tourne toujours (`systemctl --user status` le montre actif) mais la chaîne enregistrement → transcription → injection ne fonctionne plus en pratique, probablement lié aux changements de driver NVIDIA côté Fedora (voir section Drivers). Le repo est conservé comme base pour une reconstruction propre sur **Kubuntu**, pas pour un fix rapide sur Fedora.

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

## Installation (procédure Fedora d'origine — à revalider sous Kubuntu)

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

> ⚠️ **Correction a posteriori** : l'indication ci-dessus (driver 470xx obligatoire) était fausse — c'était en fait un reliquat legacy inutile pour du Pascal (GP104). Le driver **mainline standard** (580.173.02 côté RPM Fusion Fedora) fonctionne bien sur GTX 1070 Ti. Sur Kubuntu, partir du driver NVIDIA standard proposé par `ubuntu-drivers` / le PPA `graphics-drivers`, pas d'une branche legacy, sauf blocage constaté.

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

> Ces pins torch/cu117 datent de 2023 (mars) : à refaire avec des versions torch actuelles compatibles CUDA sur Kubuntu, ne pas copier-coller tel quel.

**Alternative à évaluer pour la reconstruction : [faster-whisper](https://github.com/SYSTRAN/faster-whisper)** (basé sur CTranslate2), déjà testé en parallèle sur cette machine — sensiblement plus rapide et moins gourmand en VRAM qu'`openai-whisper` pour un usage dictée en temps quasi réel. Change l'API de `whisper-server.py` (`WhisperModel(...).transcribe(...)` au lieu de `whisper.load_model(...)`) mais pas l'architecture (socket + modèle chargé en VRAM).

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

> ⚠️ **X11 requis pour `xdotool`.** Si la session Kubuntu (ou Fedora) tourne en Wayland, `xdotool type` ne fonctionne pas nativement. Solutions pour la reconstruction : `ydotool` (démon système + permissions uinput) ou `wtype`, à la place de `xdotool` dans `whisper-dictee.sh`. À trancher selon la session par défaut de Kubuntu (KDE Plasma sous Kubuntu peut tourner en X11 ou Wayland selon la version).

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
