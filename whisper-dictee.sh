#!/bin/bash

if [ -f /tmp/dictee.pid ]; then
    kill $(cat /tmp/dictee.pid) 2>/dev/null
    rm /tmp/dictee.pid
    sleep 0.3
    TEXTE=$(echo "/tmp/dictee.wav" | socat -t 30 - UNIX-CONNECT:/tmp/whisper.sock)
    sleep 0.5
    DISPLAY=:0 xdotool type --clearmodifiers "$TEXTE"
    rm -f /tmp/dictee.wav
else
    rec /tmp/dictee.wav 2>/dev/null &
    echo $! > /tmp/dictee.pid
fi
