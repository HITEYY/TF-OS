import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.VirtualKeyboard
import QtMultimedia

// 터치용: 크기는 화면 높이 기준(해상도 미확정). 페이지 2개: 홈 / 업데이트.
ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: "#101418"
    readonly property real u: height / 12   // 기본 단위
    property var ota: ({ state: "idle", log: "", installed: "?", candidate: "", update: false })
    property string err: ""

    function call(method, path) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (x.status === 0) { err = "OTA 데몬 연결 실패"; return }
            err = ""
            ota = JSON.parse(x.responseText)
        }
        x.open(method, "http://127.0.0.1:8765" + path)
        x.send()
    }
    // 작업 중에만 폴링
    Timer {
        interval: 1500; repeat: true
        running: win.ota.state === "checking" || win.ota.state === "upgrading"
        onTriggered: win.call("GET", "/status")
    }
    property int setupDone: -1   // -1 확인 전, 0 필요, 1 완료
    property string setupErr: ""
    function postSetup(user, pw, ssh) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (x.status === 0) { setupErr = "데몬 연결 실패"; return }
            var r = JSON.parse(x.responseText)
            setupErr = r.error
            if (r.done) setupDone = 1
        }
        x.open("POST", "http://127.0.0.1:8765/setup")
        x.send(JSON.stringify({ user: user, password: pw, ssh: ssh }))
    }
    Component.onCompleted: {
        call("GET", "/status")
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE)
                setupDone = (x.status === 200 && JSON.parse(x.responseText).done) ? 1 : (x.status === 200 ? 0 : -1)
        }
        x.open("GET", "http://127.0.0.1:8765/setup")
        x.send()
    }

    component Tile: Button {
        id: t
        Layout.fillWidth: true; Layout.fillHeight: true
        font.pixelSize: win.u * 0.7
        contentItem: Text { text: t.text; font: t.font; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; wrapMode: Text.Wrap }
        background: Rectangle { radius: win.u * 0.3; color: !t.enabled ? "#2a3038" : t.down ? "#2f6fdb" : "#3b82f6" }
    }

    // 상단바
    Rectangle {
        id: bar
        width: parent.width; height: win.u * 1.2; color: "#1a2027"
        Text {
            anchors.centerIn: parent; color: "white"; font.pixelSize: win.u * 0.6
            text: "TF-OS"
        }
        Text {
            anchors { right: parent.right; rightMargin: win.u * 0.4; verticalCenter: parent.verticalCenter }
            color: "#9aa4b2"; font.pixelSize: win.u * 0.6
            Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
                    onTriggered: parent.text = Qt.formatTime(new Date(), "hh:mm") }
        }
    }

    StackView {
        id: stack
        anchors { top: bar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: win.u * 0.4 }
        initialItem: GridLayout {
            columns: 2; rowSpacing: win.u * 0.4; columnSpacing: win.u * 0.4
            Tile { text: "Wi-Fi"; onClicked: stack.push(wifiPage) }
            Tile { text: "하드웨어"; onClicked: stack.push(hwPage) }
            Tile { text: "업데이트"; onClicked: stack.push(updatePage) }
            Tile { text: "재부팅"; onClicked: win.call("POST", "/reboot") }
        }
    }

    Component {
        id: updatePage
        ColumnLayout {
            spacing: win.u * 0.3
            Text { color: "white"; font.pixelSize: win.u * 0.6
                   text: "현재 " + win.ota.installed + (win.ota.candidate ? "  /  최신 " + win.ota.candidate : "") }
            Text { color: win.err || win.ota.state === "error" ? "#f87171" : "#9aa4b2"; font.pixelSize: win.u * 0.5
                   text: win.err ? win.err : ({ idle: "", checking: "확인 중…", upgrading: "설치 중… 전원 끄지 마세요",
                         done: win.ota.update ? "완료. 재부팅하면 적용됩니다" : "최신 버전입니다", error: "실패" })[win.ota.state] }
            Flickable {   // 로그: 에러 때 원인 확인용
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                contentHeight: logText.height
                Text { id: logText; width: parent.width; color: "#6b7686"; wrapMode: Text.Wrap
                       font.pixelSize: win.u * 0.3; text: win.ota.log }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: win.u * 1.6; spacing: win.u * 0.3
                readonly property bool busy: win.ota.state === "checking" || win.ota.state === "upgrading"
                Tile { text: "뒤로"; onClicked: stack.pop() }
                Tile { text: "확인"; enabled: !parent.busy; onClicked: win.call("POST", "/check") }
                Tile { text: "설치"; enabled: !parent.busy && win.ota.update; onClicked: win.call("POST", "/upgrade") }
                Tile { text: "재부팅"; enabled: !parent.busy; onClicked: win.call("POST", "/reboot") }
            }
        }
    }

    Component {
        id: wifiPage
        ColumnLayout {
            id: wp
            spacing: win.u * 0.25
            property var nets: []
            property string cur: ""
            property string msg: ""
            property bool busy: false
            property var sel: null    // 선택한 망 (숨김망 추가면 hidden:true)
            readonly property bool hid: sel !== null && sel.hidden === true
            readonly property bool eap: hid ? fEap.checked : (sel !== null && sel.eap === true)
            readonly property string ssid: hid ? fSsid.text : (sel ? sel.ssid : "")

            function req(method, body, done) {
                busy = true
                var x = new XMLHttpRequest()
                x.onreadystatechange = function () {
                    if (x.readyState !== XMLHttpRequest.DONE) return
                    busy = false
                    if (x.status === 0) { msg = "데몬 연결 실패"; return }
                    done(JSON.parse(x.responseText))
                }
                x.open(method, "http://127.0.0.1:8765/wifi")
                x.send(body ? JSON.stringify(body) : undefined)
            }
            function scan() {
                msg = "검색 중…"
                req("GET", null, function (r) {
                    msg = r.error; if (r.error) return
                    nets = r.networks; cur = r.current
                })
            }
            function act(action) {
                msg = ssid + " …"
                var b = { action: action, ssid: ssid }
                if (action === "connect") {
                    b.password = fPw.text; b.hidden = hid
                    if (eap) { b.eap = fMethod.currentText; b.phase2 = fPhase2.currentText; b.identity = fId.text }
                }
                req("POST", b, function (r) {
                    msg = r.ok ? "" : r.error
                    if (r.ok) { sel = null; fPw.text = ""; fId.text = ""; fSsid.text = ""; scan() }
                })
            }
            Component.onCompleted: scan()

            Text { color: "white"; font.pixelSize: win.u * 0.55; text: cur ? "연결됨: " + cur : "연결 안 됨" }
            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#9aa4b2"; font.pixelSize: win.u * 0.4; text: wp.msg }

            // 선택한 망 설정 패널
            ColumnLayout {
                visible: wp.sel !== null
                Layout.fillWidth: true; spacing: win.u * 0.15
                Text { visible: !wp.hid; color: "white"; font.pixelSize: win.u * 0.5; text: wp.ssid }
                TextField { id: fSsid; visible: wp.hid; Layout.fillWidth: true; font.pixelSize: win.u * 0.45; placeholderText: "SSID (숨김 망)" }
                CheckBox { id: fEap; visible: wp.hid; text: "802.1X (기업망)"; font.pixelSize: win.u * 0.4 }
                RowLayout {
                    visible: wp.eap; Layout.fillWidth: true
                    ComboBox { id: fMethod; model: ["peap", "ttls"]; font.pixelSize: win.u * 0.4 }
                    ComboBox { id: fPhase2; model: ["mschapv2", "pap"]; font.pixelSize: win.u * 0.4 }
                    TextField { id: fId; Layout.fillWidth: true; font.pixelSize: win.u * 0.45; placeholderText: "아이디"
                                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText }
                }
                TextField { id: fPw; visible: wp.eap || (wp.sel !== null && (wp.hid || wp.sel.secure))
                            Layout.fillWidth: true; echoMode: TextInput.Password; font.pixelSize: win.u * 0.45
                            placeholderText: wp.hid && !wp.eap ? "비밀번호 (열린 망이면 비움)" : "비밀번호" }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: win.u * 1.1; spacing: win.u * 0.2
                    readonly property bool isCur: wp.sel !== null && wp.ssid === wp.cur
                    readonly property bool isSaved: wp.sel !== null && wp.sel.saved === true
                    Tile { text: "취소"; onClicked: wp.sel = null }
                    Tile { text: "잊기"; visible: parent.isSaved; enabled: !wp.busy; onClicked: wp.act("forget") }
                    Tile { text: "끊기"; visible: parent.isCur; enabled: !wp.busy; onClicked: wp.act("disconnect") }
                    Tile { text: "저장된 설정으로 연결"; visible: parent.isSaved && !parent.isCur; enabled: !wp.busy; onClicked: wp.act("saved") }
                    Tile {
                        text: "연결"; visible: !parent.isCur
                        enabled: !wp.busy && wp.ssid !== "" && (!wp.eap || (fId.text !== "" && fPw.text !== ""))
                                 && (fPw.text === "" || fPw.text.length >= 8 || wp.eap)
                        onClicked: wp.act("connect")
                    }
                }
            }
            ListView {
                visible: wp.sel === null
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: win.u * 0.15
                model: wp.nets
                delegate: Rectangle {
                    width: ListView.view.width; height: win.u * 1.2; radius: win.u * 0.2
                    color: modelData.ssid === wp.cur ? "#1f3a66" : "#1a2027"
                    Text { anchors { left: parent.left; leftMargin: win.u * 0.3; verticalCenter: parent.verticalCenter }
                           color: "white"; font.pixelSize: win.u * 0.5
                           text: (modelData.secure ? "🔒 " : "") + modelData.ssid + (modelData.saved ? "  ★" : "") }
                    Text { anchors { right: parent.right; rightMargin: win.u * 0.3; verticalCenter: parent.verticalCenter }
                           color: "#9aa4b2"; font.pixelSize: win.u * 0.4; text: modelData.signal + "%" }
                    MouseArea {
                        anchors.fill: parent; enabled: !wp.busy
                        onClicked: {
                            // 열린 미저장 망은 바로 연결, 나머지는 패널
                            if (!modelData.secure && !modelData.saved && modelData.ssid !== wp.cur) { wp.sel = modelData; wp.act("connect") }
                            else wp.sel = modelData
                        }
                    }
                }
            }
            RowLayout {
                visible: wp.sel === null
                Layout.fillWidth: true; Layout.preferredHeight: win.u * 1.6; spacing: win.u * 0.3
                Tile { text: "뒤로"; onClicked: stack.pop() }
                Tile { text: "다시 검색"; enabled: !wp.busy; onClicked: wp.scan() }
                Tile { text: "숨김 망 추가"; onClicked: wp.sel = { hidden: true, secure: true, ssid: "" } }
            }
        }
    }

    Component {
        id: hwPage
        ColumnLayout {
            id: hp
            spacing: win.u * 0.25
            property var info: ({ camera: [], ic: "", nfc: "" })
            property var snd: ({ cards: "", control: "", volume: -1 })
            property string sndMsg: ""
            property bool busy: false
            function sndCall(method, path, body, done) {
                var x = new XMLHttpRequest()
                x.onreadystatechange = function () {
                    if (x.readyState === XMLHttpRequest.DONE) done(x.status, x.status ? JSON.parse(x.responseText) : null)
                }
                x.open(method, "http://127.0.0.1:8765" + path)
                x.send(body ? JSON.stringify(body) : undefined)
            }
            function sndLoad() { sndCall("GET", "/audio", null, function (st, r) { if (st === 200) snd = r }) }
            function refresh() {
                busy = true
                var x = new XMLHttpRequest()
                x.onreadystatechange = function () {
                    if (x.readyState !== XMLHttpRequest.DONE) return
                    busy = false
                    if (x.status === 200) info = JSON.parse(x.responseText)
                }
                x.open("GET", "http://127.0.0.1:8765/hw")
                x.send()
            }
            Component.onCompleted: { refresh(); sndLoad() }

            // 스피커: ALSA 사운드 카드 필요 (코덱 DTS)
            RowLayout {
                Layout.fillWidth: true; spacing: win.u * 0.2
                Text { color: "white"; font.pixelSize: win.u * 0.45; text: "스피커" }
                Slider {
                    id: vol; Layout.fillWidth: true; from: 0; to: 100; stepSize: 5
                    enabled: hp.snd.volume >= 0
                    value: hp.snd.volume >= 0 ? hp.snd.volume : 0
                    // 손을 뗄 때만 적용 (드래그 중 매 값마다 호출 방지)
                    onPressedChanged: if (!pressed) hp.sndCall("POST", "/audio", { volume: Math.round(value) }, function (st, r) { hp.sndMsg = st === 200 ? "" : (r ? r.error : "데몬 연결 실패") })
                }
                Text { color: "#9aa4b2"; font.pixelSize: win.u * 0.4; text: hp.snd.volume >= 0 ? Math.round(vol.value) + "%" : "없음" }
                Tile { text: "테스트음"; Layout.fillWidth: false; Layout.preferredWidth: win.u * 3; Layout.preferredHeight: win.u * 1.1
                       enabled: hp.snd.volume >= 0
                       onClicked: hp.sndCall("POST", "/audio/test", null, function (st, r) { hp.sndMsg = st === 200 ? "" : (r ? r.error : "데몬 연결 실패") }) }
            }
            Text { visible: hp.sndMsg !== ""; color: "#f87171"; font.pixelSize: win.u * 0.35; text: hp.sndMsg }

            // 카메라: V4L2 장치가 있어야 함 (센서 DTS 필요)
            Switch { id: camOn; text: "카메라 미리보기 (" + hp.info.camera.length + "개)"; font.pixelSize: win.u * 0.45
                     enabled: hp.info.camera.length > 0 }
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: camOn.checked ? win.u * 4.5 : 0; clip: true
                VideoOutput { id: vo; anchors.fill: parent; visible: camOn.checked }
                CaptureSession { camera: Camera { active: camOn.checked }; videoOutput: vo }
            }
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentHeight: t.height
                Text { id: t; width: parent.width; wrapMode: Text.Wrap; color: "#c9d1dc"
                       font.pixelSize: win.u * 0.3; font.family: "monospace"
                       text: "[사운드 카드" + (hp.snd.control ? ", 컨트롤 " + hp.snd.control : "") + "]\n" + (hp.snd.cards || "카드 없음")
                             + "\n\n[IC 카드 리더 PC/SC]\n" + (hp.info.ic || "리더 없음")
                             + "\n\n[NFC]\n" + (hp.info.nfc || "리더 없음")
                             + "\n\n[MST]\n미지원: 표준 리눅스 인터페이스 없음 (전용 보안 MCU)" }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: win.u * 1.6; spacing: win.u * 0.3
                Tile { text: "뒤로"; onClicked: stack.pop() }
                Tile { text: hp.busy ? "읽는 중…" : "IC·NFC 읽기"; enabled: !hp.busy; onClicked: hp.refresh() }
            }
        }
    }

    // 최초 설정: 사용자 생성 + SSH. 완료 전까지 다른 화면 가림.
    Rectangle {
        id: setup
        visible: win.setupDone === 0
        anchors.fill: parent; color: "#101418"
        ColumnLayout {
            x: win.u * 0.5; width: parent.width - win.u
            y: Math.max(win.u * 0.3, (kb.active ? kb.y : parent.height) - height - win.u * 0.3)
            spacing: win.u * 0.25
            Text { text: "처음 설정"; color: "white"; font.pixelSize: win.u * 0.8 }
            TextField { id: fUser; Layout.fillWidth: true; placeholderText: "사용자 이름 (영문 소문자)"
                        font.pixelSize: win.u * 0.5; inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhLowercaseOnly }
            TextField { id: fPw; Layout.fillWidth: true; placeholderText: "비밀번호 (8자 이상)"
                        font.pixelSize: win.u * 0.5; echoMode: TextInput.Password }
            TextField { id: fPw2; Layout.fillWidth: true; placeholderText: "비밀번호 확인"
                        font.pixelSize: win.u * 0.5; echoMode: TextInput.Password }
            CheckBox { id: fSsh; checked: true; text: "SSH 켜기"; font.pixelSize: win.u * 0.5 }
            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: win.u * 0.4; color: "#f87171"
                   text: fPw.text !== fPw2.text && fPw2.text !== "" ? "비밀번호가 다릅니다" : win.setupErr }
            Tile {
                Layout.fillHeight: false; Layout.preferredHeight: win.u * 1.3
                text: "만들기"; enabled: fUser.text !== "" && fPw.text.length >= 8 && fPw.text === fPw2.text
                onClicked: win.postSetup(fUser.text, fPw.text, fSsh.checked)
            }
        }
    }
    InputPanel {
        id: kb
        z: 99
        width: parent.width
        y: active ? parent.height - height : parent.height
    }
}
