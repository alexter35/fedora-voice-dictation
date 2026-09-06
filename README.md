# voice-dictation 🎙️ (portage Kubuntu)

Dictée vocale locale en français, avec Whisper accéléré CUDA. 100 % hors-ligne :
aucun son ni texte n'est envoyé sur internet.

> **Historique :** repo écrit à l'origine pour Fedora 43 (openai-whisper + PyTorch
> cu117 + driver NVIDIA 470xx + `xdotool`). Cassé après des mises à jour Fedora.
> **Réécrit pour Kubuntu (Ubuntu 26.04 LTS, KDE Plasma / Wayland)** en 2026-09 :
> backend `faster-whisper` (CTranslate2, sans PyTorch), capture PipeWire,
> injection presse-papier + Ctrl+V simulé (Wayland). L'ancienne procédure Fedora
> est en fin de fichier.

## Fonctionnement

```
whisper-server.py       serveur ; garde le modèle Whisper en VRAM (réponse quasi immédiate)
whisper-dictee.sh       script "toggle" : 1er appel = enregistre, 2e = transcrit + injecte
whisper-server.service  service systemd utilisateur (démarre au login)
```

Le serveur écoute sur un socket UNIX (`$XDG_RUNTIME_DIR/whisper.sock`). Le script
enregistre le micro avec `pw-record`, envoie le `.wav` au serveur, récupère le
texte, le met dans le presse-papier (`wl-copy`) et simule **Ctrl+V** dans la
fenêtre active (`ydotool key`, codes de touches evdev → indépendant de la
disposition clavier). `ydotool type` a été écarté : il frappe des positions
US-QWERTY, ce qui mélange le texte sur un clavier AZERTY. `wtype` ne marche pas
sous KWin (protocole *virtual-keyboard* non exposé).

## Prérequis

- GPU NVIDIA (testé : GTX 1070 Ti / Pascal, driver 580, sans runtime CUDA système —
  les libs CUDA 12 sont tirées en paquets pip dans le venv).
- Kubuntu / KDE Plasma, session **Wayland** (testé) ou X11. L'injection utilise
  `wl-clipboard` + `ydotool` (via `/dev/uinput`, indépendant du serveur d'affichage).
- `/dev/nvidia-uvm` présent (`nvidia-smi` OK). Reboot si absent après install du driver.

## Installation

```bash
./install.sh
```

Le script : installe les paquets apt (`pipewire-bin socat ffmpeg ydotool
wl-clipboard libnotify-bin` + `python3.x-venv`), active `ydotool.service`, crée
`~/whisper-env`, installe `faster-whisper` + libs CUDA (`requirements.txt`), copie
les fichiers dans `$HOME`, active le service utilisateur.

Puis, **manuellement**, le raccourci clavier KDE :
Configuration du système → Raccourcis → *Raccourcis personnalisés* → Modifier →
Nouveau → Commande/URL. Action : `~/whisper-dictee.sh`. Déclencheur : au choix
(ex. `Méta+D`).

## Utilisation

1. Clic dans un champ de texte.
2. Raccourci → l'enregistrement démarre (notification 🎙️).
3. Parle.
4. Raccourci à nouveau → transcription puis collage automatique du texte
   (Ctrl+V ; dans un terminal, mets `DICTEE_INJECT=clipboard` et colle à la main).

## Configuration — `~/.config/whisper-dictee.conf`

Lu à la fois par le service et par le script. Lignes `VAR=valeur` :

| Variable | Défaut | Rôle |
|---|---|---|
| `WHISPER_MODEL` | `small` | `tiny` / `base` / `small` / `medium` / `large-v3` |
| `WHISPER_DEVICE` | `cuda` | `cuda` ou `cpu` |
| `WHISPER_COMPUTE_TYPE` | `int8` | Pascal : garder `int8` (pas de float16 utile) |
| `WHISPER_LANGUAGE` | `fr` | vide = détection auto |
| `DICTEE_INJECT` | `type` | `type` = presse-papier + Ctrl+V · `clipboard` = copie seule · `keys` = frappe `ydotool type` brute (positions US-QWERTY) |
| `DICTEE_SOURCE` | auto | source PipeWire précise (`pw-record --list-targets`) |
| `DICTEE_NOTIFY` | `1` | notifications KDE |

Après modification : `systemctl --user restart whisper-server.service`.

### VRAM par modèle (int8, GTX 1070 Ti 8 Go)

| Modèle | Qualité | VRAM approx. |
|---|---|---|
| `small` | bon | ~0,5 Go |
| `medium` | très bon | ~1,5 Go |
| `large-v3` | excellent | ~3 Go |

`large-v3` en int8 tient largement dans les 8 Go et reste rapide en dictée courte.

## Dépannage

```bash
systemctl --user status whisper-server.service
journalctl --user -u whisper-server.service -f
```

- **`libcublas.so.12 is not found`** : `~/whisper-env/bin/pip install -r requirements.txt`
  n'a pas installé `nvidia-cublas-cu12` / `nvidia-cudnn-cu12`. Le serveur ajoute
  seul leur dossier à `LD_LIBRARY_PATH` (re-exec au démarrage).
- **Rien ne se tape** : `systemctl --user status ydotool.service` ; vérifier l'accès
  à `/dev/uinput` (`getfacl /dev/uinput` doit lister l'utilisateur, ou être dans le
  groupe `input` — relogin après `install.sh` si le groupe vient d'être ajouté).
- **Texte mélangé / mauvaises lettres** (« comment » → « co,,ent ») : `DICTEE_INJECT`
  est sur `keys`, qui frappe des positions US-QWERTY. Repasser sur `type` (défaut,
  presse-papier + Ctrl+V, insensible à la disposition clavier).
- **Rien ne se colle dans un terminal** : le terminal utilise Ctrl+Maj+V, pas Ctrl+V.
  Mettre `DICTEE_INJECT=clipboard` et coller à la main.
- **`Serveur Whisper injoignable`** : le service n'est pas lancé, ou `XDG_RUNTIME_DIR`
  diffère entre le service et la session (normalement `/run/user/$UID`).
- **CUDA non détecté** : `ls /dev/nvidia-uvm` ; `nvidia-smi`. Reboot si `nvidia-uvm`
  absent.
- **Transcription vide** : le filtre VAD a tout coupé (bruit/silence) — parler plus
  près du micro, ou régler `DICTEE_SOURCE`.

## Désinstallation

```bash
systemctl --user disable --now whisper-server.service
rm -f ~/whisper-server.py ~/whisper-dictee.sh \
      ~/.config/systemd/user/whisper-server.service \
      ~/.config/whisper-dictee.conf
rm -rf ~/whisper-env
```

---

## Annexe — procédure Fedora d'origine (obsolète, pour mémoire)

<details>
<summary>Fedora 43, openai-whisper + PyTorch cu117 + NVIDIA 470xx</summary>

- RPM Fusion + `akmod-nvidia-470xx` — le **470xx était une erreur** (reliquat legacy) :
  le driver mainline (580) marche sur Pascal. Sous Kubuntu : `ubuntu-drivers autoinstall`
  ou le PPA `graphics-drivers`.
- `sudo dnf install python3.11 sox xdotool wl-clipboard socat ffmpeg`
- venv + `pip install torch==2.0.1+cu117 … openai-whisper "numpy<2"` — **pins 2023**,
  ne pas réutiliser.
- `xdotool type` pour l'injection — **KO en Wayland**, remplacé par `ydotool`.
- Réglage BIOS de l'époque : *AMD CBS → NBIO → IOMMU → Disabled*. Non requis pour ce
  portage (et hors périmètre : on ne touche pas au BIOS de ce poste).

</details>
