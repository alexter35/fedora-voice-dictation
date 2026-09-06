#!/usr/bin/env python3
"""Serveur de dictée Whisper — garde le modèle chargé en VRAM.

Backend : faster-whisper (CTranslate2), pas de PyTorch.
Protocole : socket UNIX, une requête = un chemin de fichier audio terminé par
"\n" ; la réponse est le texte transcrit (UTF-8), puis la connexion est fermée.

Configuration par variables d'environnement (toutes optionnelles) :
  WHISPER_MODEL          modèle faster-whisper           (défaut : small)
  WHISPER_DEVICE         cuda | cpu                      (défaut : cuda)
  WHISPER_COMPUTE_TYPE   int8 | int8_float32 | float32   (défaut : int8)
  WHISPER_LANGUAGE       code langue, vide = auto        (défaut : fr)
  WHISPER_BEAM_SIZE      taille du faisceau              (défaut : 5)
  WHISPER_SOCKET         chemin du socket UNIX
                         (défaut : $XDG_RUNTIME_DIR/whisper.sock)
"""
import glob
import os
import socket
import sys
import sysconfig
import traceback


def _ensure_cuda_libs():
    """CTranslate2 ne sait pas trouver les libs CUDA livrées en paquets pip
    (nvidia-cublas-cu12, nvidia-cudnn-cu12). On ajoute leurs dossiers à
    LD_LIBRARY_PATH puis on relance le process une seule fois."""
    if os.environ.get("_WHISPER_LDPATH_SET") == "1":
        return
    purelib = sysconfig.get_paths()["purelib"]
    libdirs = sorted(glob.glob(os.path.join(purelib, "nvidia", "*", "lib")))
    os.environ["_WHISPER_LDPATH_SET"] = "1"
    if not libdirs:
        return
    current = os.environ.get("LD_LIBRARY_PATH", "")
    parts = current.split(os.pathsep) if current else []
    if all(d in parts for d in libdirs):
        return
    os.environ["LD_LIBRARY_PATH"] = os.pathsep.join(libdirs + parts)
    os.execv(sys.executable, [sys.executable] + sys.argv)


_ensure_cuda_libs()

import numpy as np  # noqa: E402
from faster_whisper import WhisperModel  # noqa: E402

MODEL = os.environ.get("WHISPER_MODEL", "small")
DEVICE = os.environ.get("WHISPER_DEVICE", "cuda")
COMPUTE_TYPE = os.environ.get("WHISPER_COMPUTE_TYPE", "int8")
LANGUAGE = os.environ.get("WHISPER_LANGUAGE", "fr") or None
BEAM_SIZE = int(os.environ.get("WHISPER_BEAM_SIZE", "5"))

_runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
SOCK_PATH = os.environ.get("WHISPER_SOCKET", os.path.join(_runtime_dir, "whisper.sock"))


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def transcribe(model, path):
    segments, info = model.transcribe(
        path,
        language=LANGUAGE,
        beam_size=BEAM_SIZE,
        vad_filter=True,
        condition_on_previous_text=False,
    )
    text = "".join(seg.text for seg in segments).strip()
    log(f"  [{info.language} {info.duration:.1f}s] -> {text!r}")
    return text


def main():
    log(f"Chargement du modèle Whisper « {MODEL} » ({DEVICE}/{COMPUTE_TYPE})…")
    try:
        model = WhisperModel(MODEL, device=DEVICE, compute_type=COMPUTE_TYPE)
    except Exception:
        log("Échec du chargement sur le device demandé :")
        traceback.print_exc()
        if DEVICE != "cpu":
            log("Repli sur CPU (int8).")
            model = WhisperModel(MODEL, device="cpu", compute_type="int8")
        else:
            raise

    # Préchauffe : force le chargement des kernels CUDA sur du silence.
    try:
        model.transcribe(np.zeros(16000, dtype=np.float32), language=LANGUAGE)
    except Exception:
        pass
    log("Modèle prêt.")

    if os.path.exists(SOCK_PATH):
        os.remove(SOCK_PATH)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(SOCK_PATH)
    os.chmod(SOCK_PATH, 0o600)
    sock.listen(1)
    log(f"En écoute sur {SOCK_PATH}")

    while True:
        conn, _ = sock.accept()
        try:
            conn.settimeout(120)
            buf = b""
            while b"\n" not in buf and len(buf) < 4096:
                chunk = conn.recv(1024)
                if not chunk:
                    break
                buf += chunk
            audio_file = buf.split(b"\n", 1)[0].decode("utf-8", "replace").strip()
            if audio_file and os.path.exists(audio_file):
                text = transcribe(model, audio_file)
                conn.sendall(text.encode("utf-8"))
            else:
                log(f"Fichier introuvable : {audio_file!r}")
        except Exception:
            log("Erreur pendant la transcription :")
            traceback.print_exc()
        finally:
            conn.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
