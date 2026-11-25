// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Chih
// Application / UI controller for MaeShare on Fremantle (Maemo 5).
// The UI layer and this controller are written for Maemo 5 in this project; the
// network core is the separate `probe` binary (derived from MeeShare, see its header).
// Fremantle adaptations: no libcontentaction, no gconftool-2, Maemo 5 paths,
// and every Qt container iteration is index-based (the armel/glibc2.5 build
// has a QString/QMap foreach ABI defect that makes foreach iterate once).
// Drop-in replacement for the N9 controller. No libcontentaction, no gconftool-2.
// Every Qt container iteration is index-based: on this armel/glibc2.5 build the
// Q_FOREACH macro only visits the first element (see HANDOVER section 4).
#ifndef N9_TRANSFER_H
#define N9_TRANSFER_H
#include <QObject>
#include <QString>
#include <QStringList>
#include <QByteArray>
#include <QVariant>
#include <QMap>
#include <QDateTime>
#include <QTimer>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QFileInfo>
#include <QSettings>
#include <QProcess>
#include <QProcessEnvironment>
#include <QHostAddress>
#include <QNetworkInterface>
#include <QAbstractSocket>
#include <QCoreApplication>
#include <QLocale>
#include <QDebug>
#include <QImageReader>
#include <QApplication>
#include <QClipboard>
#if defined(__GLIBC__)
#include <malloc.h>
#endif
#include "parser.h"

class Transfer : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString localAddress READ localAddress NOTIFY changed)
    Q_PROPERTY(QString localAddresses READ localAddresses NOTIFY changed)
    Q_PROPERTY(QVariantList history READ history NOTIFY changed)
    Q_PROPERTY(QString localName READ localName NOTIFY changed)
    Q_PROPERTY(QString offer READ offer NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(bool listening READ listening NOTIFY changed)
    // 窗口是否在前台：不在前台就停掉波纹动画，别在后台白烧 CPU
    Q_PROPERTY(bool active READ active NOTIFY changed)
    Q_PROPERTY(QString folder READ folder NOTIFY changed)
    Q_PROPERTY(QVariantList entries READ entries NOTIFY changed)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY changed)
    Q_PROPERTY(QString selected READ selected NOTIFY changed)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY changed)
    Q_PROPERTY(QString selectedSummary READ selectedSummary NOTIFY changed)
    Q_PROPERTY(QString peer READ peer NOTIFY changed)
    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY changed)
    Q_PROPERTY(bool autoSave READ autoSave WRITE setAutoSave NOTIFY changed)
    Q_PROPERTY(QString receiveDirectory READ receiveDirectory NOTIFY changed)
    Q_PROPERTY(QString pickerMode READ pickerMode NOTIFY changed)
    Q_PROPERTY(int receivedCount READ receivedCount NOTIFY changed)
    Q_PROPERTY(QString receivedSummary READ receivedSummary NOTIFY changed)
    Q_PROPERTY(bool canOpenReceived READ canOpenReceived NOTIFY changed)
    Q_PROPERTY(bool receivedIsText READ receivedIsText NOTIFY changed)
    Q_PROPERTY(QString version READ version NOTIFY changed)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY changed)
    Q_PROPERTY(QString systemLanguage READ systemLanguage CONSTANT)

    QString state, message, dir, chosen, peerName, ip, pin, root, identity, receive, helper, ownName, operation, langTag;
    QString pendingOpen;
    QString pendingBrowse;          // 延迟一拍的目录跳转目标（见 browseDeferred）
    QString previewImagePath;      // 非空时 QML 直接用内置浮层显示图片（不占额外进程）
    int previewW = 0, previewH = 0; // 按原图长宽比算出的解码尺寸（见 previewDecode*）
    QString unsupportedExt, unsupportedFilePath;   // 非空 = 该图片格式这台设备解不了，QML 弹提示
    bool pendingSend, nameCustom;
    bool sendingTextMode;          // 本次发送的是一段文本消息（probe 会把 fileType 标成 text）
    QString receivedType;          // 最近一次接收到的 fileType（LocalSend 的 text 消息靠它识别）
    QVariantList listing, deviceList;
    QMap<QString, QVariantMap> known;
    QStringList selection, receivedBatch;
    QStringList stagedShare;   // 相册分享时插件拷过来的副本，发送结束后由客户端删掉
    QVariantList historyList;
    QProcess receiver, job;
    QTimer decisionTimer, expiry, awakeTimer, awakeGuard;
    bool awakeOn;
    bool keepAwakeOn;
    QByteArray receiverBuffer, jobOutput;
    bool working, stopping, canceled, automatic, receiving, receivedOpenable;
    // 本次 info 是「手输地址」发起的：成功后就地转成手动设备（持久化、免过期）
    bool manualAddr;
    bool appActive;
    int peerPort;
    QString pickMode, receiverFailure;
    // 最近一次接收的来源（probe 的 SENDER 事件），只用于历史记录
    QString lastSender, lastSenderIp;

    bool canChangeService() const { return !working && message.isEmpty() && !receiving; }
    void restartService() { if (listening()) { stopReceive(); startReceive(); } }
    static QString trUtf(const char *s) { return QCoreApplication::translate("App", s, 0, QCoreApplication::UnicodeUTF8); }
    void finish(QString text) { state = text; emit changed(); emit feedback(text); }

    // ---- 传输期间防 Wi-Fi 休眠 -------------------------------------------------
    // Maemo 的 MCE 在灭屏后会让 WLAN 进省电甚至断开，大文件中途容易失败。
    // MCE 的 req_display_blanking_pause 在 system bus 上（实测返回 method return），
    // 每次有效期约 30s，所以要周期续期；停止续期即「释放」，无需 resume 方法。
    Q_SLOT void pokeAwake() {
        QStringList args;
        args << "--system" << "--type=method_call" << "--dest=com.nokia.mce"
             << "/com/nokia/mce/request" << "com.nokia.mce.request.req_display_blanking_pause";
        QProcess::startDetached("/usr/bin/dbus-send", args);
        qDebug() << "AWAKE_POKE";
    }
    // MCE 在上只有两种可用手段（实测 req_cpu_blanking_pause / req_blanking_pause 都是
    // UnknownMethod，没有「允许息屏但保持 CPU/网络醒着」的独立请求）：
    //   req_display_blanking_pause —— 阻止自动灭屏，到期自动失效
    //   req_display_state_on / _off —— 直接点亮 / 熄灭屏幕
    // 所以「让传输不受息屏影响」只能靠不让屏幕自己灭；但用户主动按电源键灭屏时
    // 不再强行点亮（尊重用户），传输本身照常继续。
    void lightScreen() {
        QStringList args;
        args << "--system" << "--type=method_call" << "--dest=com.nokia.mce"
             << "/com/nokia/mce/request" << "com.nokia.mce.request.req_display_state_on";
        QProcess::startDetached("/usr/bin/dbus-send", args);
        qDebug() << "AWAKE_LIGHT";
    }
    Q_SLOT void awakeExpired() { setAwake(false); }
    void setAwake(bool on) {
        if (on && !keepAwakeOn) {
            // 用户在设置里关掉了「保持唤醒」：不占屏幕、不续期，靠 MCE 自然休眠
            if (awakeOn) { awakeOn = false; awakeTimer.stop(); awakeGuard.stop(); }
            return;
        }
        if (on) {
            // 只在「从无到有」的那一次点亮屏幕；续期（每 25 秒）只发 blanking_pause，
            // 这样用户中途按电源键灭屏不会被我们反复顶亮。
            if (!awakeOn) lightScreen();
            awakeOn = true;
            pokeAwake();
            if (!awakeTimer.isActive()) awakeTimer.start();
            awakeGuard.start();          // 每来一次事件就把保险窗口重新计时
        } else {
            if (awakeOn) qDebug() << "AWAKE_OFF";
            awakeOn = false;
            awakeTimer.stop();
            awakeGuard.stop();
        }
    }

    // 「保持唤醒」开关：默认开，只在传输期间生效（不发请求时完全不管屏幕，空闲时零开销）
    Q_PROPERTY(bool keepAwake READ keepAwake WRITE setKeepAwake NOTIFY changed)
    bool keepAwake() const { return keepAwakeOn; }
    void setKeepAwake(bool on) {
        if (keepAwakeOn == on) return;
        keepAwakeOn = on;
        QSettings("Chih", "MaeShare").setValue("keep_awake", on);
        qDebug() << "KEEP_AWAKE" << (on ? "on" : "off");
        if (!on) setAwake(false);       // 关掉时立即释放已有的锁
        emit changed();
    }

    void refreshList() {
        deviceList.clear();
        QStringList keys = known.keys();
        for (int i = 0; i < keys.size(); ++i) deviceList.append(known.value(keys.at(i)));
        emit changed();
    }
    void remember(QVariantMap m, QString address) {
        QString name = m.value("alias").toString().trimmed().left(100);
        if (name.isEmpty() || QHostAddress(address).isNull()) return;
        m["ip"] = address;
        m["lastSeen"] = QDateTime::currentDateTime().toTime_t();
        if (!m.contains("port")) m["port"] = 53317;
        if (!m.contains("protocol")) m["protocol"] = "https";
        // 手输地址添加的设备没有组播广播，不能按 75 秒过期清掉，也不能下次启动就忘
        if (manualAddr) { m["manual"] = true; saveManualPeer(m); }
        known[address] = m;
        if (ip == address) { peerName = name; peerPort = m.value("port").toInt(); }
        refreshList();
    }

    // 手输设备持久化：QSettings 里一行一台（ip \t alias \t port \t deviceType）。
    // 不用嵌套组：Qt4 的 ini 后端会把 "组\键" 写成内联键，childGroups() 反而取不到。
    void saveManualPeer(QVariantMap m) {
        QString ipKey = m.value("ip").toString();
        if (ipKey.isEmpty()) return;
        QSettings s("Chih", "MaeShare");
        QStringList list = s.value("manual_list").toStringList();
        QStringList out;
        for (int i = 0; i < list.size(); ++i) {
            QStringList f = list.at(i).split("\t");
            if (!f.isEmpty() && f.at(0) == ipKey) continue;
            out.append(list.at(i));
        }
        QStringList row;
        row << ipKey
            << m.value("alias").toString()
            << QString::number(m.value("port", 53317).toInt())
            << m.value("deviceType").toString();
        out.append(row.join("\t"));
        s.setValue("manual_list", out);
        s.sync();
    }
    void loadManualPeers() {
        QSettings s("Chih", "MaeShare");
        QStringList list = s.value("manual_list").toStringList();
        for (int i = 0; i < list.size(); ++i) {
            QStringList f = list.at(i).split("\t");
            if (f.size() < 2) continue;
            QString address = f.at(0);
            if (QHostAddress(address).isNull() || f.at(1).trimmed().isEmpty()) continue;
            QVariantMap m;
            m["ip"] = address;
            m["alias"] = f.at(1);
            m["port"] = f.size() > 2 ? f.at(2).toInt() : 53317;
            if (m.value("port").toInt() <= 0) m["port"] = 53317;
            m["deviceType"] = f.size() > 3 ? f.at(3) : QString("desktop");
            m["protocol"] = "https";
            m["manual"] = true;
            m["lastSeen"] = QDateTime::currentDateTime().toTime_t();
            known[address] = m;
        }
        refreshList();
    }
    void run(QString op, QStringList args) {
        operation = op; jobOutput.clear(); working = true; canceled = false;
        state = op == "info" ? trUtf("正在连接设备…") : op == "send" ? trUtf("等待对方接收…") : trUtf("正在准备设备名称…");
        setAwake(true);   // 发送期间不许灭屏，否则对端可能收不到后续分片
        applyProbeEnv(job);
        job.start(helper, args);
        if (op == "send") sendingTextMode = false;   // 环境变量已交给 probe，这里复位
        emit changed();
    }
    QString failureText() {
        QString e = QString::fromUtf8(jobOutput);
        if (e.contains("http_403") || e.contains("file_not_accepted")) return trUtf("对方拒绝接收。");
        if (e.contains("http_409")) return trUtf("对方正在处理其他传输，请稍后再试。");
        if (e.contains("http_401")) return trUtf("对方要求 PIN 验证，此版本暂不支持。");
        if (e.contains("http_429")) return trUtf("请求过于频繁，请稍后再试。");
        if (e.contains("timed out") || e.contains("timeout")) return trUtf("等待对方响应超时，请重试。");
        if (e.contains("peer_fingerprint_mismatch")) return trUtf("对方设备身份已变化，请重新连接后发送。");
        if (e.contains("file_read_failed")) return trUtf("无法访问本机配置目录，请检查是否被占用或存储空间不足。");
        if (e.contains("file_missing") || e.contains("file_read")) return trUtf("无法读取选中的文件，请重新选择。");
        return operation == "send" ? trUtf("发送失败，请检查网络及对方设备。") : trUtf("连接失败，请确认对方已打开 LocalSend。");
    }

public:
    Transfer()
        : working(false), stopping(false), canceled(false), automatic(false), receiving(false),
          receivedOpenable(false), manualAddr(false), peerPort(53317), pendingSend(false),
          nameCustom(false), sendingTextMode(false), appActive(true) {
        root = "/home/user/MyDocs";
        dir = root;
        // 固定使用 Maemo 的 user 家目录：应用若以 root 启动（调试），HOME 会变成 /root
        identity = QFileInfo("/home/user").isDir() ? QString("/home/user/.config/localsend")
                                                   : QDir::homePath() + "/.config/localsend";
        // 默认保存到 MyDocs 根目录（不再自动建 LocalSend 子目录）
        receive = root;
        helper = QCoreApplication::applicationDirPath() + "/probe";
        QDir().mkpath(identity);
        QDir().mkpath(receive);
        QSettings settings("Chih", "MaeShare");
        QString stored = QFileInfo(settings.value("receive_directory", receive).toString()).canonicalFilePath();
        // 迁移旧版本的默认目录 /home/user/MyDocs/LocalSend 到 MyDocs 根目录
        if (stored == root + "/LocalSend") {
            stored = root;
            settings.setValue("receive_directory", root);
        }
        if (stored == root || stored.startsWith(root + "/")) receive = stored;
        automatic = settings.value("auto_save", false).toBool();
        langTag = settings.value("language", "").toString();
        // 1.008 起语言保留 简体中文 / 繁體中文（香港 / 台灣）/ English / Čeština，旧版残留的其它 tag 一律回落「跟随系统」
        if (!langTag.isEmpty() && langTag != "zh_CN" && langTag != "zh_HK" && langTag != "zh_TW" && langTag != "en" && langTag != "cs") {
            langTag.clear();
            settings.setValue("language", "");
        }
        loadHistory();
        loadManualPeers();
        pickMode = "files";
        nameCustom = settings.value("name_custom", false).toBool();
        ip = settings.value("peer_ip", "").toString();
        ownName = trUtf("default_device_name");
        state = trUtf("正在准备局域网发现…");

        decisionTimer.setSingleShot(true);
        decisionTimer.setInterval(105000);
        connect(&decisionTimer, SIGNAL(timeout()), this, SLOT(rejectExpired()));
        expiry.setInterval(15000);
        connect(&expiry, SIGNAL(timeout()), this, SLOT(expirePeers()));
        expiry.start();

        // 防休眠：MCE 的 blanking pause 只保 30 秒，传输期间每 25 秒续一次；
        // 保险窗口 10 分钟，期间没有新事件会自动收手，避免异常退出手动清理。
        awakeOn = false;
        keepAwakeOn = settings.value("keep_awake", true).toBool();
        awakeTimer.setInterval(25000);
        connect(&awakeTimer, SIGNAL(timeout()), this, SLOT(pokeAwake()));
        awakeGuard.setSingleShot(true);
        awakeGuard.setInterval(600000);
        connect(&awakeGuard, SIGNAL(timeout()), this, SLOT(awakeExpired()));

        receiver.setProcessChannelMode(QProcess::MergedChannels);
        connect(&receiver, SIGNAL(readyRead()), this, SLOT(readReceiver()));
        connect(&receiver, SIGNAL(finished(int, QProcess::ExitStatus)), this, SLOT(receiverEnded()));
        connect(&receiver, SIGNAL(error(QProcess::ProcessError)), this, SLOT(receiverError(QProcess::ProcessError)));

        job.setProcessChannelMode(QProcess::MergedChannels);
        connect(&job, SIGNAL(readyRead()), this, SLOT(readJob()));
        connect(&job, SIGNAL(finished(int, QProcess::ExitStatus)), this, SLOT(jobEnded(int, QProcess::ExitStatus)));
        connect(&job, SIGNAL(error(QProcess::ProcessError)), this, SLOT(jobError(QProcess::ProcessError)));

        browse(root);
        QTimer::singleShot(0, this, SLOT(initialize()));
    }
    ~Transfer() {
        disconnect(&receiver, 0, this, 0);
        disconnect(&job, 0, this, 0);
        receiver.kill();
        receiver.waitForFinished(2000);
        job.kill();
        job.waitForFinished(2000);
    }

    QString localAddress() const {
        QList<QHostAddress> addresses = QNetworkInterface::allAddresses();
        for (int i = 0; i < addresses.size(); ++i) {
            QHostAddress a = addresses.at(i);
            quint32 n = a.toIPv4Address();
            if (a.protocol() == QAbstractSocket::IPv4Protocol && ((n >> 24) == 10 || (n >> 20) == 0xac1 || (n >> 16) == 0xc0a8))
                return a.toString();
        }
        return trUtf("请连接 Wi-Fi");
    }

    // 信息卡片里要显示本机全部可用 IPv4（多网卡时一行一个）
    QString localAddresses() const {
        QStringList out;
        QList<QHostAddress> addresses = QNetworkInterface::allAddresses();
        for (int i = 0; i < addresses.size(); ++i) {
            QHostAddress a = addresses.at(i);
            if (a.protocol() != QAbstractSocket::IPv4Protocol) continue;
            // Qt 4.7 没有 QHostAddress::isLoopback，用 SpecialAddress 比较
            if (a == QHostAddress::LocalHost || a == QHostAddress::LocalHostIPv6) continue;
            QString text = a.toString();
            if (!out.contains(text)) out << text;
        }
        return out.isEmpty() ? trUtf("请连接 Wi-Fi") : out.join("\n");
    }

    QString status() const { return state; }
    QString localName() const { return ownName; }
    QString offer() const { return message; }
    bool busy() const { return working; }
    bool listening() const { return receiver.state() != QProcess::NotRunning; }
    bool active() const { return appActive; }
    // 由 app.cpp 的窗口事件过滤器调用：切后台停动画，回前台再开
    Q_INVOKABLE void setActive(bool on) {
        if (appActive == on) return;
        appActive = on;
        emit changed();
    }
    QString folder() const { return dir; }
    QVariantList entries() const { return listing; }
    QVariantList devices() const { return deviceList; }
    QString selected() const { return chosen; }
    QString peer() const { return peerName; }
    QString host() const { return ip; }
    bool connected() const { return !pin.isEmpty(); }
    bool autoSave() const { return automatic; }
    QString receiveDirectory() const { return receive; }
    QString pickerMode() const { return pickMode; }
    QString version() const { return "1.0.3"; }
    QString language() const { return langTag; }
    QString systemLanguage() const { return QLocale::system().name(); }

    // 随机设备名用哪套词库：让默认名字跟界面语言一致
    QString aliasLang() const {
        QString t = langTag;
        if (t.isEmpty() || t == "system") t = QLocale::system().name();
        t.replace("-", "_");
        if (t.startsWith("zh") || t.startsWith("ZH")) {
            if (t.contains("HK") || t.contains("hk") || t.contains("MO") || t.contains("mo")) return "zh_HK";
            if (t.contains("TW") || t.contains("tw") || t.contains("Hant") || t.contains("hant")) return "zh_TW";
            return "zh_CN";
        }
        return "en";
    }

    // glibc 不会主动把释放的堆页还给内核，传完大文件 RSS 会停在峰值。
    // 每次 job / 接收结束调一次 malloc_trim，让空闲页回到系统。
    void trimHeap() {
#if defined(__GLIBC__)
        malloc_trim(0);
#endif
    }

    void applyProbeEnv(QProcess &p) {
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("N9_ALIAS_LANGUAGE", aliasLang());
        env.insert("MAESHARE_TEXT_SEND", sendingTextMode ? "1" : "0");
        p.setProcessEnvironment(env);
    }

    void setLanguage(QString tag) {
        if (tag == langTag) return;
        langTag = tag;
        QSettings("Chih", "MaeShare").setValue("language", tag);
        emit changed();
        // 名字是自动生成的（用户没改过）时，跟着语言重新取一次词库里的名字
        if (!nameCustom && message.isEmpty() && !working) regenerateName();
    }
    int receivedCount() const { return receivedBatch.size(); }
    bool canOpenReceived() const { return receivedOpenable; }

    QString receivedSummary() const {
        return receivedBatch.size() == 1 ? QFileInfo(receivedBatch.first()).fileName()
                                         : trUtf("已接收 %1 个文件").arg(receivedBatch.size());
    }

    // 收到的是单个文本消息时，界面直接把内容显示出来（LocalSend 用 fileType=text 标记
    // 一条文本消息，文件名可能只是个普通名字；老版本只靠 .txt 后缀判断）。
    bool receivedIsText() const {
        if (receivedBatch.size() != 1) return false;
        QFileInfo f(receivedBatch.first());
        if (!f.isFile() || f.size() > 65536) return false;
        if (!receivedType.isEmpty()) {
            QString t = receivedType.toLower();
            if (t == "text" || t == "text/plain") return true;
        }
        return f.suffix().compare("txt", Qt::CaseInsensitive) == 0;
    }

    Q_INVOKABLE QString receivedText() {
        if (!receivedIsText()) return QString();
        QFile f(receivedBatch.first());
        if (!f.open(QIODevice::ReadOnly)) return QString();
        QByteArray data = f.readAll();
        return QString::fromUtf8(data.constData(), data.size());
    }

    // ------------------------------------------------------------- 接收历史
    // 只记「收到过的文件」，存在 QSettings 的 history 键里，
    // 一行一条：<时间戳>\t<字节数>\t<来源标签>\t<路径>。
    QVariantList history() const { return historyList; }

    static QString sizeTextFor(qint64 bytes) {
        if (bytes >= 1048576) return QString::number(bytes / 1048576.0, 'f', 1) + " MB";
        if (bytes >= 1024) return QString::number(bytes / 1024.0, 'f', 1) + " KB";
        return QString::number(bytes) + " B";
    }

    void appendHistory(const QString &path) {
        QFileInfo f(path);
        if (!f.isFile()) return;
        QString sender = lastSender;
        if (sender.isEmpty()) sender = lastSenderIp;
        if (sender.isEmpty()) sender = peerName;
        if (sender.isEmpty()) sender = ip;
        if (sender.isEmpty()) sender = trUtf("未知设备");
        QVariantMap item;
        item["path"] = f.absoluteFilePath();
        item["name"] = f.fileName();
        item["bytes"] = (qint64)f.size();
        item["sizeText"] = sizeTextFor(f.size());
        item["time"] = QDateTime::currentDateTime().toTime_t();
        item["when"] = QDateTime::currentDateTime().toString("yyyy/MM/dd HH:mm");
        item["peer"] = sender;
        // 同一个路径只保留最新一条
        for (int i = historyList.size() - 1; i >= 0; --i) {
            if (historyList.at(i).toMap().value("path").toString() == item["path"].toString())
                historyList.removeAt(i);
        }
        historyList.prepend(item);
        while (historyList.size() > 60) historyList.removeLast();
        saveHistory();
    }

    // 历史存在独立 UTF-8 文本文件里（QSettings 的 INI 转义对含 tab / 中文的行不可靠）
    QString historyFilePath() const {
        return QDir::homePath() + "/.config/Chih/history.txt";
    }

    void saveHistory() {
        QDir().mkpath(QDir::homePath() + "/.config/Chih");
        QFile file(historyFilePath());
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            qDebug() << "HISTORY_SAVE_FAIL";
            return;
        }
        QTextStream out(&file);
        out.setCodec("UTF-8");
        for (int i = 0; i < historyList.size(); ++i) {
            QVariantMap m = historyList.at(i).toMap();
            QString peer = m.value("peer").toString().replace('\t', ' ').replace('\n', ' ');
            QString path = m.value("path").toString().replace('\t', ' ').replace('\n', ' ');
            out << QString::number(m.value("time").toLongLong()) << "\t"
                << QString::number(m.value("bytes").toLongLong()) << "\t"
                << peer << "\t" << path << "\n";
        }
        file.close();
        qDebug() << "HISTORY_SAVED" << historyList.size();
    }

    void loadHistory() {
        historyList.clear();
        QFile file(historyFilePath());
        if (!file.open(QIODevice::ReadOnly)) {
            qDebug() << "HISTORY_NONE";
            return;
        }
        QTextStream in(&file);
        in.setCodec("UTF-8");
        while (!in.atEnd()) {
            QString line = in.readLine();
            if (line.trimmed().isEmpty()) continue;
            QStringList f = line.split("\t");
            if (f.size() < 4) continue;
            QVariantMap item;
            item["path"] = f.at(3);
            item["name"] = QFileInfo(f.at(3)).fileName();
            item["bytes"] = f.at(1).toLongLong();
            item["sizeText"] = sizeTextFor(f.at(1).toLongLong());
            item["time"] = f.at(0).toLongLong();
            item["when"] = QDateTime::fromTime_t(f.at(0).toLongLong()).toString("yyyy/MM/dd HH:mm");
            item["peer"] = f.at(2).isEmpty() ? trUtf("未知设备") : f.at(2);
            historyList.append(item);
            if (historyList.size() >= 60) break;
        }
        file.close();
        qDebug() << "HISTORY_LOADED" << historyList.size();
    }

    QString historyPathAt(int index) const {
        if (index < 0 || index >= historyList.size()) return QString();
        return historyList.at(index).toMap().value("path").toString();
    }

    Q_INVOKABLE void clearHistory() {
        historyList.clear();
        saveHistory();
        emit changed();
    }

    Q_INVOKABLE bool historyIsText(int index) const {
        QString path = historyPathAt(index);
        if (path.isEmpty()) return false;
        QFileInfo f(path);
        return f.isFile() && f.size() <= 65536 && f.suffix().compare("txt", Qt::CaseInsensitive) == 0;
    }

    Q_INVOKABLE QString historyTextAt(int index) {
        QString path = historyPathAt(index);
        if (path.isEmpty()) return QString();
        QFileInfo f(path);
        if (!f.isFile() || f.size() > 65536) return QString();
        if (f.suffix().compare("txt", Qt::CaseInsensitive) != 0) return QString();
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) return QString();
        QByteArray data = file.readAll();
        return QString::fromUtf8(data.constData(), data.size());
    }

    // 点历史条目：文本直接在对话框里看内容，其它类型交给系统查看器
    Q_INVOKABLE void openHistoryFolder(int index) {
        QString path = historyPathAt(index);
        if (path.isEmpty()) { finish(trUtf("文件不存在或无法读取。")); return; }
        pickMode = "received";
        browse(QFileInfo(path).path());
    }

    // 诊断用：不管 release 有没有把 qDebug 编掉，都往 /home/user/maeshare-open.log 落一行
    void logOpen(const QString &m) {
        qDebug() << "OPEN" << m;
        QFile lf("/home/user/maeshare-open.log");
        if (lf.open(QIODevice::WriteOnly | QIODevice::Append)) {
            lf.write(QDateTime::currentDateTime().toString("MM-dd HH:mm:ss ").toUtf8());
            lf.write(m.toUtf8());
            lf.write("\n");
            lf.close();
        }
    }

    // 历史条目直接打开（图片/音视频/PDF 交给系统应用，不再经过目录列表）
    Q_INVOKABLE bool openHistoryFile(int index) {
        QString path = historyPathAt(index);
        logOpen(QString("HIST index=%1 path=%2").arg(index).arg(path));
        if (path.isEmpty()) { finish(trUtf("文件不存在或无法读取。")); return false; }
        return openFile(path);
    }

    bool canOpenFile(QString path) const {
        QFileInfo f(path);
        QString canonical = f.canonicalFilePath();
        return f.isFile() && !f.isSymLink() && f.isReadable() && canonical.startsWith(root + "/");
    }

    // Fremantle 没有 libcontentaction / xdg-open，但系统自带查看器可以直接调起：
    // 图片 → image-viewer，音视频 → mediaplayer，PDF → osso_pdfviewer
    QString viewerFor(const QString &path) const {
        QString suffix = QFileInfo(path).suffix().toLower();
        QStringList img;
        img << "jpg" << "jpeg" << "png" << "gif" << "bmp" << "tif" << "tiff" << "webp" << "svg" << "ico";
        QStringList media;
        media << "mp4" << "avi" << "mkv" << "mov" << "3gp" << "wmv" << "flv" << "mpg" << "mpeg"
              << "m4v" << "ts" << "mp3" << "wav" << "aac" << "m4a" << "ogg" << "flac" << "amr" << "wma";
        QString app;
        if (img.contains(suffix)) app = "/usr/bin/image-viewer";
        else if (media.contains(suffix)) app = "/usr/bin/mediaplayer";
        else if (suffix == "pdf") app = "/usr/bin/osso_pdfviewer";
        if (app.isEmpty() || !QFileInfo(app).isExecutable()) return QString();
        return app;
    }

    // 图片不再交给外部 image-viewer：那是一个独立进程（实测约 30MB，而设备只剩个位数 MB
    // 空闲内存），很容易起不来或起了不切前台。改成用 QML 内置浮层直接显示，零额外进程。
    Q_PROPERTY(QString previewImage READ previewImage NOTIFY changed)
    QString previewImage() const { return previewImagePath; }
    // 解码尺寸必须按原图长宽比算：Qt Quick 1 的 sourceSize 是「强制解码成这个尺寸」，
    // 宽高一齐写死 800x480 会把竖图压扁，之后再 PreserveAspectFit 也救不回来。
    Q_PROPERTY(int previewDecodeWidth READ previewDecodeWidth NOTIFY changed)
    Q_PROPERTY(int previewDecodeHeight READ previewDecodeHeight NOTIFY changed)
    int previewDecodeWidth() const { return previewW > 0 ? previewW : 800; }
    int previewDecodeHeight() const { return previewH > 0 ? previewH : 480; }
    Q_INVOKABLE void closePreview() {
        if (previewImagePath.isEmpty()) return;
        previewImagePath.clear();
        previewW = 0;
        previewH = 0;
        emit changed();
    }

    // 解不了的格式（WebP / HEIC 等）：给一句人话，而不是黑屏
    Q_PROPERTY(QString unsupportedFormat READ unsupportedFormat NOTIFY changed)
    Q_PROPERTY(QString unsupportedPath READ unsupportedPath NOTIFY changed)
    QString unsupportedFormat() const { return unsupportedExt; }
    QString unsupportedPath() const { return unsupportedFilePath; }
    Q_INVOKABLE void closeUnsupported() {
        if (unsupportedExt.isEmpty()) return;
        unsupportedExt.clear();
        unsupportedFilePath.clear();
        emit changed();
    }

    // 文本消息要能真正「复制粘贴」：Qt Quick 1 没有剪贴板 API，走 Qt 这一侧。
    Q_INVOKABLE void copyText(QString text) {
        if (text.isEmpty()) return;
        QApplication::clipboard()->setText(text);
        finish(trUtf("已复制到剪贴板。"));
    }

    Q_INVOKABLE bool openFile(QString path) {
        if (!canOpenFile(path)) {
            logOpen(QString("FAIL not-readable root=%1 path=%2").arg(root).arg(path));
            finish(trUtf("文件不存在或无法读取。"));
            return false;
        }
        QFileInfo fi(path);
        logOpen(QString("TRY path=%1 suffix=%2").arg(fi.absoluteFilePath()).arg(fi.suffix()));

        // 图片：内置浮层显示
        QStringList imgList;
        imgList << "jpg" << "jpeg" << "png" << "gif" << "bmp" << "tif" << "tiff" << "svg" << "ico"
                << "webp" << "heic" << "heif" << "avif";
        if (imgList.contains(fi.suffix().toLower())) {
            // 先问解码器：这台设备的 Qt 只有 jpeg/gif/ico/svg/tiff 插件（png/bmp 内建），
            // 没有 webp、没有 heic —— 硬塞给 Image 只会得到一块黑屏，所以这里先探测再决定。
            QImageReader probe(fi.absoluteFilePath());
            if (!probe.canRead()) {
                unsupportedExt = fi.suffix().toUpper();
                unsupportedFilePath = fi.absoluteFilePath();
                logOpen(QString("UNSUPPORTED format=%1 path=%2").arg(unsupportedExt).arg(unsupportedFilePath));
                emit changed();
                return false;
            }
            previewImagePath = fi.absoluteFilePath();
            // 解码尺寸：等比缩到 800x480 的框内（小图保持原始尺寸，不放大解码）。
            {
                QSize raw = probe.size();
                if (raw.isValid() && raw.width() > 0 && raw.height() > 0) {
                    double scale = qMin(800.0 / raw.width(), 480.0 / raw.height());
                    if (scale > 1.0) scale = 1.0;
                    previewW = qMax(1, int(qRound(raw.width() * scale)));
                    previewH = qMax(1, int(qRound(raw.height() * scale)));
                } else {
                    previewW = 800;
                    previewH = 480;
                }
            }
            logOpen(QString("INLINE image=%1 decode=%2x%3").arg(previewImagePath).arg(previewW).arg(previewH));
            emit changed();
            return true;
        }

        // 真机实测（2026-11-17）：N900 上的 /usr/bin/image-viewer、mediaplayer、osso_pdfviewer
        // 都是指向 maemo-invoker 的符号链接，maemo-invoker 靠 argv[0] 判断要拉起哪个服务。
        // 所以必须用「服务名」调用（/usr/bin/image-viewer），直接调 /usr/bin/maemo-invoker
        // 会立刻退出（实测 rc=1）且什么都不弹。rc 不可靠（invoker 可能驻留等子进程），
        // 因此仍用 startDetached 异步拉起。
        QString app = viewerFor(fi.absoluteFilePath());
        if (app.isEmpty()) {
            logOpen(QString("FAIL no-viewer suffix=%1").arg(fi.suffix()));
            finish(trUtf("没有可打开此类型文件的应用。"));
            return false;
        }
        if (QProcess::startDetached(app, QStringList() << fi.absoluteFilePath())) {
            logOpen(QString("OK via=%1 path=%2").arg(app).arg(fi.absoluteFilePath()));
            finish(trUtf("已用系统查看器打开：") + fi.fileName());
            QTimer::singleShot(3000, this, SLOT(checkViewerAlive()));
            return true;
        }
        logOpen(QString("FAIL start-detached app=%1").arg(app));
        finish(trUtf("无法启动系统查看器。"));
        return false;
    }
    Q_INVOKABLE bool openLastReceived() { return receivedBatch.size() == 1 && openFile(receivedBatch.first()); }

    Q_INVOKABLE void activateEntry(QString path) {
        {   // 临时诊断：记录每一次点击到底有没有到达这里
            QFile log("/home/user/maeshare-tap.log");
            if (log.open(QIODevice::Append)) {
                log.write(QString("%1 dir=%2 mode=%3\n").arg(path)
                          .arg(QFileInfo(path).isDir() ? 1 : 0).arg(pickMode).toUtf8());
                log.close();
            }
        }
        // 目录：把浏览延到事件循环下一轮再做。
        // 直接在 onClicked 里改 model 会在手指按住时销毁整个 delegate，
        // 之后鼠标/触摸抓取丢失，表现为「点文件夹没反应 / 整页卡死」。
        if (QFileInfo(path).isDir()) { browseDeferred(path); return; }
        if (pickMode == "received") openFile(path);
        else toggleSelection(path);
    }

    void browseDeferred(QString path) {
        pendingBrowse = path;
        QMetaObject::invokeMethod(this, "browsePending", Qt::QueuedConnection);
    }

    int selectedCount() const { return selection.size(); }

    QString selectedSummary() const {
        if (selection.isEmpty()) return trUtf("选择要发送的文件");
        if (selection.size() == 1) return QFileInfo(selection.first()).fileName();
        return trUtf("已选择 %1 个文件").arg(selection.size());
    }

    Q_INVOKABLE bool isSelected(QString path) const {
        return selection.contains(path) || selection.contains(QFileInfo(path).canonicalFilePath());
    }

    Q_INVOKABLE void clearSelection() { dropStagedCopies(); selection.clear(); chosen.clear(); sendingTextMode = false; emit changed(); }

    // 相册分享的暂存副本：libsharing 的 outbox 临时件在 send 返回后就被删掉，插件因此先拷一份。
    // 拷贝放在家目录的隐藏目录里（不在 MyDocs，图库索引扫不到），发送结束由客户端删除。
    static QString shareStageDir() { return QDir::homePath() + "/.maeshare-share/"; }
    static QString legacyStageDir() { return QDir::homePath() + "/MyDocs/.maeshare-share/"; }

    bool isStagedPath(const QString &p) const {
        return p.startsWith(shareStageDir()) || p.startsWith(legacyStageDir());
    }

    // 发送成功或取消后调用：删掉本次分享的副本，并把它们从已选内容里摘掉
    void dropStagedCopies() {
        if (stagedShare.isEmpty()) return;
        for (int i = 0; i < stagedShare.size(); ++i) {
            if (QFile::exists(stagedShare.at(i))) QFile::remove(stagedShare.at(i));
            // 插件把每个分享项放在独立子目录里（为了保留原始文件名），空了就一并收掉
            QDir().rmdir(QFileInfo(stagedShare.at(i)).absolutePath());
            selection.removeAll(stagedShare.at(i));
        }
        stagedShare.clear();
        if (selection.isEmpty()) chosen.clear();
        else chosen = selection.first();
        emit changed();
    }

    // 系统相册「分享」进来的文件：不受 picker 根目录限制，直接作为已选内容。
    // 来自 libsharing 插件（/opt/maeshare/maeshare --share <path>...）或单实例转发。
    Q_INVOKABLE void shareFiles(QStringList paths) {
        sendingTextMode = false;
        if (!working) dropStagedCopies();   // 上一次分享没人用掉，先清掉
        selection.clear();
        for (int i = 0; i < paths.size() && selection.size() < 20; ++i) {
            QFileInfo f(paths.at(i));
            if (!f.isFile() || !f.isReadable()) continue;
            QString canonical = f.canonicalFilePath();
            if (canonical.isEmpty()) continue;
            if (!selection.contains(canonical)) selection.append(canonical);
            if (isStagedPath(canonical) && !stagedShare.contains(canonical))
                stagedShare.append(canonical);
        }
        chosen = selection.isEmpty() ? QString() : selection.first();
        emit changed();
        qDebug("SHARE_INTAKE %d/%d", selection.size(), paths.size());
        if (!selection.isEmpty()) emit shareReady();   // 让界面自己跳到发送页
    }

    Q_INVOKABLE void toggleSelection(QString path) {
        sendingTextMode = false;
        QFileInfo f(path);
        if (f.isDir()) { browse(path); return; }
        QString canonical = f.canonicalFilePath();
        if (!canonical.startsWith(root + "/") || f.isSymLink() || !f.isFile() || !f.isReadable()) return;
        if (selection.contains(canonical)) {
            selection.removeAll(canonical);
        } else {
            if (selection.size() >= 20) { finish(trUtf("每次最多选择 20 个文件。")); return; }
            for (int i = 0; i < selection.size(); ++i) {
                if (QFileInfo(selection.at(i)).fileName() == f.fileName()) {
                    finish(trUtf("存在同名文件，请分开传输。"));
                    return;
                }
            }
            selection.append(canonical);
        }
        chosen = selection.isEmpty() ? QString() : selection.first();
        emit changed();
    }

    void setAutoSave(bool enabled) {
        if (enabled == automatic) return;
        if (!canChangeService()) { finish(trUtf("请先完成当前传输。")); return; }
        automatic = enabled;
        QSettings("Chih", "MaeShare").setValue("auto_save", enabled);
        restartService();
        emit changed();
    }

    void setHost(QString s) {
        if (s == ip) return;
        ip = s.trimmed();
        pin.clear();
        peerName = known.value(ip).value("alias").toString();
        peerPort = known.value(ip).value("port", 53317).toInt();
        emit changed();
    }

    Q_INVOKABLE void browse(QString path) {
        QString canonical = QFileInfo(path).canonicalFilePath();
        if (canonical != root && !canonical.startsWith(root + "/")) return;
        dir = canonical;
        listing.clear();
        QDir d(dir);
        QFileInfoList list = d.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Readable, QDir::DirsFirst | QDir::Name);
        for (int i = 0; i < list.size(); ++i) {
            QFileInfo f = list.at(i);
            if (f.isSymLink()) continue;
            if (!f.isDir()) {
                if (pickMode == "folder") continue;
                if (pickMode == "photos") {
                    QString lower = f.suffix().toLower();
                    if (!(lower == "jpg" || lower == "jpeg" || lower == "png" || lower == "gif" || lower == "bmp" || lower == "webp")) continue;
                }
            }
            QVariantMap m;
            m["name"] = f.fileName();
            m["path"] = f.absoluteFilePath();
            m["directory"] = f.isDir();
            m["size"] = f.size();
            listing.append(m);
        }
        emit changed();
    }

    Q_INVOKABLE void up() { if (dir != root) browseDeferred(QFileInfo(dir).path()); }

    Q_INVOKABLE void openReceived() { pickMode = "received"; browse(receive); }

    Q_INVOKABLE void beginPicker(QString mode) {
        pickMode = mode;
        QString target = mode == "folder" ? receive : mode == "photos" ? root + "/DCIM" : root;
        if (!QFileInfo(target).isDir()) target = root;
        browse(target);
    }

    Q_INVOKABLE void setReceiveDirectory(QString path) {
        if (!canChangeService()) { finish(trUtf("请先完成当前传输。")); return; }
        QFileInfo f(path);
        QString canonical = f.canonicalFilePath();
        if (!f.isDir() || f.isSymLink() || (canonical != root && !canonical.startsWith(root + "/")) || !f.isWritable()) {
            finish(trUtf("此目录不可用，请选择手机文件区域内的文件夹。"));
            return;
        }
        receive = canonical;
        QSettings("Chih", "MaeShare").setValue("receive_directory", receive);
        restartService();
        finish(trUtf("保存目录已更新。"));
    }

    Q_INVOKABLE void choose(QString path) {
        if (QFileInfo(path).isDir()) browseDeferred(path);
        else if (!isSelected(path)) toggleSelection(path);
    }

    Q_INVOKABLE void connectPeer() {
        if (working) return;
        QHostAddress a(ip);
        quint32 n = a.toIPv4Address();
        if (a.protocol() != QAbstractSocket::IPv4Protocol || !((n >> 24) == 10 || (n >> 20) == 0xac1 || (n >> 16) == 0xc0a8)) {
            finish(trUtf("请输入局域网 IPv4 地址。"));
            return;
        }
        QSettings("Chih", "MaeShare").setValue("peer_ip", ip);
        run("info", QStringList() << "--info" << identity << ip << QString::number(peerPort));
    }

    // 发送页「手输地址」：直接给地址连过去。已选内容时连上就发（与点设备行一致），
    // 没选内容时只把对方加进设备列表并记住指纹。
    Q_INVOKABLE void connectManual(QString address) {
        if (working) { finish(trUtf("请先完成当前任务。")); return; }
        setHost(address);
        manualAddr = true;
        pendingSend = !selection.isEmpty();
        connectPeer();
    }

    Q_INVOKABLE void selectDevice(int index) {
        if (working || index < 0 || index >= deviceList.size()) return;
        QVariantMap m = deviceList.at(index).toMap();
        if (m.value("protocol").toString() != "https") {
            finish(trUtf("此设备使用未加密传输，请在对方开启加密后重试。"));
            return;
        }
        setHost(m.value("ip").toString());
        manualAddr = false;
        connectPeer();
    }

    // 选好内容后直接点设备：连上就发，不再需要单独的发送键；
    // 没选内容时点设备只建立连接（文本页要靠这个连接发送文本）
    Q_INVOKABLE void sendToDevice(int index) {
        if (working) return;
        pendingSend = !selection.isEmpty();
        selectDevice(index);
    }

    Q_INVOKABLE void send() {
        if (working) return;
        if (pin.isEmpty() || selection.isEmpty()) { finish(trUtf("请先连接设备并选择文件。")); return; }
        QStringList args;
        args << "--send" << identity << ip << QString::number(peerPort) << pin;
        for (int i = 0; i < selection.size(); ++i) args << selection.at(i);
        run("send", args);
    }

    // LocalSend v2 的 FileDto 带 fileType 字段：值 text 表示「一条文本消息」，官方客户端
    // 收到后会渲染成可复制的文本气泡，而不是一个 .txt 附件。旧的实现把 fileType 写死成
    // application/octet-stream，所以对方只看到一个文件。这里通过 probe 环境变量把类型带过去。
    bool stageText(QString text) {
        QString body = text;
        while (body.endsWith("\n") || body.endsWith("\r")) body.chop(1);
        if (body.trimmed().isEmpty()) { finish(trUtf("请先输入内容。")); return false; }
        if (body.length() > 4096) { finish(trUtf("文本过长，请控制在 4096 个字符以内。")); return false; }
        QString dirPath = QDir::homePath() + "/.maeshare-texts";
        if (!QDir().mkpath(dirPath)) { finish(trUtf("无法创建文本目录。")); return false; }
        QString name = "MaeShare-text-" + QDateTime::currentDateTime().toString("yyyyMMdd-hhmmss") + ".txt";
        QString path = dirPath + "/" + name;
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly)) { finish(trUtf("文本保存失败。")); return false; }
        QByteArray bytes = body.toUtf8();
        bytes.append('\n');
        if (f.write(bytes) != bytes.size()) {
            f.close();
            finish(trUtf("文本保存失败。"));
            return false;
        }
        f.close();
        selection.clear();
        selection.append(path);
        chosen = path;
        sendingTextMode = true;
        emit changed();
        return true;
    }

    // 旧的「先连设备再点发送」入口，保留给历史调用
    Q_INVOKABLE void sendText(QString text) {
        if (working) return;
        if (pin.isEmpty()) { finish(trUtf("请先在发送页选择设备")); return; }
        if (!stageText(text)) return;
        send();
    }

    // 文本页：写完文本直接点设备就发，不再要求先连接，也没有单独的发送键
    Q_INVOKABLE void sendTextToDevice(int index, QString text) {
        if (working) return;
        if (!stageText(text)) return;
        sendToDevice(index);
    }

    Q_INVOKABLE void startReceive() {
        if (listening() || working) return;
        receiverBuffer.clear();
        receiverFailure.clear();
        stopping = false;
        QStringList args;
        args << "--serve" << identity << receive << "lan" << (automatic ? "autosave" : "consent");
        applyProbeEnv(receiver);
        receiver.start(helper, args);
        state = trUtf("正在发现附近设备…");
        emit changed();
    }

    Q_INVOKABLE void stopReceive() {
        stopping = true;
        receiver.kill();
        receiver.waitForFinished(1000);
        decisionTimer.stop();
        receiving = false;
        message.clear();
        state = trUtf("接收与设备发现已关闭。");
        emit changed();
    }

    Q_INVOKABLE void scan() {
        if (working || !message.isEmpty()) return;
        stopReceive();
        startReceive();
    }

    Q_INVOKABLE void regenerateName() {
        if (working || !message.isEmpty()) return;
        nameCustom = false;
        QSettings("Chih", "MaeShare").setValue("name_custom", false);
        stopReceive();
        run("identity", QStringList() << "--new-name" << identity);
    }

    Q_INVOKABLE void setLocalName(QString name) {
        if (!canChangeService()) { finish(trUtf("请先完成当前传输。")); return; }
        name = name.trimmed().left(50);
        if (name.isEmpty()) { finish(trUtf("设备名称不能为空。")); return; }
        for (int i = 0; i < name.size(); ++i) {
            if (name.at(i).unicode() < 32 || name.at(i).unicode() == 127) return;
        }
        QFile f(identity + "/alias.txt");
        if (!f.open(QIODevice::WriteOnly) || f.write(name.toUtf8()) != name.toUtf8().size()) {
            finish(trUtf("设备名称保存失败。"));
            return;
        }
        f.close();
        f.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
        ownName = name;
        nameCustom = true;
        QSettings("Chih", "MaeShare").setValue("name_custom", true);
        restartService();
        finish(trUtf("设备名称已保存。"));
    }

    // 键盘输入在 N900 上不稳定（SCIM 面板不一定弹），给界面一个「粘贴」入口：
    // 剪贴板是 X 级共享的，从 Notes/对话里复制中文过来就能直接用。
    Q_INVOKABLE QString clipboardText() {
        return QApplication::clipboard()->text().left(4000);
    }

    Q_INVOKABLE void answer(bool accept) {
        if (message.isEmpty()) return;
        decisionTimer.stop();
        receiver.write(accept ? "accept\n" : "reject\n");
        receiving = accept;
        message.clear();
        state = accept ? trUtf("正在接收…") : trUtf("已拒绝接收。");
        emit changed();
    }

    Q_INVOKABLE void cancel() { if (working) { canceled = true; job.kill(); } }

    // 诊断用（--open）：先把路径存下来，等事件循环跑起来再调 openFile
    void setPendingOpen(const QString &p) { pendingOpen = p; }

public slots:
    void openPendingFile() { if (!pendingOpen.isEmpty()) openFile(pendingOpen); }

    // activateEntry / up 的延迟执行体（见 browseDeferred 的注释）
    void browsePending() {
        if (pendingBrowse.isEmpty()) return;
        QString p = pendingBrowse;
        pendingBrowse.clear();
        browse(p);
    }

    // 拉起查看器 3 秒后看一眼：进程在不在、内存还剩多少
    void checkViewerAlive() {
        QProcess p;
        p.start("/bin/sh", QStringList() << "-c"
                << "ps -o pid,stat,rss,args | grep -E 'image-viewer|mediaplayer|osso_pdfviewer' | grep -v grep; echo MEM; grep -E 'MemFree|MemAvailable' /proc/meminfo");
        p.waitForFinished(5000);
        logOpen(QString("PROCS %1").arg(QString::fromUtf8(p.readAllStandardOutput()).trimmed().replace("\n", " | ")));
    }

signals:
    void changed();
    void shareReady();          // 相册分享送来了文件：界面应当切到发送页并列出它们
    void messageArrived();      // 收到一条文本消息，接收页据此把内容直接弹出来
    void feedback(QString text);
    void receiveCompleted();

private slots:
    void initialize() {
        bool firstRun = !QFileInfo(identity + "/identity-key.pem").exists();
        run("identity", QStringList() << "--identity" << identity);
        if (firstRun) { state = trUtf("首次启动：正在生成安全密钥，请稍候…"); emit changed(); }
    }

    void rejectExpired() {
        answer(false);
        finish(trUtf("接收确认已超时，请重新发送。"));
    }

    void expirePeers() {
        uint now = QDateTime::currentDateTime().toTime_t();
        QStringList keys = known.keys();
        for (int i = 0; i < keys.size(); ++i) {
            if (known.value(keys.at(i)).value("manual").toBool()) continue;
            if (now - known.value(keys.at(i)).value("lastSeen").toUInt() > 75) known.remove(keys.at(i));
        }
        refreshList();
    }

    void readJob() {
        jobOutput += job.readAll();
        if (jobOutput.size() > 1048576) job.kill();
    }

    void jobError(QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) { working = false; finish(trUtf("无法启动传输组件，请重新打开应用。")); }
    }

    void receiverError(QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) finish(trUtf("无法启动接收组件。"));
    }

    void jobEnded(int code, QProcess::ExitStatus exit) {
        readJob();
        working = false;
        setAwake(false);   // 本次 job 结束；若是 info 后自动接 send()，send() 里会重新续期
        trimHeap();        // 大文件发送时堆上会留不少空洞，结束后还给系统
        if (canceled) { pendingSend = false; if (operation == "send") dropStagedCopies(); finish(trUtf("已取消发送。")); return; }
        if (code || exit != QProcess::NormalExit) { pendingSend = false; finish(failureText()); return; }

        if (operation == "identity" || operation == "info") {
            bool ok = false;
            QVariantMap data = QJson::Parser().parse(jobOutput, &ok).toMap();
            if (!ok) { finish(trUtf("设备信息无法识别，请重试。")); return; }
            if (operation == "identity") {
                QString alias = data.value("alias").toString();
                if (!alias.isEmpty()) ownName = alias;
                startReceive();
                emit changed();
                return;
            }
            if (data.value("status").toInt() != 200) { finish(trUtf("连接失败，对方响应异常。")); return; }
            pin = data.value("certificateFingerprint").toString();
            QVariantMap info = data.value("info").toMap();
            if (info.value("alias").toString().trimmed().isEmpty())
                info["alias"] = known.value(ip).value("alias", trUtf("未命名设备"));
            remember(info, ip);
            if (pendingSend) {
                pendingSend = false;
                if (!selection.isEmpty()) { send(); return; }
            }
            finish(trUtf("已连接：") + peerName);
            return;
        }
        if (operation == "send") dropStagedCopies();   // 发完就删掉相册分享留下的一份副本
        finish(trUtf("发送完成。"));
    }

    void receiverEnded() {
        receiving = false;
        setAwake(false);
        decisionTimer.stop();
        message.clear();
        if (!stopping) {
            if (receiverFailure.isEmpty()) finish(trUtf("接收服务已停止，请重新开启。"));
            else { QString f = receiverFailure; receiverFailure.clear(); finish(f); }
        }
        emit changed();
    }

    void readReceiver() {
        receiverBuffer += receiver.readAll();
        int at;
        while ((at = receiverBuffer.indexOf('\n')) >= 0) {
            QByteArray line = receiverBuffer.left(at);
            receiverBuffer.remove(0, at + 1);

            if (line.startsWith("PEER ")) {
                bool ok = false;
                QVariantMap m = QJson::Parser().parse(line.mid(5), &ok).toMap();
                if (ok) remember(m, m.value("ip").toString());
            } else if (line.startsWith("OFFER ")) {
                setAwake(true);   // 用户要在这个确认框里做决定，别让屏幕先灭了
                bool ok = false;
                QVariantMap m = QJson::Parser().parse(line.mid(6), &ok).toMap();
                if (ok) {
                    decisionTimer.start();
                    QStringList names;
                    QVariantList list = m.value("names").toList();
                    for (int i = 0; i < list.size(); ++i) names << list.at(i).toString();
                    message = trUtf("来自 ") + m.value("sender").toString() + "\n\n" + names.join("\n") + "\n\n"
                            + QString::number(m.value("bytes").toLongLong()) + trUtf(" 字节");
                }
            } else if (line.startsWith("SENDER ")) {
                // 接收方只有 autosave 模式时 probe 不输出 OFFER，用这个事件补上来源
                setAwake(true);   // 对端开始推文件：从现在起保持 WLAN 处于活跃状态
                bool ok = false;
                QVariantMap m = QJson::Parser().parse(line.mid(7), &ok).toMap();
                if (ok) {
                    QString alias = m.value("sender").toString().trimmed().left(100);
                    if (!alias.isEmpty()) lastSender = alias;
                    QString addr = m.value("ip").toString();
                    if (!addr.isEmpty()) lastSenderIp = addr;
                }
            } else if (line.startsWith("READY")) {
                state = trUtf("已就绪，正在发现附近设备。");
            } else if (line.startsWith("FILE_RECEIVED ")) {
                bool ok = false;
                QVariantMap data = QJson::Parser().parse(line.mid(14), &ok).toMap();
                QFileInfo f(data.value("path").toString());
                QString path = f.canonicalFilePath();
                if (ok && f.isFile() && !f.isSymLink() && path.startsWith(root + "/") && !receivedBatch.contains(path)) {
                    receivedBatch.append(path);
                    receivedType = data.value("type").toString();
                }
            } else if (line.startsWith("RECEIVE_OK")) {
                receiving = false;
                setAwake(false);   // 一整套接收结束，放开唤醒锁（MCE 30 秒内自然恢复）
                trimHeap();        // 接收大文件后把堆上空洞还给系统
                // 对方发的是文本消息（LocalSend 用 fileType=text 表示一条消息）：
                // 不该在 MyDocs 里留一个 .txt 文件，挪进应用私有目录，界面直接按消息展示。
                if (receivedBatch.size() == 1 && receivedIsText()) {
                    QString from = receivedBatch.first();
                    QString box = QDir::homePath() + "/.maeshare-texts";
                    QDir().mkpath(box);
                    QString to = box + "/msg-" + QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss") + ".txt";
                    if (QFile::rename(from, to)) receivedBatch[0] = to;
                }
                receivedOpenable = false;
                for (int i = 0; i < receivedBatch.size(); ++i) {
                    if (receivedIsText()) continue;   // 文本消息不当作文件记进历史
                    appendHistory(receivedBatch.at(i));
                }
                if (receivedIsText()) {
                    finish(trUtf("收到一条文本消息。"));
                    emit messageArrived();
                } else {
                    finish(trUtf("接收完成，已保存到 ") + trUtf("文件") + receive.mid(root.size()) + trUtf("。"));
                }
                if (!receivedBatch.isEmpty()) emit receiveCompleted();
            } else if (line.startsWith("RECEIVE_FAILED")) {
                receiving = false;
                setAwake(false);
                finish(trUtf("接收失败，未保存不完整文件，请重试。"));
            } else if (line.startsWith("PREPARE_ACCEPTED")) {
                receivedBatch.clear();
                receivedType.clear();
                receivedOpenable = false;
                receiving = true;
                state = trUtf("正在接收…");
            } else if (line.startsWith("RECEIVE_NO_SPACE")) {
                finish(trUtf("存储空间不足，请更改保存目录或释放空间。"));
            } else if (line.startsWith("RECEIVE_CANCELED")) {
                receiving = false;
                finish(trUtf("对方已取消发送。"));
            } else if (line.contains("PROBE_ERROR")) {
                receiverFailure = trUtf("无法开启接收：端口 53317 可能已被占用。");
            } else if (line.startsWith("CONNECTION_ERROR") && receiving) {
                receiving = false;
                finish(trUtf("接收中断，请检查网络后重试。"));
            }
            emit changed();
        }
        if (receiverBuffer.size() > 1048576) receiverBuffer.clear();
    }
};
#endif
