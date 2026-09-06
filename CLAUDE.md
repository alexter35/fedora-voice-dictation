# CLAUDE.md — Portage dictée vocale Fedora → Kubuntu (suivi)

## État (2026-09-06) — ✅ OPÉRATIONNEL. Raccourci Meta+D actif, injection presse-papier+Ctrl+V, testé à la voix réelle.

Repo `alexter35/fedora-voice-dictation` (clone : `~/kubuntu-reinstall/fedora-voice-dictation/`) :
dictée vocale locale FR, Whisper accéléré CUDA, 100 % hors-ligne. Écrit à l'origine pour
Fedora 43, **cassé** après MàJ Fedora. Réécrit pour **Kubuntu 26.04 (Plasma 6.6 / Wayland)** ;
`main` = portage Kubuntu depuis 2026-09-06, tag `v1-fedora` = dernier état Fedora.

Sous-projet de `../CLAUDE.md` (bug reboot, CLOS) et `../kubuntu-reinstall.md` (réinstall).

### Ce qui tourne maintenant

- **`whisper-server.service`** (user, `systemctl --user`) : actif, modèle `small` sur
  **CUDA / int8**, **~434 Mio VRAM**, socket `$XDG_RUNTIME_DIR/whisper.sock`.
- Latence à chaud : **~0,2 s** pour un clip de ~2,5 s (modèle résident en VRAM).
- venv `~/whisper-env` (Python 3.14) : `faster-whisper==1.2.1` + `ctranslate2 4.8.2`
  + `nvidia-cublas-cu12` / `nvidia-cudnn-cu12` (libs CUDA 12 en pip, ~1,3 Go, isolées).
- Capture : `pw-record` (PipeWire). Injection : **presse-papier (`wl-copy`) + Ctrl+V
  simulé** via `ydotool key 29:1 47:1 47:0 29:0` (service user `ydotool.service` actif,
  ACL sur `/dev/uinput`). Micro : webcam Logitech C920.
  → `ydotool type` **abandonné** : frappe en positions US-QWERTY → texte mélangé quand le
  clavier est en AZERTY (layout du poste = `fr azerty`). `wtype` **inutilisable** : KWin
  n'expose pas `zwp_virtual_keyboard_manager_v1` (`wayland-info` : seuls `text_input_*`).
  Ctrl+V par keycodes evdev est indépendant du layout. `DICTEE_INJECT` : `type` (défaut,
  presse-papier+Ctrl+V) · `clipboard` (copie seule) · `keys` (ancienne frappe ydotool brute).

### Corrections apportées (vs repo Fedora d'origine)

| Origine (Fedora) | Remplacé par (Kubuntu) |
|---|---|
| `install.sh` : dnf, RPM Fusion, `akmod-nvidia-470xx`, dracut | `install.sh` apt, service user, config auto |
| `openai-whisper` + PyTorch `2.0.1+cu117` (pins 2023) | `faster-whisper` (CTranslate2, **sans torch**) |
| pas de runtime CUDA → `libcublas.so.12 not found` | libs CUDA 12 en paquets pip dans le venv ; le serveur ajoute leur dir à `LD_LIBRARY_PATH` (re-exec au démarrage) |
| `xdotool type` (X11) — **KO en Wayland** | presse-papier + Ctrl+V simulé `ydotool key` (voir ci-dessus ; `ydotool type` mélange en AZERTY, `wtype` KO sur KWin) |
| `rec` / sox (absent sur le poste) | `pw-record --rate=16000 --channels=1 --format=s16` |
| chemins `/home/alexter33` en dur, modèle `small` en dur | tout via `~/.config/whisper-dictee.conf` ; service en `%h` |
| socket `/tmp/whisper.sock` | `$XDG_RUNTIME_DIR/whisper.sock` (0600, privé, auto-nettoyé) |
| `whisper-server.service` chemins en dur, `After=default.target` | `%h`, `After=graphical-session.target`, `Wants=ydotool.service`, `EnvironmentFile=-%h/.config/whisper-dictee.conf` |

Choix techniques : **int8** (Pascal/GP104 n'a pas de float16 utile — `ctranslate2` ne
propose que `float32`/`int8_float32`/`int8` sur ce GPU). VAD activé,
`condition_on_previous_text=False` (moins d'hallucination / de boucles en dictée courte).

### Fichiers

| Fichier repo | Copié vers | Rôle |
|---|---|---|
| `whisper-server.py` | `~/whisper-server.py` | serveur socket, modèle en VRAM (faster-whisper) |
| `whisper-dictee.sh` | `~/whisper-dictee.sh` | script toggle : 1er appel = enregistre, 2e = transcrit + injecte |
| `whisper-server.service` | `~/.config/systemd/user/` | service user |
| `requirements.txt` | — | `faster-whisper` + libs CUDA pip |
| `install.sh` | — | installe tout (apt + venv + service) |
| — | `~/.config/whisper-dictee.conf` | config (créée par install.sh) |
| — | `~/.local/share/applications/whisper-dictee.desktop` | lanceur pour raccourci KDE |

### Config — `~/.config/whisper-dictee.conf` (lue par le service ET le script)

```
WHISPER_MODEL=small          # tiny/base/small/medium/large-v3
WHISPER_DEVICE=cuda          # cuda | cpu
WHISPER_COMPUTE_TYPE=int8    # garder int8 sur Pascal
WHISPER_LANGUAGE=fr          # vide = auto
# DICTEE_INJECT=type         # type (presse-papier+Ctrl+V) | clipboard (copie seule) | keys (ydotool brut)
# DICTEE_SOURCE=             # source PipeWire précise (pw-record --list-targets)
# DICTEE_NOTIFY=1
```

VRAM int8 (carte 8 Go) : `small` ~0,5 Go · `medium` ~1,5 Go · `large-v3` ~3 Go.
`large-v3` tient large et reste rapide en dictée courte → envisageable pour la qualité.

### RESTE À FAIRE

1. **Raccourci clavier Meta+D — ACTIF (2026-09-06).** `_launch` était dans
   `kglobalshortcutsrc` mais sans grab clavier vivant (`getGlobalShortcutsByKey` vide) ;
   ni reboot ni `kbuildsycoca6` ne l'ont réparé. Forcé via D-Bus
   (`org.kde.KGlobalAccel.setShortcut`, flag 6) → Meta+D → Whisper, Meta+Shift+D → Coup
   d'œil sur le bureau. Détail : mémoire `kde-plasma-6-shortcuts`.
2. **Test bout-en-bout voix réelle — OK (2026-09-06).** Rapport utilisateur : « il marche
   nickel », dictée réelle collée correctement (accents compris), GPU ne s'emballe pas
   (modèle résident, ~0,2 s/requête). Si un jour la qualité déçoit sur dictée longue :
   passer `WHISPER_MODEL=medium` (ou `large-v3`) dans `~/.config/whisper-dictee.conf` +
   `systemctl --user restart whisper-server.service`.

### Commandes utiles

```bash
systemctl --user status whisper-server.service
journalctl --user -u whisper-server.service -f
systemctl --user restart whisper-server.service      # après édition de la conf
nvidia-smi --query-compute-apps=pid,used_memory --format=csv   # VRAM du serveur
~/whisper-dictee.sh                                  # toggle manuel (test)
```

Désinstallation : `systemctl --user disable --now whisper-server.service` ;
`rm -f ~/whisper-server.py ~/whisper-dictee.sh ~/.config/systemd/user/whisper-server.service ~/.config/whisper-dictee.conf` ;
`rm -rf ~/whisper-env`.

---

## Journal

- **2026-09-06** — Analyse du repo Fedora + portage complet Kubuntu.
  - Vérifs poste : session Wayland, NVIDIA 580 + CUDA + `/dev/nvidia-uvm`, `ydotool` +
    service actif + ACL uinput, `pw-record`/`socat`/`ffmpeg` présents, Python 3.14 seul.
  - `faster-whisper` + `ctranslate2 4.8.2` : cp314 OK ; **`libcublas.so.12` manquant**
    (pas de runtime CUDA système) → résolu par `nvidia-cublas-cu12` + `nvidia-cudnn-cu12`
    dans le venv + `LD_LIBRARY_PATH` (re-exec géré par `whisper-server.py`).
  - `ctranslate2.get_supported_compute_types('cuda')` = `{float32, int8_float32, int8}`
    (pas de float16 → Pascal) → on tourne en **int8**.
  - Réécriture des 6 fichiers (cf. tableau ci-dessus). `install.sh` exécuté :
    service actif, modèle `small`/cuda/int8 chargé, socket en écoute.
  - Tests OK : socket serveur, `pw-record` (wav valide, SIGINT propre), chaîne complète
    `whisper-dictee.sh` (presse-papier), latence chaud ~0,2 s, VRAM 434 Mio.
    Transcription correcte sur entrée propre (« je teste la latence… » → exact).
  - Raccourci KDE : fichiers en place (`.desktop` + `kglobalshortcutsrc`,
    Show Desktop déplacé sur Meta+Shift+D). **Bloqué sur relogin** (kglobalaccel intégré
    à kwin_wayland en Plasma 6.6, pas de reload à chaud).
