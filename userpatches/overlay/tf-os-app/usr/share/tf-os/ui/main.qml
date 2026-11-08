import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.VirtualKeyboard
import QtMultimedia

// 토스 스타일 터치 UI. 크기는 화면 높이 기준(Theme.u = 높이/12) — 해상도 미확정이라.
// 위젯/토큰은 같은 폴더의 Theme.qml, Btn.qml 등 (qmldir).
ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: Theme.bg
    font.family: Theme.family
    readonly property real m: Theme.u * 0.5      // 화면 좌우 여백
    Binding { target: Theme; property: "u"; value: win.height / 12 }

    // ---- 데몬 호출 ----
    readonly property string api: "http://127.0.0.1:8765"
    function http(method, path, body, done) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            done(x.status, x.status ? JSON.parse(x.responseText) : null)
        }
        x.open(method, api + path)
        x.send(body ? JSON.stringify(body) : undefined)
    }

    // ---- OTA 상태 ----
    property var ota: ({ state: "idle", log: "", installed: "", candidate: "", update: false })
    property string lastAct: ""          // 사용자가 마지막에 시작한 작업: check | upgrade
    property bool daemonDown: false
    readonly property bool otaBusy: ota.state === "checking" || ota.state === "upgrading"
    function otaPoll() { http("GET", "/status", null, function (st, r) { daemonDown = st !== 200; if (r) ota = r }) }
    function otaDo(path, name) { lastAct = name; http("POST", path, null, function (st, r) { daemonDown = st === 0; if (r) ota = r }) }
    Timer { interval: 1500; repeat: true; running: win.otaBusy; onTriggered: win.otaPoll() }

    // ---- 재부팅 확인 시트 ----
    property bool askReboot: false

    // ---- 최초 설정 ----
    property int setupDone: -1   // -1 확인 전, 0 필요, 1 완료
    property string setupErr: ""
    Component.onCompleted: {
        otaPoll()
        http("GET", "/setup", null, function (st, r) { setupDone = st === 200 ? (r.done ? 1 : 0) : -1 })
    }

    // 상단: 시계만 (조용하게)
    Label {
        id: clock
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: Theme.u * 0.2 }
        font.pixelSize: Theme.u * 0.38; color: Theme.hint
        Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm") }
    }

    StackView {
        id: stack
        anchors { top: parent.top; topMargin: Theme.u * 0.6; bottom: parent.bottom; left: parent.left; right: parent.right
                  leftMargin: win.m; rightMargin: win.m; bottomMargin: win.m }
        initialItem: homePage
        pushEnter: Transition { ParallelAnimation {
            NumberAnimation { property: "x"; from: stack.width * 0.25; to: 0; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260 } } }
        pushExit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 160 } }
        popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
        popExit: Transition { ParallelAnimation {
            NumberAnimation { property: "x"; from: 0; to: stack.width * 0.25; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; to: 0; duration: 220 } } }
    }

    // ================= 홈 =================
    Component {
        id: homePage
        ColumnLayout {
            spacing: Theme.u * 0.35
            Label { Layout.topMargin: Theme.u * 0.6; text: "안녕하세요"; font.pixelSize: Theme.u * 0.9; font.bold: true; color: Theme.text }
            Label { text: "TF-OS " + win.ota.installed; font.pixelSize: Theme.u * 0.4; color: Theme.sub }
            Item { Layout.preferredHeight: Theme.u * 0.3 }
            Card {
                Layout.fillWidth: true
                ListRow { Layout.fillWidth: true; title: "Wi-Fi"; sub: "네트워크 연결"; onClicked: stack.push(wifiPage) }
                ListRow { Layout.fillWidth: true; title: "하드웨어"; sub: "스피커 · 카메라 · IC · NFC"; onClicked: stack.push(hwPage) }
                ListRow { Layout.fillWidth: true; title: "업데이트"; sub: win.ota.update ? "새 버전이 있어요" : "소프트웨어 버전"
                          trail: win.ota.update ? win.ota.candidate : win.ota.installed; onClicked: stack.push(updatePage) }
            }
            Card {
                Layout.fillWidth: true
                ListRow { Layout.fillWidth: true; title: "재부팅"; titleColor: Theme.red; chevron: false; onClicked: win.askReboot = true }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ================= 업데이트 =================
    Component {
        id: updatePage
        ColumnLayout {
            id: up
            spacing: Theme.u * 0.3
            readonly property bool installed: win.ota.state === "done" && win.lastAct === "upgrade"
            readonly property string title: win.daemonDown ? "연결할 수 없어요"
                : win.ota.state === "checking" ? "확인하고 있어요"
                : win.ota.state === "upgrading" ? "설치하고 있어요"
                : win.ota.state === "error" ? "문제가 생겼어요"
                : installed ? "설치가 끝났어요"
                : win.ota.update ? "새 버전이 있어요"
                : (win.ota.state === "done" || win.lastAct === "check") ? "최신 버전이에요"
                : "업데이트를 확인해 볼까요?"
            readonly property string sub: win.daemonDown ? "시스템 서비스에 연결하지 못했어요"
                : win.ota.state === "upgrading" ? "전원을 끄지 마세요"
                : installed ? "재부팅하면 새 버전이 적용돼요"
                : win.ota.update ? win.ota.installed + " → " + win.ota.candidate
                : "현재 버전 " + win.ota.installed

            PageHead { Layout.fillWidth: true; title: up.title; sub: up.sub; onBackClicked: stack.pop() }
            Item { Layout.fillHeight: true; Layout.fillWidth: true
                // 오류일 때만 로그 노출 (원인 확인용)
                Card {
                    visible: win.ota.state === "error"
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Theme.u * 0.3 }
                    pad: Theme.u * 0.3
                    height: Math.min(parent.height - Theme.u * 0.3, lg.implicitHeight + 2 * pad)
                    Flickable {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentHeight: lg.height
                        Label { id: lg; width: parent.width; wrapMode: Text.Wrap; color: Theme.sub
                                font.pixelSize: Theme.u * 0.3; font.family: "monospace"; text: win.ota.log }
                    }
                }
            }
            Btn {
                Layout.fillWidth: true
                text: win.otaBusy ? "진행 중…" : up.installed ? "재부팅" : win.ota.update ? "설치하기" : win.ota.state === "error" ? "다시 시도" : "업데이트 확인"
                enabled: !win.otaBusy && !win.daemonDown
                onClicked: up.installed ? win.askReboot = true : win.ota.update ? win.otaDo("/upgrade", "upgrade") : win.otaDo("/check", "check")
            }
        }
    }

    // ================= Wi-Fi =================
    Component {
        id: wifiPage
        ColumnLayout {
            id: wp
            spacing: Theme.u * 0.3
            property var nets: []
            property string cur: ""
            property string msg: ""
            property bool bad: false
            property bool busy: false
            property var sel: null    // 선택한 망 (숨김망 추가면 hidden:true)
            readonly property bool hid: sel !== null && sel.hidden === true
            readonly property bool eap: hid ? fEap.checked : (sel !== null && sel.eap === true)
            readonly property string ssid: hid ? fSsid.text : (sel ? sel.ssid : "")
            readonly property bool isCur: sel !== null && ssid === cur
            readonly property bool isSaved: sel !== null && sel.saved === true

            function say(t, isBad) { msg = t; bad = !!isBad }
            function req(method, body, done) {
                busy = true
                win.http(method, "/wifi", body, function (st, r) {
                    busy = false
                    if (st === 0) { say("데몬 연결 실패", true); return }
                    done(r)
                })
            }
            function scan() {
                say("주변 Wi-Fi를 찾는 중이에요")
                req("GET", null, function (r) {
                    if (r.error) { say(r.error, true); return }
                    say(""); nets = r.networks; cur = r.current
                })
            }
            function act(action) {
                say(ssid + " 연결 중이에요")
                var b = { action: action, ssid: ssid }
                if (action === "connect") {
                    b.password = fPw.text; b.hidden = hid
                    if (eap) { b.eap = fMethod.current; b.phase2 = fPhase2.current; b.identity = fId.text }
                }
                req("POST", b, function (r) {
                    if (!r.ok) { say(r.error, true); return }
                    say(""); sel = null; fPw.text = ""; fId.text = ""; fSsid.text = ""; scan()
                })
            }
            Component.onCompleted: scan()

            PageHead {
                Layout.fillWidth: true
                title: wp.sel === null ? "Wi-Fi" : (wp.hid ? "숨김 망 추가" : wp.ssid)
                sub: wp.sel === null ? (wp.cur ? wp.cur + "에 연결됨" : "연결된 망이 없어요") : ""
                action: wp.sel === null ? "새로고침" : ""
                onBackClicked: wp.sel === null ? stack.pop() : wp.sel = null
                onActionClicked: if (!wp.busy) wp.scan()
            }
            Label { Layout.fillWidth: true; visible: wp.msg !== ""; wrapMode: Text.Wrap; text: wp.msg
                    font.pixelSize: Theme.u * 0.36; color: wp.bad ? Theme.red : Theme.hint }

            // --- 망 목록 ---
            Card {
                visible: wp.sel === null
                Layout.fillWidth: true; Layout.fillHeight: true
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    model: wp.nets
                    delegate: ListRow {
                        width: ListView.view.width
                        title: modelData.ssid
                        sub: (modelData.saved ? "저장됨" : "") + (modelData.saved && modelData.secure ? " · " : "") + (modelData.secure ? (modelData.eap ? "기업망" : "보안") : (modelData.saved ? "" : "열린 망"))
                        trail: modelData.ssid === wp.cur ? "연결됨" : ""
                        strength: modelData.signal
                        highlight: modelData.ssid === wp.cur
                        onClicked: {
                            if (wp.busy) return
                            // 열린 미저장 망은 바로 연결, 나머지는 설정 화면
                            wp.sel = modelData
                            if (!modelData.secure && !modelData.saved && modelData.ssid !== wp.cur) wp.act("connect")
                        }
                    }
                }
            }
            Btn { visible: wp.sel === null; Layout.fillWidth: true; kind: "secondary"; text: "숨김 망 추가"
                  onClicked: wp.sel = { hidden: true, secure: true, ssid: "" } }

            // --- 선택한 망 설정 ---
            Card {
                visible: wp.sel !== null
                Layout.fillWidth: true
                pad: Theme.u * 0.3
                ColumnLayout {
                    Layout.fillWidth: true; spacing: Theme.u * 0.25
                    Field { id: fSsid; visible: wp.hid; Layout.fillWidth: true; placeholderText: "SSID" }
                    Toggle { id: fEap; visible: wp.hid; Layout.fillWidth: true; text: "기업망 (802.1X)" }
                    ColumnLayout {
                        visible: wp.eap; Layout.fillWidth: true; spacing: Theme.u * 0.15
                        Seg { id: fMethod; options: ["peap", "ttls"] }
                        Seg { id: fPhase2; options: ["mschapv2", "pap"] }
                    }
                    Field { id: fId; visible: wp.eap; Layout.fillWidth: true; placeholderText: "아이디"
                            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText }
                    Field { id: fPw; Layout.fillWidth: true; echoMode: TextInput.Password
                            visible: wp.eap || (wp.sel !== null && (wp.hid || wp.sel.secure))
                            placeholderText: wp.hid && !wp.eap ? "비밀번호 (열린 망이면 비움)" : "비밀번호" }
                    Label { visible: wp.isCur; text: "지금 연결된 망이에요"; font.pixelSize: Theme.u * 0.38; color: Theme.sub }
                }
            }
            Item { Layout.fillHeight: true; visible: wp.sel !== null }
            RowLayout {
                visible: wp.sel !== null
                Layout.fillWidth: true; spacing: Theme.u * 0.25
                Btn { visible: wp.isSaved; kind: "danger"; text: "잊기"; enabled: !wp.busy; onClicked: wp.act("forget") }
                Btn { visible: wp.isCur; Layout.fillWidth: true; kind: "danger"; text: "연결 끊기"; enabled: !wp.busy; onClicked: wp.act("disconnect") }
                Btn { visible: wp.isSaved && !wp.isCur; Layout.fillWidth: true; kind: "secondary"; text: "저장된 설정으로 연결"; enabled: !wp.busy; onClicked: wp.act("saved") }
                Btn {
                    visible: !wp.isCur; Layout.fillWidth: true; text: "연결"
                    enabled: !wp.busy && wp.ssid !== "" && (!wp.eap || (fId.text !== "" && fPw.text !== ""))
                             && (fPw.text === "" || fPw.text.length >= 8 || wp.eap)
                    onClicked: wp.act("connect")
                }
            }
        }
    }

    // ================= 하드웨어 =================
    Component {
        id: hwPage
        ColumnLayout {
            id: hp
            spacing: Theme.u * 0.3
            property var info: ({ camera: [], ic: "", nfc: "" })
            property var snd: ({ cards: "", control: "", volume: -1 })
            property string sndMsg: ""
            property bool busy: false
            function sndLoad() { win.http("GET", "/audio", null, function (st, r) { if (st === 200) snd = r }) }
            function refresh() {
                busy = true
                win.http("GET", "/hw", null, function (st, r) { busy = false; if (st === 200) info = r })
            }
            Component.onCompleted: { refresh(); sndLoad() }

            PageHead { Layout.fillWidth: true; title: "하드웨어"; action: hp.busy ? "읽는 중…" : "다시 읽기"
                       onBackClicked: stack.pop()
                       onActionClicked: if (!hp.busy) { hp.refresh(); hp.sndLoad() } }

            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                contentHeight: body.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: body
                    width: parent.width; spacing: Theme.u * 0.3

                    // 스피커: ALSA 사운드 카드 필요
                    Card {
                        Layout.fillWidth: true; pad: Theme.u * 0.35
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: Theme.u * 0.2
                            RowLayout {
                                Layout.fillWidth: true
                                Label { Layout.fillWidth: true; text: "스피커"; font.pixelSize: Theme.u * 0.46; font.bold: true; color: Theme.text }
                                Label { text: hp.snd.volume >= 0 ? Math.round(vol.value) + "%" : "사운드 카드 없음"; font.pixelSize: Theme.u * 0.38; color: Theme.sub }
                            }
                            Slider {
                                id: vol; Layout.fillWidth: true; from: 0; to: 100; stepSize: 5
                                enabled: hp.snd.volume >= 0
                                value: hp.snd.volume >= 0 ? hp.snd.volume : 0
                                background: Rectangle {
                                    x: vol.leftPadding; y: vol.topPadding + vol.availableHeight / 2 - height / 2
                                    width: vol.availableWidth; height: Theme.u * 0.14; radius: height / 2; color: Theme.off
                                    Rectangle { width: vol.visualPosition * parent.width; height: parent.height; radius: height / 2
                                                color: vol.enabled ? Theme.blue : Theme.offText }
                                }
                                handle: Rectangle {
                                    x: vol.leftPadding + vol.visualPosition * (vol.availableWidth - width)
                                    y: vol.topPadding + vol.availableHeight / 2 - height / 2
                                    width: Theme.u * 0.55; height: width; radius: width / 2; color: "white"
                                    border.width: 2; border.color: vol.enabled ? Theme.blue : Theme.offText
                                    scale: vol.pressed ? 1.15 : 1
                                    Behavior on scale { NumberAnimation { duration: 100 } }
                                }
                                // 손을 뗄 때만 적용 (드래그 중 매 값마다 호출 방지)
                                onPressedChanged: if (!pressed) win.http("POST", "/audio", { volume: Math.round(value) },
                                    function (st, r) { hp.sndMsg = st === 200 ? "" : (r ? r.error : "데몬 연결 실패") })
                            }
                            Label { visible: hp.sndMsg !== ""; text: hp.sndMsg; font.pixelSize: Theme.u * 0.34; color: Theme.red }
                            Btn { Layout.fillWidth: true; kind: "secondary"; text: "테스트음 재생"; enabled: hp.snd.volume >= 0
                                  onClicked: win.http("POST", "/audio/test", null, function (st, r) { hp.sndMsg = st === 200 ? "" : (r ? r.error : "데몬 연결 실패") }) }
                        }
                    }

                    // 카메라: V4L2 장치 필요
                    Card {
                        Layout.fillWidth: true; pad: Theme.u * 0.35
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: Theme.u * 0.2
                            Toggle { id: camOn; Layout.fillWidth: true; text: "카메라 (" + hp.info.camera.length + "개)"; enabled: hp.info.camera.length > 0 }
                            Rectangle {
                                visible: camOn.checked
                                Layout.fillWidth: true; Layout.preferredHeight: Theme.u * 4.5; radius: Theme.radius; color: "black"; clip: true
                                VideoOutput { id: vo; anchors.fill: parent }
                                CaptureSession {
                                    camera: Camera { active: camOn.checked }
                                    videoOutput: vo
                                }
                            }
                        }
                    }

                    // 장치 상태
                    Card {
                        Layout.fillWidth: true; pad: Theme.u * 0.35
                        Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.sub
                                font.pixelSize: Theme.u * 0.3; font.family: "monospace"
                                text: "[사운드 카드" + (hp.snd.control ? ", " + hp.snd.control : "") + "]\n" + (hp.snd.cards || "없음")
                                      + "\n\n[IC 리더 PC/SC]\n" + (hp.info.ic || "없음")
                                      + "\n\n[NFC]\n" + (hp.info.nfc || "없음")
                                      + "\n\n[MST]\n미지원 (전용 보안 MCU, 표준 리눅스 인터페이스 없음)" }
                    }
                }
            }
        }
    }

    // ================= 재부팅 확인 시트 =================
    Rectangle {
        anchors.fill: parent; color: "#80000000"; z: 50
        visible: opacity > 0; opacity: win.askReboot ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        MouseArea { anchors.fill: parent; onClicked: win.askReboot = false }
        Rectangle {
            width: parent.width; height: sheet.implicitHeight + Theme.u * 0.9
            y: win.askReboot ? parent.height - height : parent.height
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            color: Theme.card; radius: Theme.u * 0.5
            MouseArea { anchors.fill: parent }   // 시트 안 터치가 스크림으로 새지 않게
            ColumnLayout {
                id: sheet
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: win.m; topMargin: Theme.u * 0.5 }
                spacing: Theme.u * 0.3
                Label { text: "재부팅할까요?"; font.pixelSize: Theme.u * 0.65; font.bold: true; color: Theme.text }
                Label { text: "저장하지 않은 작업은 사라져요"; font.pixelSize: Theme.u * 0.4; color: Theme.sub }
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: Theme.u * 0.2; spacing: Theme.u * 0.25
                    Btn { Layout.fillWidth: true; kind: "secondary"; text: "취소"; onClicked: win.askReboot = false }
                    Btn { Layout.fillWidth: true; text: "재부팅"
                          onClicked: { win.askReboot = false; win.http("POST", "/reboot", null, function () {}) } }
                }
            }
        }
    }

    // ================= 최초 설정 (완료 전까지 전체 가림) =================
    Rectangle {
        id: setup
        z: 60
        visible: win.setupDone === 0
        anchors.fill: parent; color: Theme.bg
        ColumnLayout {
            x: win.m; width: parent.width - 2 * win.m
            y: Math.max(Theme.u * 0.6, (kb.active ? kb.y : parent.height - win.m) - height - Theme.u * 0.2)
            spacing: Theme.u * 0.25
            Label { text: "처음 오셨네요"; font.pixelSize: Theme.u * 0.85; font.bold: true; color: Theme.text }
            Label { text: "사용할 계정을 만들어요"; font.pixelSize: Theme.u * 0.42; color: Theme.sub }
            Item { Layout.preferredHeight: Theme.u * 0.1 }
            Field { id: sUser; Layout.fillWidth: true; placeholderText: "사용자 이름 (영문 소문자)"
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhLowercaseOnly }
            Field { id: sPw; Layout.fillWidth: true; placeholderText: "비밀번호 (8자 이상)"; echoMode: TextInput.Password }
            Field { id: sPw2; Layout.fillWidth: true; placeholderText: "비밀번호 확인"; echoMode: TextInput.Password }
            Toggle { id: sSsh; Layout.fillWidth: true; checked: true; text: "SSH 켜기" }
            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: Theme.u * 0.36; color: Theme.red
                    visible: text !== ""
                    text: sPw.text !== sPw2.text && sPw2.text !== "" ? "비밀번호가 달라요" : win.setupErr }
            Btn {
                Layout.fillWidth: true; text: "시작하기"
                enabled: sUser.text !== "" && sPw.text.length >= 8 && sPw.text === sPw2.text
                onClicked: win.http("POST", "/setup", { user: sUser.text, password: sPw.text, ssh: sSsh.checked },
                    function (st, r) {
                        if (st === 0) { win.setupErr = "데몬 연결 실패"; return }
                        win.setupErr = r.error
                        if (r.done) win.setupDone = 1
                    })
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
