"""ota-daemon 로직 점검 (apt 없이): python3 tests/test_ota.py"""
import importlib.machinery, importlib.util, time
l = importlib.machinery.SourceFileLoader("ota", "userpatches/overlay/tf-os-app/usr/lib/tf-os/ota-daemon.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("ota", l)); l.exec_module(m)

calls = []
def fake(rc):
    def run(cmd):
        calls.append(cmd[0:2]); return rc, "out\n"
    return run

def wait():
    while m.lock.locked(): time.sleep(0.01)

m.run = fake(0)
assert m.job("upgrading", m.UPDATE, m.UPGRADE); wait()
assert m.st["state"] == "done" and len(calls) == 2, m.st
assert "Dir::Etc::sourcelist=/etc/tf-os/tfos.list" in m.UPDATE and "APT::Get::List-Cleanup=0" in m.UPDATE

m.run = fake(1); calls.clear()
assert m.job("upgrading", m.UPDATE, m.UPGRADE); wait()
assert m.st["state"] == "error" and len(calls) == 1, "update 실패 시 upgrade 중단"

m.lock.acquire()
assert not m.job("checking", m.UPDATE), "동시 작업 거부"
print("ok")

# --- 최초 설정 검증 ---
import glob, os, tempfile
m.DONE = os.path.join(tempfile.mkdtemp(), "done")
cmds = []
m.run = lambda c, input=None: (cmds.append((c, input)) or (0, ""))
for bad in [("root", "password1"), ("Bad", "password1"), ("a;b", "password1"), ("bob", "short"), ("bob", "pass:word1"), (None, "password1")]:
    assert m.setup(*bad, True), bad
assert not cmds, "검증 실패 시 시스템 변경 없음"
assert m.setup("bob", "password1", True) is None
assert cmds[0][0][0] == "useradd" and cmds[1] == (["chpasswd"], "bob:password1\n") and cmds[2][0][:3] == ["systemctl", "enable", "--now"]
assert m.setup("bob2", "password1", False), "두 번째 설정 거부"
cmds.clear(); os.remove(m.DONE)
assert m.setup("amy", "password1", False) is None and all(c[0][0] != "systemctl" for c in cmds), "ssh 미선택 시 활성화 안 함"
print("ok setup")

# --- Wi-Fi ---
out = "*:My\\:Home:80:WPA2\n :My\\:Home:40:WPA2\n :Cafe:55:--\n ::70:WPA2\n :Bad:x:WPA2\nwarning line\n"
cur, nets = m.parse_wifi(out)
assert cur == "My:Home" and [n["ssid"] for n in nets] == ["My:Home", "Cafe"], (cur, nets)
assert nets[0]["signal"] == 80 and nets[0]["secure"] and not nets[1]["secure"]
cmds.clear()
A = lambda **k: m.wifi_action(k)
for bad in [dict(ssid=""), dict(ssid="-x"), dict(ssid="a" * 33), dict(ssid=None), dict(ssid="ok", password="short"), dict(ssid="ok", action="zzz")]:
    assert A(**bad), bad
assert not cmds
m.run = lambda c, input=None: (cmds.append((c, input)) or (0, ""))
assert A(ssid="Cafe") is None and "--ask" not in cmds[-1][0]
assert A(ssid="Home", password="password1") is None and cmds[-1][1] == "password1\n" and "password1" not in cmds[-1][0]
cmds.clear(); assert A(ssid="Home", action="disconnect") is None and cmds[0][0][6:] == ["Home", "connection.autoconnect", "no"] and cmds[1][0][3:6] == ["connection", "down", "id"]
cmds.clear(); assert A(ssid="Home", action="forget") is None and cmds[0][0][3:6] == ["connection", "delete", "id"]
m.run = lambda c, input=None: (cmds.append((c, input)) or (1, "bad"))
cmds.clear(); assert A(ssid="Home", password="password1") == "bad" and cmds[-1][0][3:6] == ["connection", "delete", "id"]

# 키파일: 숨김 PSK / Enterprise, 0600, 실패 시 파일 제거
import stat
m.NM_DIR = tempfile.mkdtemp()
m.run = lambda c, input=None: (cmds.append((c, input)) or (0, ""))
assert A(ssid="Corp", eap="peap", identity="me", password="pw", phase2="mschapv2") is None
f = glob.glob(m.NM_DIR + "/*")[0]
t = open(f).read()
assert "key-mgmt=wpa-eap" in t and "eap=peap;" in t and "identity=me" in t and stat.S_IMODE(os.stat(f).st_mode) == 0o600
assert not any("pw" in x for c, _ in cmds for x in c), "비밀번호 argv 노출 금지"
os.remove(f)
assert A(ssid="Hid", hidden=True, password="password1") is None
t = open(glob.glob(m.NM_DIR + "/*")[0]).read(); assert "hidden=true" in t and "psk=password1" in t
for bad in [dict(ssid="a;b", hidden=True), dict(ssid="x", eap="tls", identity="i", password="p"), dict(ssid="x", eap="peap", identity="i\nx", password="p")]:
    assert A(**bad), bad
m.run = lambda c, input=None: (cmds.append((c, input)) or (1 if c[4] == "load" else 0, "boom"))
for f in glob.glob(m.NM_DIR + "/*"): os.remove(f)
assert A(ssid="Hid2", hidden=True, password="password1") == "boom" and not glob.glob(m.NM_DIR + "/*"), "실패 시 키파일 정리"
print("ok wifi")

# --- 스피커 ---
def alsa(c, input=None, timeout=None):
    cmds.append(c)
    if c[:2] == ["amixer", "scontrols"]:
        return 0, "Simple mixer control 'Mic',0\nSimple mixer control 'Master',0\nSimple mixer control 'Speaker',0\n"
    if c[:2] == ["amixer", "sget"]:  # Mic 은 capture 전용
        return 0, "Capabilities: cvolume\n" if c[2] == "Mic" else "Capabilities: pvolume\n Front Left: Playback 40 [63%] [on]\n"
    return 0, ""
m.run = alsa
assert m.mixer_ctl()[0] == "Speaker", "Speaker 우선"
assert m.audio_get()["volume"] == 63 and m.audio_get()["control"] == "Speaker"
cmds.clear(); assert m.audio_set(50) is None and cmds[-1] == ["amixer", "sset", "Speaker", "50%", "unmute"]
for bad in (-1, 101, "5", None, True, 5.0):
    assert m.audio_set(bad), bad
m.run = lambda c, input=None, timeout=None: (1, "no card")
assert m.audio_set(10) == "사운드 카드 없음" and m.audio_get()["volume"] == -1
print("ok audio")

# 실제 run(): 타임아웃은 정상 취급
l2 = importlib.machinery.SourceFileLoader("ota", l.path); m2 = importlib.util.module_from_spec(importlib.util.spec_from_loader("ota", l2)); l2.exec_module(m2)
assert m2.run(["sleep", "5"], timeout=0.1) == (0, "")
assert m2.run(["echo", "hi"])[1].strip() == "hi"
print("ok run")
