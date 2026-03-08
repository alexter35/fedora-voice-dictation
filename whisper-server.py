#!/usr/bin/env python3
import whisper
import sys
import os
import socket

print("Chargement du modèle Whisper...", flush=True)
model = whisper.load_model("small", device="cuda")
print("Modèle prêt !", flush=True)

# Écoute les requêtes de transcription
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock_path = "/tmp/whisper.sock"
if os.path.exists(sock_path):
    os.remove(sock_path)
sock.bind(sock_path)
sock.listen(1)
os.chmod(sock_path, 0o600)

while True:
    conn, _ = sock.accept()
    audio_file = conn.recv(1024).decode().strip()
    if os.path.exists(audio_file):
        result = model.transcribe(audio_file, language="fr")
        conn.sendall(result["text"].encode())
    conn.close()
