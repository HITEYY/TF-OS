#!/usr/bin/python3
"""TF-OS 시스템 데몬(root): OTA + 최초 설정. UI(QML)가 localhost HTTP 로 호출.
GET /status  POST /check  POST /upgrade  POST /reboot
GET /setup   POST /setup {user,password,ssh}  (최초 1회만 허용)
GET /wifi    POST /wifi {action,ssid,password,hidden,eap,identity,phase2}  (NetworkManager/nmcli)
             action: connect(기본) | saved | disconnect | forget
GET /audio   POST /audio {volume:0-100}  POST /audio/test   스피커 (ALSA amixer/speaker-test)
GET /hw      카메라 목록 / IC 리더(PC/SC) / NFC 리더 상태 (진단용)
"""
import glob, json, os, re, subprocess, threading, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PKG, LIST, PORT = "tf-os-app", "/etc/tf-os/tfos.list", 8765
# update 는 tf-os 목록만 새로고침 (Armbian/Debian 목록은 건드리지 않음)
UPDATE = ["apt-get", "-o", f"Dir::Etc::sourcelist={LIST}", "-o", "Dir::Etc::sourceparts=-",
          "-o", "APT::Get::List-Cleanup=0", "update"]
UPGRADE = ["apt-get", "-y", "--only-upgrade", "install", PKG]

DONE = "/var/lib/tf-os/setup-done"
USER_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")

lock = threading.Lock()
setup_lock = threading.Lock()
st = {"state": "idle", "log": ""}  # idle | checking | upgrading | done | error


def run(cmd, input=None, timeout=None):
    try:
        return _run(cmd, input, timeout)
    except subprocess.TimeoutExpired:
        return 0, ""  # 테스트음처럼 일부러 자르는 용도


def _run(cmd, input, timeout):
    p = subprocess.run(cmd, input=input, timeout=timeout, capture_output=True, text=True, env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "DEBIAN_FRONTEND": "noninteractive"})
    return p.returncode, (p.stdout + p.stderr)[-8000:]


def versions():
    _, inst = run(["dpkg-query", "-W", "-f=${Version}", PKG])
    _, pol = run(["apt-cache", "policy", PKG])
    cand = next((l.split()[-1] for l in pol.splitlines() if l.strip().startswith("Candidate:")), "")
    return inst.strip(), ("" if cand == "(none)" else cand)


def job(name, *cmds):
    if not lock.acquire(blocking=False):
        return False
    def go():
        try:
            st.update(state=name, log="")
            for c in cmds:
                rc, out = run(c)
                st["log"] += out
                if rc:
                    st["state"] = "error"
                    return
            st["state"] = "done"
        finally:
            lock.release()
    threading.Thread(target=go, daemon=True).start()
    return True


def setup(user, password, ssh):
    """최초 사용자 생성. 성공 시 None, 실패 시 사유 문자열."""
    if not (isinstance(user, str) and USER_RE.match(user)) or user in ("root", "tfui"):
        return "사용자명: 소문자/숫자/-/_ (시작은 문자), root·tfui 불가"
    if not isinstance(password, str) or len(password) < 8 or ":" in password or "\n" in password:
        return "비밀번호 8자 이상 (':' 불가)"
    with setup_lock:  # 동시 요청/재요청 방지
        if os.path.exists(DONE):
            return "이미 설정됨"
        steps = [(["useradd", "-m", "-s", "/bin/bash", "-G", "sudo,video,audio,input,render", user], None),
                 (["chpasswd"], f"{user}:{password}\n")]
        if ssh:
            steps.append((["systemctl", "enable", "--now", "ssh"], None))
        for cmd, inp in steps:
            rc, out = run(cmd, inp)
            if rc:
                return f"{cmd[0]} 실패: {out.strip()[-200:]}"
        os.makedirs(os.path.dirname(DONE), exist_ok=True)
        open(DONE, "w").close()
    return None


def unesc(f):
    return re.sub(r"\\(.)", r"\1", f)


def parse_wifi(out):
    """nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY 출력 -> (현재 SSID, [{ssid,signal,secure}] 신호순)"""
    best, cur = {}, ""
    for line in out.splitlines():
        f = [unesc(x) for x in re.split(r"(?<!\\):", line)]
        if len(f) != 4 or not f[1] or not f[2].isdigit():
            continue  # 숨김 SSID/경고 줄 무시
        if f[0] == "*":
            cur = f[1]
        n = {"ssid": f[1], "signal": int(f[2]), "secure": f[3] not in ("", "--"), "eap": "802.1X" in f[3]}
        if f[1] not in best or n["signal"] > best[f[1]]["signal"]:
            best[f[1]] = n
    return cur, sorted(best.values(), key=lambda n: -n["signal"])


def wifi_scan():
    rc, out = run(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"])
    if rc:
        return {"error": out.strip()[-200:] or "Wi-Fi 장치 없음"}
    cur, nets = parse_wifi(out)
    _, sv = run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"])
    saved = [unesc(x[0]) for x in (re.split(r"(?<!\\):", l) for l in sv.splitlines()) if len(x) == 2 and x[1] == "802-11-wireless"]
    for n in nets:
        n["saved"] = n["ssid"] in saved
    return {"current": cur, "networks": nets, "error": ""}


NM_DIR = "/etc/NetworkManager/system-connections"
BAD = re.compile(r"[\x00-\x1f]")


def nm(*a):
    return run(["nmcli", "-w", "45", *a])


def wifi_keyfile(ssid, password, hidden, eap, identity, phase2):
    """숨김 SSID / WPA-Enterprise 용 NM 키파일 (비밀은 argv 대신 0600 파일로). 실패 시 사유, 성공 시 None."""
    if eap and (eap not in ("peap", "ttls") or phase2 not in ("mschapv2", "pap") or not identity or not password):
        return "EAP: peap|ttls + mschapv2|pap, 아이디/비밀번호 필요"
    if ";" in ssid or any(BAD.search(x or "") for x in (ssid, password, identity)):
        return "SSID/아이디/비밀번호에 ';'·제어문자 불가"
    uid = str(uuid.uuid4())
    sec = ""
    if eap:
        sec = f"\n[wifi-security]\nkey-mgmt=wpa-eap\n\n[802-1x]\neap={eap};\nphase2-auth={phase2}\nidentity={identity}\npassword={password}\n"
    elif password:
        sec = f"\n[wifi-security]\nkey-mgmt=wpa-psk\npsk={password}\n"
    body = (f"[connection]\nid={ssid}\nuuid={uid}\ntype=wifi\n\n[wifi]\nssid={ssid}\nmode=infrastructure\n"
            f"hidden={'true' if hidden else 'false'}\n{sec}\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n")
    path = os.path.join(NM_DIR, f"tfos-{uid}.nmconnection")
    nm("connection", "delete", "id", ssid)  # 같은 이름 기존 프로필 교체
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(body)
    rc, out = nm("connection", "load", path)
    if not rc:
        rc, out = nm("connection", "up", "uuid", uid)
    if rc:
        nm("connection", "delete", "uuid", uid)
        if os.path.exists(path):
            os.remove(path)
        return out.strip()[-200:] or "연결 실패"
    return None


def wifi_action(d):
    ssid, act = d.get("ssid"), d.get("action") or "connect"
    if not isinstance(ssid, str) or not 0 < len(ssid.encode()) <= 32 or ssid.startswith("-"):
        return "SSID 오류"
    pw = d.get("password") or ""
    if act == "forget":
        rc, out = nm("connection", "delete", "id", ssid)
    elif act == "disconnect":  # 자동 재연결 방지 후 끊기
        nm("connection", "modify", "id", ssid, "connection.autoconnect", "no")
        rc, out = nm("connection", "down", "id", ssid)
    elif act == "saved":
        nm("connection", "modify", "id", ssid, "connection.autoconnect", "yes")
        rc, out = nm("connection", "up", "id", ssid)
    elif act == "connect":
        if d.get("eap") or d.get("hidden"):
            return wifi_keyfile(ssid, pw, bool(d.get("hidden")), d.get("eap") or "", d.get("identity") or "", d.get("phase2") or "mschapv2")
        if pw and (not isinstance(pw, str) or not 8 <= len(pw) <= 63):
            return "비밀번호 8~63자"
        if pw:  # 비밀번호는 argv(ps) 대신 stdin 으로
            rc, out = run(["nmcli", "-w", "45", "--ask", "dev", "wifi", "connect", ssid], pw + "\n")
        else:
            rc, out = nm("dev", "wifi", "connect", ssid)
        if rc:
            nm("connection", "delete", "id", ssid)  # 실패한 프로필 정리
    else:
        return "알 수 없는 action"
    return (out.strip()[-200:] or "실패") if rc else None


PREFER = ("Speaker", "Master", "PCM", "Playback", "Headphone")


def mixer_ctl():
    """재생 볼륨 조절 가능한 ALSA 컨트롤 이름 (코덱마다 달라서 우선순위로 탐색)."""
    rc, out = run(["amixer", "scontrols"])
    names = re.findall(r"'([^']+)',\d+", out) if not rc else []
    for n in sorted(names, key=lambda n: PREFER.index(n) if n in PREFER else len(PREFER)):
        rc, o = run(["amixer", "sget", n])
        if not rc and "pvolume" in o:
            return n, o
    return None, ""


def audio_get():
    _, cards = run(["aplay", "-l"])
    ctl, o = mixer_ctl()
    m = re.search(r"\[(\d+)%\]", o)
    return {"cards": cards.strip(), "control": ctl or "", "volume": int(m.group(1)) if m else -1}


def audio_set(vol):
    if not isinstance(vol, int) or isinstance(vol, bool) or not 0 <= vol <= 100:
        return "volume 0~100"
    ctl, _ = mixer_ctl()
    if not ctl:
        return "사운드 카드 없음"
    rc, out = run(["amixer", "sset", ctl, f"{vol}%", "unmute"])
    return (out.strip()[-200:] or "실패") if rc else None


def audio_test():
    rc, out = run(["speaker-test", "-t", "sine", "-f", "440", "-c", "2"], timeout=2)
    return (out.strip()[-200:] or "실패") if rc else None


def hw():
    """진단용. 표준 인터페이스(V4L2, PC/SC CCID, libnfc 지원 칩)로 보이는 것만 보고."""
    cams = []
    for d in sorted(glob.glob("/sys/class/video4linux/video*")):
        try:
            cams.append({"dev": "/dev/" + os.path.basename(d), "name": open(d + "/name").read().strip()})
        except OSError:
            pass
    _, ic = run(["opensc-tool", "--list-readers"])
    _, nfc = run(["nfc-list"])
    return {"camera": cams, "ic": ic.strip(), "nfc": nfc.strip()}


class H(BaseHTTPRequestHandler):
    def reply(self, code=200):
        inst, cand = versions()
        self.json(dict(st, installed=inst, candidate=cand, update=bool(cand and cand != inst)), code)

    def do_GET(self):
        if self.path == "/setup":
            self.json({"done": os.path.exists(DONE)})
        elif self.path == "/wifi":
            self.json(wifi_scan())
        elif self.path == "/audio":
            self.json(audio_get())
        elif self.path == "/hw":
            self.json(hw())
        elif self.path == "/status":
            self.reply()
        else:
            self.send_error(404)

    def json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_POST(self):
        if self.path == "/setup":
            try:
                d = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            except ValueError:
                return self.json({"error": "bad json"}, 400)
            err = setup(d.get("user"), d.get("password"), bool(d.get("ssh")))
            return self.json({"done": not err, "error": err or ""}, 200 if not err else 400)
        if self.path == "/audio/test":
            err = audio_test()
            return self.json({"ok": not err, "error": err or ""}, 200 if not err else 400)
        if self.path == "/audio":
            try:
                err = audio_set(json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)))).get("volume"))
            except ValueError:
                err = "bad json"
            return self.json({"ok": not err, "error": err or ""}, 200 if not err else 400)
        if self.path == "/wifi":
            try:
                d = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            except ValueError:
                return self.json({"error": "bad json"}, 400)
            err = wifi_action(d)
            return self.json({"ok": not err, "error": err or ""}, 200 if not err else 400)
        if self.path == "/check":
            ok = job("checking", UPDATE)
        elif self.path == "/upgrade":
            ok = job("upgrading", UPDATE, UPGRADE)
        elif self.path == "/reboot":
            if st["state"] in ("checking", "upgrading"):
                return self.reply(409)  # dpkg 도중 재부팅 금지
            self.reply()
            subprocess.Popen(["systemctl", "reboot"])
            return
        else:
            return self.send_error(404)
        self.reply(200 if ok else 409)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
