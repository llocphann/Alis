#!/usr/bin/env python3
"""Private real MPD codec/queue/resume qualification with a null audio output."""
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import wave
from local_music_mpd import MpdClient

ROOT = Path(__file__).resolve().parents[1]
if not shutil.which("mpd") or not shutil.which("ffmpeg"):
    raise SystemExit("SKIP: real MPD/FFmpeg executables unavailable")

with tempfile.TemporaryDirectory(prefix="alis-private-mpd-") as name:
    folder = Path(name)
    music = folder / "music"
    music.mkdir()
    (folder / "playlists").mkdir()
    audio = music / "valid.wav"
    with wave.open(str(audio), "wb") as stream:
        stream.setnchannels(1);stream.setsampwidth(2);stream.setframerate(8000)
        stream.writeframes(struct.pack("<h",32)*8000*20)
    subprocess.run(["ffmpeg","-v","error","-i",str(audio),str(music/"valid.flac")],check=True,timeout=10)
    valid_uri = "valid.flac"
    # Index a valid track first, then break its header after the scan completes.
    # Invalid frames after valid metadata can look like ordinary EOF to MPD;
    # this fixture needs a genuine decoder-open failure on a known queue URI.
    encoded = (music / valid_uri).read_bytes()
    broken = music / "broken.flac"
    broken.write_bytes(encoded)
    sock = folder / "mpd.sock"
    conf = folder / "mpd.conf"
    conf.write_text('music_directory "'+str(music)+'"\nplaylist_directory "'+str(folder/"playlists")+'"\n'
                    'db_file "'+str(folder/"db")+'"\nstate_file "'+str(folder/"state")+'"\n'
                    'bind_to_address "'+str(sock)+'"\nzeroconf_enabled "no"\nauto_update "no"\n'
                    'audio_output {\n type "null"\n name "Private null fixture"\n mixer_type "software"\n}\n')
    env = dict(os.environ,XDG_CONFIG_HOME=str(folder/"config"),XDG_CACHE_HOME=str(folder/"cache"),
               XDG_STATE_HOME=str(folder/"state-home"),XDG_DATA_HOME=str(folder/"data"))
    log = folder / "mpd.log"
    with log.open("wb") as stream:
        process = subprocess.Popen(["mpd","--no-daemon",str(conf)],env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
    def helper(mode,*args):
        result = subprocess.run([sys.executable,str(ROOT/"scripts/local_music_mpd.py"),mode,str(sock),"0",*args],
                                env=env,text=True,capture_output=True,timeout=10)
        payload = json.loads(result.stdout)
        if result.returncode: raise AssertionError(payload)
        return payload
    def status(): return helper("status",str(music))["status"]
    def eventually(predicate, message):
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            if predicate(): return
            if process.poll() is not None: raise AssertionError(log.read_text())
            time.sleep(.05)
        raise AssertionError(message+": "+str(status()))
    try:
        eventually(lambda:sock.exists(),"private MPD socket missing")
        with MpdClient(str(sock),0) as client: client.command("update")
        eventually(lambda:len(helper("snapshot",str(music))["tracks"])==3,"synthetic library scan incomplete")
        broken.write_bytes(b"invalid synthetic FLAC header")
        helper("queue","0",json.dumps([valid_uri,"valid.wav"]))
        eventually(lambda:status().get("state")=="play","valid synthetic codec did not play")
        check=status()
        assert not check.get("error") and float(check.get("duration","0"))>=19,check
        helper("command","stop","[]")
        time.sleep(.5)
        helper("command","play","[0]")
        eventually(lambda:status().get("state")=="play","Stop/idle/Play failed")
        helper("command","pause","[1]")
        assert status()["state"]=="pause"
        helper("command","pause","[0]")
        helper("command","random","[1]")
        helper("command","repeat","[1]")
        check=status()
        assert check.get("random")=="1" and check.get("repeat")=="1" and check.get("state")=="play",check
        helper("command","random","[0]")
        helper("command","repeat","[0]")
        helper("command","clear","[]")
        helper("queue","0",json.dumps(["broken.flac"]))
        eventually(lambda:bool(status().get("error")),"corrupt codec failed without a status error")
        helper("queue","0",json.dumps([valid_uri]))
        eventually(lambda:status().get("state")=="play" and not status().get("error"),"valid-track recovery retained corrupt-codec error")
        print("PASS: real private MPD decoded "+valid_uri+", queue/Stop/idle/Play/Pause/Shuffle/Repeat and corrupt-codec recovery; null output only")
    finally:
        if process.poll() is None:
            os.killpg(process.pid,signal.SIGTERM)
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired: os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=3)
