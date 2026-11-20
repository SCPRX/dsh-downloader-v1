import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00FFCC), brightness: Brightness.dark)),
      home: const Material(
        color: Color(0xFF03060A),
        child: AppRoot(),
      ),
    );
  }
}

class _SwitchRequested implements Exception {}

class ChatSession {
  final String id;
  String title;
  final List<ChatMsg> msgs;
  ChatSession(this.id, this.title, this.msgs);
}

class ChatMsg {
  final String text;
  final bool mine;
  final int kind;
  final int ts;
  ChatMsg(this.text, this.mine, {this.kind = 0, int? ts})
      : ts = ts ?? DateTime.now().millisecondsSinceEpoch;
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with SingleTickerProviderStateMixin {
  static const MethodChannel _ch = MethodChannel('com.dsh.dshapp/status');

  String _phase = 'env';

  String _status = "正在检查环境...";
  bool _failed = false;
  double _progress = 0.0;

  static const List<String> _envUrls = [
    'https://ghfast.top/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/apk.zip',
    'https://gh-proxy.com/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/apk.zip',
    'https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/apk.zip',
  ];
  static const List<String> _envNames = ['高速镜像', '极速镜像', '官方源'];

  static const int _envSize = 207615322;
  int _runId = 0;
  bool _downloading = false;
  String _speed = "";
  String _curName = "";
  final Map<int, String> _srcInfo = {};
  final Map<int, double> _srcBps = {};
  DateTime _lastProgressPaint = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _keepAliveTimer;
  Timer? _startupTimer;
  String _keepAliveText = "正在准备环境，请勿清理后台…";


  static const List<String> _models = ['deepseek-flash', 'deepseek-v4-pro'];
  bool _testing = false;
  String _testResult = "";
  String _engineLog = "";
  bool _showKey = false;
  double _textScale = 1.0;
  String _lastSessionId = "";
  String _balance = "";
  bool _balanceLoading = false;
  String _nativeFailMsg = "";

  String _apiKey = "";
  String _model = "deepseek-flash";
  String _appDir = "";
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _modelCtrl =
      TextEditingController(text: "deepseek-flash");

  int _rpcId = 0;
  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  String _sessionId = "";
  bool _rpcReady = false;

  List<ChatMsg> _msgs = [];
  final List<ChatSession> _sessions = [];
  String _sessionKey = "";
  String _sessionQuery = "";
  String _fsPath = "/root";
  List<FileSystemEntity> _fsEntries = [];
  bool _fsLoading = false;
  bool _msgsLoaded = false;
  String _streamText = "";
  bool _sending = false;
  bool _chunkSeen = false;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  WebViewController? _web;
  String _engineUrl = "http://127.0.0.1:3090";

  late AnimationController _bgController;
  final math.Random _random = math.Random();
  List<StarParticle> _stars = [];
  List<CloudParticle> _clouds = [];

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 16))
      ..repeat();
    _bgController.addListener(_updateParticles);
    for (int i = 0; i < 6; i++) {
      _clouds.add(_spawnCloud());
    }
    for (int i = 0; i < 60; i++) {
      _stars.add(_spawnStar());
    }

    _ch.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'updateStatus':
          setState(() => _status = call.arguments as String);
          break;
        case 'failed':
          _nativeFailMsg = call.arguments as String;
          setState(() {
            _failed = true;
            _status = call.arguments as String;
          });
          if (_phase == "chat") {
            setState(() {
              _msgs.add(ChatMsg(call.arguments as String, false));
            });
            _scrollToEnd();
          }
          _stopKeepAliveLoop();
          unawaited(_keepAlive(false));
          break;
        case 'envReady':
          _afterEnvReady();
          break;
        case 'rpcLine':
          _onRpcLine(call.arguments as String);
          break;
        case 'webReady':
          final arg = call.arguments;
          final url =
              (arg is String && arg.isNotEmpty) ? arg : "http://127.0.0.1:3090";
          _openWeb(url);
          break;
        case 'log':
          break;
      }
    });
    _bootstrap();
  }

  CloudParticle _spawnCloud() => CloudParticle(
        x: _random.nextBool() ? -0.6 : 1.6,
        y: _random.nextDouble() * 0.8 + 0.1,
        radius: 0.25 + _random.nextDouble() * 0.2,
        opacity: 0.15 + _random.nextDouble() * 0.15,
        vx: (_random.nextBool() ? 1 : -1) *
            (0.0005 + _random.nextDouble() * 0.0005),
      );

  StarParticle _spawnStar() => StarParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        radius: 0.5 + _random.nextDouble() * 1.2,
        maxLife: 100 + _random.nextDouble() * 200,
        life: 0,
      );

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (int i = _stars.length - 1; i >= 0; i--) {
        var star = _stars[i];
        star.life += 1;
        if (star.life > star.maxLife) {
          _stars[i] = _spawnStar();
        }
      }
      for (int i = _clouds.length - 1; i >= 0; i--) {
        var cloud = _clouds[i];
        cloud.x += cloud.vx;
        if (cloud.x < -1.0 || cloud.x > 2.0) {
          _clouds[i] = _spawnCloud();
        }
      }
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _keepAliveTimer?.cancel();
    _startupTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _phase = "chat";
      _failed = false;
      _status = "正在检查环境…";
    });
    try {
      _appDir = (await _ch.invokeMethod<String>('filesDirPath')) ?? "";
      await _loadSettings();
      await _loadSessions();
      if (_apiKey.isNotEmpty) unawaited(_fetchBalance());
      if (_apiKey.isEmpty) {
        setState(() {
          _phase = "chat";
          _failed = false;
          _status = "还没配置 API Key，点右上角⚙设置填写";
        });
      }
      final bool installed = await _ch.invokeMethod<bool>('checkEnv') ?? false;
      if (installed) {
        unawaited(_startEngine());
        return;
      }
      final bool bundled = await _ch.invokeMethod<bool>('hasBundledEnv') ?? false;
      if (bundled) {
        setState(() => _status = "正在安装内置环境…");
        _startKeepAliveLoop(text: "正在安装内置环境，请勿清理后台…");
        await _ch.invokeMethod('installBundledEnv');
        return;
      }
      await _downloadEnv();
    } catch (e) {
      _downloading = false;
      _stopKeepAliveLoop();
      unawaited(_keepAlive(false));
      setState(() {
        _failed = true;
        _status = "启动失败: $e";
      });
      if (_phase == "chat") {
        _msgs.add(ChatMsg("启动失败: $e", false));
        _scrollToEnd();
      }
    }
  }  Future<void> _applyHarnessPatches() async {
    final base =
        "$_appDir/dsh-env/rootfs/opt/dsh/node_modules/@deepseek-ai/";
    const repo =
        'https://raw.githubusercontent.com/SCPRX/dsh-downloader-v1/main/patches/';
    const mirror =
        'https://ghfast.top/https://raw.githubusercontent.com/SCPRX/dsh-downloader-v1/main/patches/';
    final jobs = <List<String>>[
      [
        'dsh-session-persistence-jsonl__index.js',
        "${base}dsh-session-persistence-jsonl/lib/index.js"
      ],
      [
        'dsh-attachment-local__index.js',
        "${base}dsh-attachment-local/lib/index.js"
      ],
    ];
    for (final job in jobs) {
      List<int>? bytes;
      final cache = File("$_appDir/harness_patches/${job[0]}");
      try {
        if (await cache.exists() && await cache.length() > 1000) {
          bytes = await cache.readAsBytes();
        } else {
          for (final u in [repo + job[0], mirror + job[0]]) {
            try {
              final r = await http
                  .get(Uri.parse(u))
                  .timeout(const Duration(seconds: 30));
              if (r.statusCode == 200 && r.bodyBytes.length > 1000) {
                bytes = r.bodyBytes;
                await cache.parent.create(recursive: true);
                await cache.writeAsBytes(bytes);
                break;
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
      if (bytes == null) continue;
      try {
        final f = File(job[1]);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes, flush: true);
      } catch (_) {}
    }
  }

  Future<void> _afterEnvReady() async {
    if (!mounted) return;
    await _applyHarnessPatches();
    if (_apiKey.isEmpty) {
      setState(() {
        _phase = "chat";
        _failed = false;
        _status = "还没配置 API Key，点右上角⚙设置填写";
      });
      return;
    }
    final bool alive = await _ch.invokeMethod<bool>('engineAlive') ?? false;
    if (alive) {
      final bool ready = await _ch.invokeMethod<bool>('engineReady') ?? false;
      if (ready) {
        _rpcReady = true;
        if (_sessionId.isEmpty) {
          _sessionId = _sessionKey.isEmpty
          ? 's${DateTime.now().millisecondsSinceEpoch}'
          : _sessionKey;
        }
        _startKeepAliveLoop(text: "落锤 运行中 · 可切到后台");
        setState(() {
          _phase = "chat";
          _failed = false;
          _status = "";
        });
        return;
      }
      try {
        await _ch.invokeMethod('killEngine');
      } catch (_) {}
    }
    await _startEngine();
  }

  File get _settingsFile => File("$_appDir/native_chat_settings.json");

  Future<void> _loadSettings() async {
    try {
      if (await _settingsFile.exists()) {
        final m = jsonDecode(await _settingsFile.readAsString());
        if (m is Map) {
          _apiKey = (m['apiKey'] ?? "").toString();
          _model = (m['model'] ?? "deepseek-flash").toString();
          _textScale = (m['textScale'] as num?)?.toDouble() ?? 1.0;
          _lastSessionId = (m['sessionKey'] ?? "").toString();
        }
      }
    } catch (_) {}
    _keyCtrl.text = _apiKey;
    _modelCtrl.text = _model;
  }

  Future<void> _saveSettings() async {
    try {
      await _settingsFile.writeAsString(jsonEncode({
        'apiKey': _apiKey,
        'model': _model,
        'textScale': _textScale,
        'sessionKey': _sessionKey,
      }));
    } catch (_) {}
  }

  File get _msgsFile => File("$_appDir/native_chat_messages.json");

  File get _sessionsFile => File("$_appDir/native_chat_sessions.json");

  String _newId() => 's${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _loadSessions() async {
    if (_msgsLoaded) return;
    _msgsLoaded = true;
    try {
      if (await _sessionsFile.exists()) {
        final list = jsonDecode(await _sessionsFile.readAsString());
        if (list is List) {
          for (final item in list) {
            if (item is! Map) continue;
            final msgs = <ChatMsg>[];
            final raw = item['msgs'];
            if (raw is List) {
              for (final m in raw) {
                if (m is Map) {
                  msgs.add(ChatMsg((m['t'] ?? "").toString(), m['m'] == true,
                      kind: (m['k'] as num?)?.toInt() ?? 0,
                      ts: (m['ts'] as num?)?.toInt()));
                }
              }
            }
            _sessions.add(ChatSession(
              (item['id'] ?? _newId()).toString(),
              (item['title'] ?? "新对话").toString(),
              msgs,
            ));
          }
        }
      }
      if (_sessions.isEmpty && await _msgsFile.exists()) {
        final list = jsonDecode(await _msgsFile.readAsString());
        if (list is List) {
          final msgs = <ChatMsg>[];
          for (final m in list) {
            if (m is Map) {
              msgs.add(ChatMsg((m['t'] ?? "").toString(), m['m'] == true,
                      kind: (m['k'] as num?)?.toInt() ?? 0,
                      ts: (m['ts'] as num?)?.toInt()));
            }
          }
          _sessions.add(ChatSession(_newId(), "历史对话", msgs));
        }
      }
    } catch (_) {}
    if (_sessions.isEmpty) {
      _sessions.add(ChatSession(_newId(), "新对话", <ChatMsg>[]));
    }
    ChatSession pick = _sessions.first;
    if (_lastSessionId.isNotEmpty) {
      for (final s in _sessions) {
        if (s.id == _lastSessionId) {
          pick = s;
          break;
        }
      }
    }
    _sessionKey = pick.id;
    _msgs = pick.msgs;
    if (_msgs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _saveSessions() {
    try {
      final list = [
        for (final s in _sessions)
          {
            'id': s.id,
            'title': s.title,
            'msgs': [
              for (final m in s.msgs)
                {'t': m.text, 'm': m.mine, 'k': m.kind, 'ts': m.ts}
            ],
          }
      ];
      unawaited(_sessionsFile.writeAsString(jsonEncode(list)));
    } catch (_) {}
  }

  void _saveMsgs() => _saveSessions();

  void _switchSession(String id) {
    setState(() {
      _sessionKey = id;
      for (final s in _sessions) {
        if (s.id == id) {
          _msgs = s.msgs;
          break;
        }
      }
      _sessionId = id;
      _sending = false;
      _streamText = "";
      _chunkSeen = false;
    });
    _saveSessions();
    unawaited(_saveSettings());
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _newChat() {
    setState(() {
      final s = ChatSession(_newId(), "新对话", <ChatMsg>[]);
      _sessions.insert(0, s);
      _sessionKey = s.id;
      _msgs = s.msgs;
      _sessionId = s.id;
      _streamText = "";
      _sending = false;
      _chunkSeen = false;
    });
    _saveSessions();
  }

  void _deleteSession(String id) {
    setState(() {
      _sessions.removeWhere((s) => s.id == id);
      if (_sessions.isEmpty) {
        _sessions.add(ChatSession(_newId(), "新对话", <ChatMsg>[]));
      }
      if (_sessionKey == id) {
        _sessionKey = _sessions.first.id;
        _msgs = _sessions.first.msgs;
      }
    });
    _saveSessions();
  }

  Future<void> _downloadEnv() async {
    final String? zipPath = await _ch.invokeMethod<String>('envZipPath');
    if (zipPath == null || zipPath.isEmpty) throw '拿不到安装包路径';
    while (true) {
      try {
        await _download(zipPath);
        break;
      } on _SwitchRequested {
        continue;
      }
    }
    _startKeepAliveLoop(text: "正在解压环境，请勿清理后台…");
    setState(() {
      _progress = 1.0;
      _status = "下载完成，正在解压(耗时较长)...";
    });
    await _ch.invokeMethod('startExtract', {'path': zipPath});
  }

  Future<void> _download(String zipPath) async {
    final zip = File(zipPath);
    final part = File('$zipPath.part');

    if (await zip.exists() && await zip.length() > 1024) {
      final head = await zip.openRead(0, 2).first;
      if (head.length == 2 && head[0] == 0x50 && head[1] == 0x4B) {
        setState(() => _progress = 1.0);
        return;
      }
      await zip.delete();
    }

    int start = await part.exists() ? await part.length() : 0;
    if (start >= _envSize) {
      await part.delete();
      start = 0;
    }

    setState(() {
      _status = start > 0
          ? "继续下载核心环境（已有 ${_mb(start)}）..."
          : "首次启动，正在下载核心环境(约 198MB)...";
    });

    _startKeepAliveLoop(text: "正在下载环境，请勿清理后台…");

    final runId = _runId;
    _downloading = true;
    if (_srcBps.isEmpty) await _testSources();
    final order = <int>[for (int i = 0; i < _envUrls.length; i++) i]
      ..sort((a, b) => (_srcBps[b] ?? -1).compareTo(_srcBps[a] ?? -1));

    Object? lastError;
    try {
      for (final i in order) {
        if (runId != _runId) throw _SwitchRequested();
        setState(() {
          _speed = "";
          _curName = _envNames[i];
        });
        try {
          await _downloadFrom(i, runId, part, start: start);
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          if (await part.exists()) start = await part.length();
          final next = order.indexOf(i) + 1;
          if (next < order.length && mounted) {
            setState(() => _status =
                "${_envNames[i]} 不行，换 ${_envNames[order[next]]}...");
          }
        }
      }
      if (lastError != null) throw lastError;

      final bool partOk = await part.exists() && await part.length() == _envSize;
      if (!partOk) {
        if (await part.exists()) await part.delete();
        throw '下载的文件大小不对（可能是镜像的旧文件），已删除，请重试';
      }
      final head = await part.openRead(0, 2).first;
      if (head.length < 2 || head[0] != 0x50 || head[1] != 0x4B) {
        await part.delete();
        throw '下载到的不是 zip 文件，已删除，请重试';
      }
      if (await zip.exists()) await zip.delete();
      await part.rename(zip.path);
    } finally {
      _downloading = false;
    }
  }

  Future<void> _downloadFrom(int index, int runId, File part,
      {required int start}) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(_envUrls[index]));
      if (start > 0) req.headers['range'] = 'bytes=$start-';
      final resp = await client.send(req).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 416 && start > 0) return;
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw 'HTTP ${resp.statusCode}';
      }
      if (resp.statusCode == 200) {
        final len = resp.contentLength;
        if (len != null && len > 0 && len != _envSize) {
          throw '这个源上是旧文件';
        }
      }
      int totalBytes = 0;
      IOSink sink;
      int received = start;
      if (resp.statusCode == 206) {
        totalBytes = _totalFromRange(resp.headers['content-range']) ??
            (resp.contentLength ?? 0) + start;
        if (totalBytes != _envSize) throw '这个源上是旧文件';
        sink = part.openWrite(mode: FileMode.append);
      } else {
        received = 0;
        totalBytes = resp.contentLength ?? 0;
        sink = part.openWrite(mode: FileMode.write);
      }
      final done = Completer<void>();
      final sw = Stopwatch()..start();
      late final StreamSubscription<List<int>> sub;
      sub = resp.stream.listen(
        (chunk) {
          if (runId != _runId) {
            sub.cancel();
            if (!done.isCompleted) done.completeError(_SwitchRequested());
            return;
          }
          sink.add(chunk);
          received += chunk.length;
          final ms = sw.elapsedMilliseconds;
          final bps = ms > 1000 ? received * 1000 ~/ ms : 0;
          final now = DateTime.now();
          if (totalBytes > 0 &&
              now.difference(_lastProgressPaint).inMilliseconds > 250 &&
              mounted) {
            _lastProgressPaint = now;
            setState(() {
              _progress = (received / totalBytes).clamp(0.0, 1.0).toDouble();
              _speed = _speedText(bps);
              _curName = _envNames[index];
              _status = "下载中 ${_mb(received)} / ${_mb(totalBytes)}";
            });
          }
          if (ms > 20000 && bps < 50 * 1024 && !done.isCompleted) {
            sub.cancel();
            done.completeError('该源太慢');
          }
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      try {
        await done.future;
      } finally {
        await sub.cancel();
        await sink.close();
      }
      if (totalBytes > 0 && received < totalBytes) throw '下载不完整';
    } finally {
      client.close();
    }
  }

  int? _totalFromRange(String? contentRange) {
    if (contentRange == null) return null;
    final i = contentRange.lastIndexOf('/');
    if (i < 0) return null;
    return int.tryParse(contentRange.substring(i + 1));
  }

  String _mb(int bytes) => "${(bytes / 1024 / 1024).toStringAsFixed(0)} MB";
  String _speedText(int bps) {
    if (bps <= 0) return "";
    if (bps >= 1024 * 1024) {
      return "${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s";
    }
    return "${(bps / 1024).toStringAsFixed(0)} KB/s";
  }

  Future<void> _testSources() async {
    final jobs = <Future<void>>[];
    for (int i = 0; i < _envUrls.length; i++) {
      if (mounted) setState(() => _srcInfo[i] = "测试中...");
      jobs.add(_probeSource(i).then((res) {
        if (mounted) setState(() => _srcInfo[i] = res);
      }));
    }
    await Future.wait(jobs);
  }

  Future<String> _probeSource(int i) async {
    final client = http.Client();
    try {
      final sw = Stopwatch()..start();
      final req = http.Request('GET', Uri.parse(_envUrls[i]));
      req.headers['range'] = 'bytes=0-524287';
      final resp = await client.send(req).timeout(const Duration(seconds: 8));
      int got = 0;
      try {
        await for (final chunk
            in resp.stream.timeout(const Duration(seconds: 8))) {
          got += chunk.length;
          if (got >= 524288) break;
        }
      } catch (_) {}
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        _srcBps[i] = -1;
        return "失败";
      }
      if (got < 32768) {
        _srcBps[i] = -1;
        return "连不上";
      }
      final bps = got * 1000 ~/ math.max(sw.elapsedMilliseconds, 1);
      _srcBps[i] = bps.toDouble();
      return "≈${_speedText(bps)}";
    } catch (_) {
      _srcBps[i] = -1;
      return "连不上";
    } finally {
      client.close();
    }
  }  Future<void> _keepAlive(bool on) async {
    try {
      await _ch.invokeMethod('keepAlive', {
        'on': on,
        'text': _keepAliveText,
      });
    } catch (_) {}
  }

  void _startKeepAliveLoop({String? text}) {
    if (text != null) _keepAliveText = text;
    _keepAliveTimer?.cancel();
    unawaited(_keepAlive(true));
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_keepAlive(true));
    });
  }

  void _stopKeepAliveLoop() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<void> _startEngine() async {
    setState(() {
      if (_phase != "chat") _phase = "starting";
      _failed = false;
      _status = "正在启动引擎…";
    });
    _nativeFailMsg = "";
    _startKeepAliveLoop(text: "引擎启动中，请稍候…");

    var secs = 0;
    _startupTimer?.cancel();
    _startupTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _phase != "starting") return;
      secs++;
      setState(() {
        _status = "正在启动引擎… ${secs} 秒";
      });
    });
    try {
      await _ch.invokeMethod('startSdk', {
        'apiKey': _apiKey,
        'model': _model,
      });

      final res = await _rpc('initialize', {
        'cwd': '/root',
        'provider': 'deepseek-official',
        'model': _model,
        'approvalRequests': true,
      }, timeout: const Duration(minutes: 15));
      if (res == null) throw '引擎没有响应';
      _rpcReady = true;
      _sessionId = 's${DateTime.now().millisecondsSinceEpoch}';
      try {
        await _ch.invokeMethod('setEngineReady', {'ready': true});
      } catch (_) {}
      _startupTimer?.cancel();

      _startKeepAliveLoop(text: "落锤 运行中 · 可切到后台");
      setState(() {
        _phase = "chat";
        _failed = false;
        _status = "";
      });
    } catch (e) {
      _startupTimer?.cancel();
      final msg = "引擎启动失败: $e" +
          (_nativeFailMsg.isEmpty ? "" : "\n原生: $_nativeFailMsg");
      if (_phase == "chat") {
        setState(() {
          _failed = true;
          _status = msg;
        });
        _msgs.add(ChatMsg(msg, false));
        _scrollToEnd();
      } else {
        setState(() {
          _phase = "starting";
          _failed = true;
          _status = msg;
        });
      }
      _stopKeepAliveLoop();
      unawaited(_keepAlive(false));
    }
  }

  Future<void> _showEngineLog() async {
    String log = "";
    try {
      log = (await _ch.invokeMethod<String>('readEngineLog')) ?? "";
    } catch (e) {
      log = "读取失败: $e";
    }
    if (!mounted) return;
    _engineLog = log;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B1220),
        title: const Text("引擎日志",
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(
              _engineLog.isEmpty ? "(空)" : _engineLog,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11, height: 1.35),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("关闭", style: TextStyle(color: Color(0xFF00FFCC))),
          ),
        ],
      ),
    );
  }

  Future<void> _sendRaw(Map<String, dynamic> msg) async {
    try {
      await _ch.invokeMethod('rpcSend', {'line': jsonEncode(msg)});
    } catch (_) {}
  }

  Future<void> _showApproval(Map<String, dynamic> params, dynamic id) async {
    final tool = (params['toolName'] ?? params['tool'] ?? "工具").toString();
    final reason = (params['reason'] ?? "").toString();
    bool allow = false;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B1220),
        title: const Text("引擎请求执行工具",
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Text(
          "$tool${reason.isEmpty ? "" : "\n\n$reason"}",
          style: const TextStyle(
              color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              allow = false;
              Navigator.pop(ctx);
            },
            child: const Text("拒绝", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              allow = true;
              Navigator.pop(ctx);
            },
            child: const Text("允许一次",
                style: TextStyle(color: Color(0xFF00FFCC))),
          ),
        ],
      ),
    );
    await _sendRaw({
      'jsonrpc': '2.0',
      'id': id,
      'result': {'outcome': allow ? 'allowed-once' : 'rejected'},
    });
  }

  Future<Map<String, dynamic>?> _rpc(String method, Map<String, dynamic> params,
      {Duration timeout = const Duration(seconds: 60)}) async {
    if (!mounted) return null;
    final id = ++_rpcId;
    final c = Completer<Map<String, dynamic>?>();
    _pending[id] = c;
    try {
      await _ch.invokeMethod('rpcSend', {
        'line': jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        })
      });
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('等待引擎响应超时');
    });
  }

  void _onRpcLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return;
    Map<String, dynamic> m;
    try {
      final decoded = jsonDecode(t);
      if (decoded is! Map) return;
      m = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }

    if (m.containsKey('id') && m['method'] != null) {
      final method = m['method'];
      final p = (m['params'] is Map)
          ? (m['params'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      if (method == 'approval/request') {
        unawaited(_showApproval(p, m['id']));
      } else if (method == 'user-question/ask') {
        unawaited(_sendRaw({
          'jsonrpc': '2.0',
          'id': m['id'],
          'result': {'cancelled': true},
        }));
      } else {
        unawaited(_sendRaw({
          'jsonrpc': '2.0',
          'id': m['id'],
          'error': {'code': -32601, 'message': 'not supported'},
        }));
      }
      return;
    }

    if (m.containsKey('id')) {
      final id = m['id'];
      if (id is int) {
        final c = _pending.remove(id);
        if (c != null && !c.isCompleted) {
          final err = m['error'];
          if (err != null) {
            final msg = err is Map ? (err['message'] ?? '$err') : '$err';
            c.completeError(msg.toString());
          } else {
            final r = m['result'];
            c.complete(
                r is Map ? r.cast<String, dynamic>() : <String, dynamic>{});
          }
        }
      }
      return;
    }

    final method = m['method'];
    final params = (m['params'] is Map)
        ? (m['params'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    if (method == 'session.event') {
      final sid = params['sessionId'];
      if (sid is String && sid.isNotEmpty) _sessionId = sid;
      final ev = (params['event'] is Map)
          ? (params['event'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final type = ev['type']?.toString() ?? '';
      final data = ev['data'];
      if (type == 'assistant/live-chunk' || type == 'assistant/chunk') {
        final chunk = (data is Map && data['chunk'] is Map)
            ? (data['chunk'] as Map)
            : (data is Map ? data : const <String, dynamic>{});
        final ctype = chunk['type']?.toString() ?? '';
        if (ctype == 'text-delta' || ctype.isEmpty) {
          final txt = chunk['text']?.toString() ?? _textOf(chunk);
          if (txt.isNotEmpty) {
            _chunkSeen = true;
            setState(() => _streamText += txt);
            _scrollToEnd();
          }
        }
      } else if (type == 'assistant/message') {
        final finalText = _messageText(data);
        setState(() {
          final out = finalText.isNotEmpty ? finalText : _streamText;
          if (out.isNotEmpty) {
            _msgs.add(ChatMsg(out, false));
          }
          _streamText = "";
          _chunkSeen = false;
          _sending = false;
        });
        _saveMsgs();
        _scrollToEnd();
      } else if (type == 'tool/call') {
        final name = (data is Map
                ? (data['toolName'] ?? data['name'] ?? data['tool'])
                : null)
            ?.toString() ??
            "tool";
        final input = data is Map
            ? (data['input'] ?? data['arguments'] ?? data['params'])
            : null;
        final brief = input == null ? "" : _clip(_textOf(input), 160);
        setState(() {
          _msgs.add(ChatMsg("🔧 $name${brief.isEmpty ? "" : "\n$brief"}",
              false,
              kind: 1));
        });
        _saveMsgs();
        _scrollToEnd();
      } else if (type == 'tool/result') {
        final ok = data is Map ? (data['ok'] ?? data['success']) : null;
        final out = data is Map
            ? (data['result'] ?? data['output'] ?? data['content'])
            : null;
        final brief = _clip(_textOf(out), 260);
        setState(() {
          _msgs.add(ChatMsg(
              "${ok == false ? "✗" : "✓"} 结果${brief.isEmpty ? "" : "\n$brief"}",
              false,
              kind: 2));
        });
        _saveMsgs();
        _scrollToEnd();
      } else if (type == 'turn/end') {
        setState(() {
          if (_streamText.isNotEmpty) {
            _msgs.add(ChatMsg(_streamText, false));
            _streamText = "";
          }
          _sending = false;
          _chunkSeen = false;
        });
        _saveMsgs();
        _scrollToEnd();
      }
    } else if (method == 'session.status') {
    } else if (method == 'session.query.completed') {
      final fr = params['finalResponse'];
      final txt = _messageText(fr);
      setState(() {
        if (_streamText.isNotEmpty) {
          _msgs.add(ChatMsg(_streamText, false));
          _streamText = "";
        } else if (txt.isNotEmpty) {
          _msgs.add(ChatMsg(txt, false));
        }
        _sending = false;
        _chunkSeen = false;
      });
      _scrollToEnd();
    }
  }

  String _clip(String s, int n) {
    if (s.length <= n) return s;
    return s.substring(0, n) + "…";
  }

  String _messageText(dynamic data) {
    if (data is Map) {
      final msg = data['message'];
      if (msg is Map) {
        final content = msg['content'];
        if (content is List) {
          final b = StringBuffer();
          for (final blk in content) {
            if (blk is Map) {
              final type = blk['type']?.toString();
              if (type == 'text' && blk['text'] is String) {
                b.write(blk['text']);
              }
            }
          }
          if (b.isNotEmpty) return b.toString();
        }
      }
    }
    return _textOf(data);
  }

  String _textOf(dynamic o) {
    if (o is String) return "";
    if (o is List) {
      final b = StringBuffer();
      for (final e in o) {
        b.write(_textOf(e));
      }
      return b.toString();
    }
    if (o is Map) {
      final b = StringBuffer();
      for (final k in ['text', 'textDelta', 'content', 'body']) {
        final v = o[k];
        if (v is String) {
          b.write(v);
        } else if (v is Map || v is List) {
          b.write(_textOf(v));
        }
      }
      if (b.isNotEmpty) return b.toString();
      for (final v in o.values) {
        if (v is Map || v is List) b.write(_textOf(v));
      }
      return b.toString();
    }
    return "";
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    if (text.startsWith("/")) {
      _inputCtrl.clear();
      _handleSlash(text);
      return;
    }
    if (!_rpcReady) {
      _inputCtrl.clear();
      setState(() {
        _msgs.add(ChatMsg(text, true));
        _msgs.add(ChatMsg("引擎还在启动，请稍等…", false));
      });
      _scrollToEnd();
      return;
    }
    _inputCtrl.clear();
    setState(() {
      _msgs.add(ChatMsg(text, true));
      for (final s in _sessions) {
        if (s.id == _sessionKey && s.title == "新对话") {
          s.title = text.length > 12 ? text.substring(0, 12) : text;
        }
      }
      _sending = true;
      _streamText = "";
      _chunkSeen = false;
    });
    _saveMsgs();
    _scrollToEnd();
    Timer(const Duration(seconds: 90), () {
      if (!mounted) return;
      if (_sending && _streamText.isEmpty) {
        setState(() {
          _sending = false;
          _msgs.add(ChatMsg("引擎 90 秒没有回应，可以先点右上角「网页版」，或重启 App 再试", false));
        });
        _scrollToEnd();
      }
    });
    try {
      await _rpc('session/query', {
        'sessionId': _sessionId,
        'contentBlocks': [
          {'type': 'text', 'text': text}
        ],
      }, timeout: const Duration(minutes: 10));
    } catch (e) {
      setState(() {
        _sending = false;
        _msgs.add(ChatMsg("发送失败: $e", false));
      });
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _switchToWeb() async {
    setState(() {
      _status = "正在启动网页版...";
      _failed = false;
    });
    try {
      await _ch.invokeMethod('startWeb', {'apiKey': _apiKey});
    } catch (e) {
      setState(() {
        _failed = true;
        _status = "网页版启动失败: $e";
      });
    }
  }

  void _openWeb(String url) {
    _engineUrl = url;
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF03060A))
      ..loadRequest(Uri.parse(url));
    setState(() {
      _web = c;
      _phase = "web";
    });
  }

  void _saveSettingsAndStart() {
    final key = _keyCtrl.text.trim();
    final model = _modelCtrl.text.trim().isEmpty
        ? "deepseek-flash"
        : _modelCtrl.text.trim();
    setState(() {
      _apiKey = key;
      _model = model;
    });
    unawaited(_saveSettings());
    setState(() {
      _phase = "chat";
      _failed = false;
      _status = "正在启动引擎…";
    });
    unawaited(_startEngine());
  }

  @override
  Widget build(BuildContext context) {
    final scaled = MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(_textScale),
    );
    final web = _web;
    late final Widget child;
    if (web != null) {
      child = _buildWeb(web);
    } else {
      switch (_phase) {
        case "setup":
          child = _buildSetup();
          break;
        case "files":
          child = _buildFiles();
          break;
        default:
          child = _buildChat();
      }
    }
    return MediaQuery(data: scaled, child: child);
  }

  Widget _buildSetup() {
    final currentModel = _models.contains(_modelCtrl.text.trim())
        ? _modelCtrl.text.trim()
        : _models.first;
    const radius = BorderRadius.all(Radius.circular(14));
    const fieldBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Color(0x22FFFFFF)),
    );
    Widget sectionTitle(String text) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(text,
              style: const TextStyle(
                  color: Color(0x88FFFFFF), fontSize: 12, letterSpacing: 1)),
        );
    return Container(
      color: const Color(0xFF03060A),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: StarryCloudPainter(_clouds, _stars)),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 16, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _phase = "chat";
                            _failed = false;
                            _status = "";
                          });
                        },
                        icon: const Icon(Icons.arrow_back,
                            size: 20, color: Colors.white70),
                      ),
                      const Text("设置",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_rpcReady)
                        const Row(children: [
                          Icon(Icons.circle,
                              size: 8, color: Color(0xFF00FFCC)),
                          SizedBox(width: 4),
                          Text("引擎运行中",
                              style: TextStyle(
                                  color: Color(0x9900FFCC), fontSize: 11)),
                        ]),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        sectionTitle("模型服务"),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E141B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0x18FFFFFF)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _keyCtrl,
                                obscureText: !_showKey,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  labelText: "DeepSeek API Key",
                                  hintText: "sk-…",
                                  labelStyle: const TextStyle(
                                      color: Color(0x99FFFFFF), fontSize: 13),
                                  hintStyle: const TextStyle(
                                      color: Color(0x44FFFFFF), fontSize: 13),
                                  helperText: "只保存在本机，不会上传",
                                  helperStyle: const TextStyle(
                                      color: Color(0x55FFFFFF), fontSize: 11),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                        _showKey
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        size: 18,
                                        color: Colors.white38),
                                    onPressed: () =>
                                        setState(() => _showKey = !_showKey),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF0A1016),
                                  enabledBorder: fieldBorder,
                                  focusedBorder: const OutlineInputBorder(
                                    borderRadius: radius,
                                    borderSide:
                                        BorderSide(color: Color(0x9900FFCC)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Text("模型",
                                      style: TextStyle(
                                          color: Color(0x99FFFFFF),
                                          fontSize: 13)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: currentModel,
                                        isExpanded: true,
                                        dropdownColor: const Color(0xFF0E141B),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14),
                                        items: [
                                          for (final m in _models)
                                            DropdownMenuItem(
                                              value: m,
                                              child: Text(m,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14)),
                                            ),
                                        ],
                                        onChanged: (v) {
                                          if (v == null) return;
                                          setState(() {
                                            _modelCtrl.text = v;
                                            _testResult = "";
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: _testing ? null : _testKey,
                                    icon: _testing
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF00FFCC)))
                                        : const Icon(Icons.wifi_tethering,
                                            size: 16,
                                            color: Color(0xFF00FFCC)),
                                    label: const Text("测试连接",
                                        style: TextStyle(
                                            color: Color(0xFF00FFCC),
                                            fontSize: 13)),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _testResult,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _testResult.startsWith("✓")
                                            ? const Color(0xFF00FFCC)
                                            : Colors.white54,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        sectionTitle("账户"),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E141B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0x18FFFFFF)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined,
                                  size: 20, color: Colors.white54),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text("DeepSeek 余额",
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _balanceLoading
                                          ? "查询中…"
                                          : (_balance.isEmpty
                                              ? "点右侧刷新"
                                              : _balance),
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: "刷新余额",
                                onPressed:
                                    _balanceLoading ? null : _fetchBalance,
                                icon: _balanceLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF00FFCC)))
                                    : const Icon(Icons.refresh,
                                        size: 18,
                                        color: Color(0xCC00FFCC)),
                              ),
                            ],
                          ),
                        ),
                        sectionTitle("显示"),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E141B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0x18FFFFFF)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("字体大小",
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 14)),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  for (final item in const [
                                    ["小", 0.9],
                                    ["标准", 1.0],
                                    ["大", 1.15],
                                  ])
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(
                                            item[0] as String,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: (_textScale ==
                                                        (item[1] as double))
                                                    ? const Color(0xFF03211D)
                                                    : Colors.white70)),
                                        selected:
                                            _textScale == (item[1] as double),
                                        selectedColor:
                                            const Color(0xFF00FFCC),
                                        backgroundColor:
                                            const Color(0xFF15202B),
                                        onSelected: (_) {
                                          setState(() =>
                                              _textScale = item[1] as double);
                                          unawaited(_saveSettings());
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        sectionTitle("用量"),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E141B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0x18FFFFFF)),
                          ),
                          child: Text(
                            _usageSummary,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                height: 1.5),
                          ),
                        ),
                        sectionTitle("会话"),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E141B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0x18FFFFFF)),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.delete_sweep_outlined,
                                    size: 20, color: Colors.white54),
                                title: const Text("清空当前对话",
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                onTap: () {
                                  setState(() {
                                    _msgs.clear();
                                    _streamText = "";
                                  });
                                  _saveMsgs();
                                },
                              ),
                              ListTile(
                                dense: true,
                                leading: const Icon(
                                    Icons.delete_forever_outlined,
                                    size: 20,
                                    color: Colors.white54),
                                title: const Text("清空全部对话",
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                onTap: () {
                                  setState(() {
                                    _sessions.clear();
                                    _sessions.add(ChatSession(
                                        _newId(), "新对话", <ChatMsg>[]));
                                    _sessionKey = _sessions.first.id;
                                    _msgs = _sessions.first.msgs;
                                    _streamText = "";
                                  });
                                  _saveSessions();
                                },
                              ),
                            ],
                          ),
                        ),
                        sectionTitle("关于"),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E141B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0x18FFFFFF)),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.article_outlined,
                                    size: 20, color: Colors.white54),
                                title: const Text("查看引擎日志",
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                onTap: _showEngineLog,
                              ),
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.public,
                                    size: 20, color: Colors.white54),
                                title: const Text("打开网页版",
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                onTap: () {
                                  setState(() => _phase = "chat");
                                  unawaited(_switchToWeb());
                                },
                              ),
                              const ListTile(
                                dense: true,
                                leading: Icon(Icons.info_outline,
                                    size: 20, color: Colors.white38),
                                title: Text("落锤 1.1.0",
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 13)),
                                subtitle: Text("本地 DSH 引擎 · 原生界面",
                                    style: TextStyle(
                                        color: Colors.white24, fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _saveSettingsAndStart,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF00FFCC),
                              foregroundColor: const Color(0xFF03211D),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24)),
                            ),
                            child: const Text("保存",
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int get _ctxChars =>
      _msgs.fold(0, (n, m) => n + m.text.length) + _streamText.length;

  String get _ctxText {
    final chars = _ctxChars;
    if (chars == 0) return "";
    return "约 ${(chars * 0.7).round()} tokens · $chars 字";
  }

  String get _fsRootHost => "$_appDir/dsh-env/rootfs";

  Future<void> _loadFiles() async {
    setState(() => _fsLoading = true);
    try {
      final dir = Directory("$_fsRootHost$_fsPath");
      final list = dir.existsSync()
          ? await dir.list(followLinks: false).toList()
          : <FileSystemEntity>[];
      list.sort((a, b) {
        final ad = a is Directory ? 0 : 1;
        final bd = b is Directory ? 0 : 1;
        if (ad != bd) return ad - bd;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      if (!mounted) return;
      setState(() => _fsEntries = list);
    } catch (_) {
      if (mounted) setState(() => _fsEntries = []);
    } finally {
      if (mounted) setState(() => _fsLoading = false);
    }
  }

  void _openFiles() {
    setState(() {
      _phase = "files";
      _fsPath = "/root";
    });
    unawaited(_loadFiles());
  }

  void _fsOpen(FileSystemEntity e) {
    if (e is Directory) {
      setState(() => _fsPath = e.path.substring(_fsRootHost.length));
      unawaited(_loadFiles());
      return;
    }
    final name = e.path.split("/").last;
    final f = File(e.path);
    final size = f.lengthSync();
    String content = "";
    if (size < 200 * 1024) {
      try {
        content = f.readAsStringSync();
      } catch (_) {
        content = "(二进制文件)";
      }
    } else {
      content = "(文件较大：${(size / 1024).toStringAsFixed(0)} KB)";
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B1220),
        title: Text(name,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: e.path.substring(_fsRootHost.length)));
              Navigator.pop(ctx);
            },
            child: const Text("复制路径",
                style: TextStyle(color: Color(0xCC00FFCC))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("关闭", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildFiles() {
    final parent = _fsPath == "/"
        ? "/"
        : _fsPath.substring(0, _fsPath.lastIndexOf("/") == 0
            ? 1
            : _fsPath.lastIndexOf("/"));
    return Container(
      color: const Color(0xFF03060A),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() => _phase = "chat"),
                    icon: const Icon(Icons.arrow_back,
                        size: 20, color: Colors.white70),
                  ),
                  Expanded(
                    child: Text(_fsPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15)),
                  ),
                  if (_fsLoading)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF00FFCC))),
                ],
              ),
            ),
            if (_fsPath != "/")
              ListTile(
                dense: true,
                leading: const Icon(Icons.arrow_upward,
                    size: 18, color: Color(0xFF00FFCC)),
                title: const Text("上一级",
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                onTap: () {
                  setState(() => _fsPath = parent);
                  unawaited(_loadFiles());
                },
              ),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            Expanded(
              child: ListView.builder(
                itemCount: _fsEntries.length,
                itemBuilder: (ctx, i) {
                  final e = _fsEntries[i];
                  final isDir = e is Directory;
                  final name = e.path.split("/").last;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                        isDir ? Icons.folder_outlined : Icons.description_outlined,
                        size: 20,
                        color: isDir
                            ? const Color(0xCC00FFCC)
                            : Colors.white38),
                    title: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13.5)),
                    subtitle: isDir
                        ? null
                        : Text("${(e as File).lengthSync()} 字节",
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 10)),
                    onTap: () => _fsOpen(e),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _messageActions(String text, bool isAi) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1620),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy, size: 20, color: Colors.white70),
              title: const Text("复制",
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(ctx);
              },
            ),
            if (isAi)
              ListTile(
                leading: const Icon(Icons.refresh,
                    size: 20, color: Color(0xFF00FFCC)),
                title: const Text("重新生成",
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _regenerate();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _regenerate() async {
    String last = "";
    for (final m in _msgs.reversed) {
      if (m.mine) {
        last = m.text;
        break;
      }
    }
    if (last.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _rpc('session/query', {
        'sessionId': _sessionId,
        'contentBlocks': [
          {'type': 'text', 'text': last}
        ],
      }, timeout: const Duration(minutes: 10));
    } catch (e) {
      setState(() {
        _sending = false;
        _msgs.add(ChatMsg("发送失败: $e", false));
      });
      _scrollToEnd();
    }
  }

  void _exportConversation() {
    final b = StringBuffer();
    b.writeln("# 落锤对话 - ${_curTitle}");
    for (final m in _msgs) {
      final t = DateTime.fromMillisecondsSinceEpoch(m.ts);
      final hh = t.hour.toString().padLeft(2, "0");
      final mm = t.minute.toString().padLeft(2, "0");
      b.writeln();
      b.writeln(m.mine ? "**我** ($hh:$mm)" : "**AI** ($hh:$mm)");
      b.writeln();
      b.writeln(m.text);
    }
    Clipboard.setData(ClipboardData(text: b.toString()));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
          content: Text("已复制为 Markdown"), duration: Duration(seconds: 1)),
    );
  }

  bool _handleSlash(String text) {
    final parts = text.trim().split(RegExp(r"\s+"));
    final cmd = parts.first.toLowerCase();
    switch (cmd) {
      case "/new":
        _newChat();
        return true;
      case "/clear":
        setState(() {
          _msgs.clear();
          _streamText = "";
        });
        _saveMsgs();
        return true;
      case "/export":
        _exportConversation();
        return true;
      case "/web":
        unawaited(_switchToWeb());
        return true;
      case "/model":
        final m = parts.length > 1 ? parts[1] : "";
        if (_models.contains(m)) {
          setState(() => _model = m);
          _modelCtrl.text = m;
          unawaited(_saveSettings());
          _engineRestartHint();
        }
        return true;
      case "/help":
        setState(() {
          _msgs.add(ChatMsg(
              "可用命令：\n/new 新建对话\n/clear 清空当前\n/export 导出复制\n/web 网页版\n/model deepseek-flash 或 deepseek-v4-pro\n/help 帮助",
              false));
        });
        _scrollToEnd();
        return true;
    }
    return false;
  }

  void _engineRestartHint() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: const Text("已切换模型，重启引擎后生效"),
        action: SnackBarAction(
          label: "立即重启",
          onPressed: () {
            unawaited(_ch.invokeMethod('killEngine'));
            unawaited(_startEngine());
          },
        ),
      ),
    );
  }

  void _pickModel() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1620),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text("选择模型",
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            for (final m in _models)
              ListTile(
                leading: Icon(
                    _model == m
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: _model == m
                        ? const Color(0xFF00FFCC)
                        : Colors.white38),
                title: Text(m,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _model = m);
                  _modelCtrl.text = m;
                  unawaited(_saveSettings());
                  _engineRestartHint();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchBalance() async {
    final key = _keyCtrl.text.trim().isEmpty ? _apiKey : _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _balance = "未配置 Key");
      return;
    }
    setState(() => _balanceLoading = true);
    try {
      final resp = await http.get(
        Uri.parse("https://api.deepseek.com/user/balance"),
        headers: {"Authorization": "Bearer $key"},
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final infos = data is Map ? data['balance_infos'] : null;
        if (infos is List && infos.isNotEmpty && infos.first is Map) {
          final i = infos.first as Map;
          final cur = (i['currency'] ?? "CNY").toString();
          final total = (i['total_balance'] ?? "0").toString();
          final granted = (i['granted_balance'] ?? "0").toString();
          setState(() => _balance = "$cur $total（赠金 $granted）");
        } else {
          setState(() => _balance = "无余额信息");
        }
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        setState(() => _balance = "Key 无效");
      } else {
        setState(() => _balance = "HTTP ${resp.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => _balance = "查询失败");
    } finally {
      if (mounted) setState(() => _balanceLoading = false);
    }
  }

  String get _usageSummary {
    int userMsgs = 0, aiMsgs = 0, chars = 0;
    for (final s in _sessions) {
      for (final m in s.msgs) {
        chars += m.text.length;
        if (m.mine) {
          userMsgs++;
        } else if (m.kind == 0) {
          aiMsgs++;
        }
      }
    }
    return "会话 ${_sessions.length} · 你 $userMsgs 条 · AI $aiMsgs 条 · 共 $chars 字";
  }

  Future<void> _testKey() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _testResult = "先填 API Key");
      return;
    }
    setState(() {
      _testing = true;
      _testResult = "";
    });
    try {
      final resp = await http.get(
        Uri.parse("https://api.deepseek.com/models"),
        headers: {"Authorization": "Bearer $key"},
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => _testResult = "✓ 连接成功");
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        setState(() => _testResult = "✗ Key 无效（${resp.statusCode}）");
      } else {
        setState(() => _testResult = "✗ HTTP ${resp.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = "✗ 网络不通：$e");
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  List<ChatSession> get _filteredSessions {
    final q = _sessionQuery.trim().toLowerCase();
    if (q.isEmpty) return _sessions;
    return [
      for (final s in _sessions)
        if (s.title.toLowerCase().contains(q) ||
            s.msgs.any((m) => m.text.toLowerCase().contains(q)))
          s
    ];
  }

  void _renameSession(ChatSession s) {
    final ctrl = TextEditingController(text: s.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B1220),
        title: const Text("重命名会话",
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: "会话名称"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                setState(() => s.title = name);
                _saveSessions();
              }
              Navigator.pop(ctx);
            },
            child: const Text("保存",
                style: TextStyle(color: Color(0xFF00FFCC))),
          ),
        ],
      ),
    );
  }

  void _copySession(ChatSession s) {
    final b = StringBuffer();
    for (final m in s.msgs) {
      b.write(m.mine ? "我：" : "AI：");
      b.writeln(m.text);
    }
    Clipboard.setData(ClipboardData(text: b.toString()));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
          content: Text("对话已复制"), duration: Duration(milliseconds: 900)),
    );
  }

  void _sessionMenu(ChatSession s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1620),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  size: 20, color: Colors.white70),
              title: const Text("重命名",
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _renameSession(s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined,
                  size: 20, color: Colors.white70),
              title: const Text("复制整段对话",
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _copySession(s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  size: 20, color: Color(0xFFFF8A80)),
              title: const Text("删除会话",
                  style: TextStyle(color: Color(0xFFFF8A80), fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteSession(s.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  String get _curTitle {
    for (final s in _sessions) {
      if (s.id == _sessionKey) return s.title;
    }
    return "落锤";
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0A1018),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Row(
                children: [
                  const Text("会话",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _newChat();
                    },
                    icon: const Icon(Icons.add,
                        size: 16, color: Color(0xFF00FFCC)),
                    label: const Text("新建",
                        style:
                            TextStyle(color: Color(0xFF00FFCC), fontSize: 13)),
                  ),
                ],
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_open,
                  size: 20, color: Color(0xCC00FFCC)),
              title: const Text("工作区文件",
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _openFiles();
              },
            ),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: TextField(
                onChanged: (v) => setState(() => _sessionQuery = v),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "搜索会话",
                  hintStyle:
                      const TextStyle(color: Colors.white30, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: Colors.white30),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF101A24),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredSessions.length,
                itemBuilder: (ctx, i) {
                  final s = _filteredSessions[i];
                  final selected = s.id == _sessionKey;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: const Color(0x2200FFCC),
                    leading: Icon(Icons.chat_bubble_outline,
                        size: 18,
                        color: selected
                            ? const Color(0xFF00FFCC)
                            : Colors.white38),
                    title: Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontSize: 14)),
                    subtitle: Text("${s.msgs.length} 条消息",
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.white30),
                      onPressed: () => _deleteSession(s.id),
                    ),
                    onLongPress: () => _sessionMenu(s),
                    onTap: () {
                      Navigator.pop(context);
                      _switchSession(s.id);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat() {
    const none = TextDecoration.none;
    return Scaffold(
      backgroundColor: const Color(0xFF03060A),
      drawer: _buildDrawer(),
      body: Container(
      color: const Color(0xFF03060A),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                      icon: const Icon(Icons.menu,
                          size: 22, color: Colors.white70),
                    ),
                  ),
                  Flexible(
                    child: Text(_curTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            decoration: none,
                            decorationColor: Colors.transparent)),
                  ),
                  InkWell(
                    onTap: _pickModel,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10202A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x2200FFCC)),
                      ),
                      child: Text(
                        _model == "deepseek-v4-pro" ? "V4 Pro" : "Flash",
                        style: const TextStyle(
                            color: Color(0xCC00FFCC), fontSize: 10.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _rpcReady
                          ? const Color(0xFF00FFCC)
                          : (_failed
                              ? const Color(0xFFFF5252)
                              : const Color(0xFFFFD54F)),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: "新建对话",
                    onPressed: _newChat,
                    icon: const Icon(Icons.add_comment_outlined,
                        size: 20, color: Color(0xCC00FFCC)),
                  ),
                  IconButton(
                    tooltip: "设置",
                    onPressed: () {
                      setState(() {
                        _phase = "setup";
                        _failed = false;
                        _status = "修改设置";
                      });
                    },
                    icon: const Icon(Icons.settings_outlined,
                        size: 20, color: Color(0xCC00FFCC)),
                  ),
                  IconButton(
                    tooltip: "引擎日志",
                    onPressed: _showEngineLog,
                    icon: const Icon(Icons.article_outlined,
                        size: 20, color: Color(0xCC00FFCC)),
                  ),
                  IconButton(
                    tooltip: "网页版",
                    onPressed: _switchToWeb,
                    icon: const Icon(Icons.public,
                        size: 20, color: Color(0xFF00FFCC)),
                  ),
                ],
              ),
            ),
            if ((_downloading || (_progress > 0 && _progress < 1)) && !_rpcReady)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 4,
                    backgroundColor: Colors.white10,
                    color: const Color(0xFF00FFCC),
                  ),
                ),
              ),
            if (!_rpcReady)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF00FFCC)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _status.isEmpty ? "引擎准备中…" : _status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                          height: 1.4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                itemCount: _msgs.length + (_streamText.isNotEmpty ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (_msgs.isEmpty && _streamText.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          _CenterText("落锤",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          _CenterText("直接发消息开始，Key 在右上角设置里改",
                              style: const TextStyle(
                                  color: Color(0x88FFFFFF), fontSize: 12.5)),
                          const SizedBox(height: 26),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in const [
                                "帮我写段代码",
                                "解释一下这个概念",
                                "翻译下面这段话",
                                "看看当前目录有什么"
                              ])
                                ActionChip(
                                  label: Text(s,
                                      style: const TextStyle(
                                          color: Color(0xFF00FFCC),
                                          fontSize: 12)),
                                  backgroundColor: const Color(0xFF10202A),
                                  side: const BorderSide(
                                      color: Color(0x3300FFCC)),
                                  onPressed: () {
                                    _inputCtrl.text = s;
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                  final isStream = i == _msgs.length;
                  final text = isStream ? _streamText : _msgs[i].text;
                  final mine = isStream ? false : _msgs[i].mine;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: mine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Bubble(
                        text: text,
                        mine: mine,
                        kind: isStream ? 0 : _msgs[i].kind,
                        ts: isStream ? null : _msgs[i].ts,
                            onLongPress: () =>
                                _messageActions(text, !mine && !isStream),
                          ),
                          if (!isStream) _BubbleTime(ts: _msgs[i].ts),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_sending)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00FFCC))),
              ),
            if (_ctxText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 18, bottom: 2),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(_ctxText,
                      style: const TextStyle(
                          color: Color(0x44FFFFFF),
                          fontSize: 10,
                          decoration: TextDecoration.none)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          decoration: none,
                          decorationColor: Colors.transparent),
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: "说点什么…",
                        hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 15,
                            decoration: none,
                            decorationColor: Colors.transparent),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: Icon(Icons.send,
                        size: 26,
                        color: _sending
                            ? Colors.white24
                            : const Color(0xFF00FFCC)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildWeb(WebViewController web) {
    return Container(
      color: const Color(0xFF03060A),
      child: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: web)),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _webButton(Icons.chat_bubble_outline, () async {
                      setState(() {
                        _web = null;
                        _phase = "starting";
                        _status = "正在启动原生界面…";
                      });
                      await _afterEnvReady();
                    }),
                    const SizedBox(width: 8),
                    _webButton(Icons.article_outlined, _showEngineLog),
                    const SizedBox(width: 8),
                    _webButton(Icons.refresh, () => web.reload()),
                    const SizedBox(width: 8),
                    _webButton(Icons.arrow_back, () async {
                      try {
                        await _ch.invokeMethod('openEngine', {'url': _engineUrl});
                      } catch (_) {}
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _webButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: const Color(0xFF00FFCC)),
        ),
      ),
    );
  }
}class _LeftText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _LeftText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return CustomPaint(
      size: Size(tp.width, tp.height),
      painter: _TextDrawPainter(text, style),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return SizedBox(
        width: 190,
        height: 44,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00FFCC),
            foregroundColor: const Color(0xFF03211D),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1)),
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0x5500FFCC)),
          foregroundColor: const Color(0xFF00FFCC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 13, letterSpacing: 0.6)),
      ),
    );
  }
}class _CenterText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _CenterText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(minWidth: c.maxWidth, maxWidth: c.maxWidth);
      return CustomPaint(
        size: Size(c.maxWidth, tp.height),
        painter: _TextDrawPainter(text, style),
      );
    });
  }
}

class _TextDrawPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  _TextDrawPainter(this.text, this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(minWidth: size.width, maxWidth: size.width);
    tp.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _TextDrawPainter old) =>
      old.text != text || old.style != style;
}

class StarParticle {
  double x, y, radius, maxLife, life;
  StarParticle(
      {required this.x,
      required this.y,
      required this.radius,
      required this.maxLife,
      required this.life});
}

class CloudParticle {
  double x, y, radius, opacity, vx;
  CloudParticle(
      {required this.x,
      required this.y,
      required this.radius,
      required this.opacity,
      required this.vx});
}

class StarryCloudPainter extends CustomPainter {
  final List<CloudParticle> clouds;
  final List<StarParticle> stars;
  StarryCloudPainter(this.clouds, this.stars);

  @override
  void paint(Canvas canvas, Size size) {
    final cloudPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60.0);
    for (var cloud in clouds) {
      final centerOffset = Offset(cloud.x * size.width, cloud.y * size.height);
      final baseRadius = cloud.radius * size.width;
      cloudPaint.color = Colors.grey.withOpacity(cloud.opacity);
      canvas.drawCircle(centerOffset, baseRadius, cloudPaint);
      canvas.drawCircle(
          Offset(centerOffset.dx - baseRadius * 0.6,
              centerOffset.dy + baseRadius * 0.1),
          baseRadius * 0.7,
          cloudPaint);
      canvas.drawCircle(
          Offset(centerOffset.dx + baseRadius * 0.7,
              centerOffset.dy - baseRadius * 0.1),
          baseRadius * 0.8,
          cloudPaint);
      canvas.drawCircle(
          Offset(centerOffset.dx + baseRadius * 0.2,
              centerOffset.dy - baseRadius * 0.5),
          baseRadius * 0.6,
          cloudPaint);
    }
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (var star in stars) {
      double lifeProgress = star.life / star.maxLife;
      double opacity = math.sin(lifeProgress * math.pi);
      starPaint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(star.x * size.width, star.y * size.height),
          star.radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StarryCloudPainter oldDelegate) => true;
}

class _BubbleTime extends StatelessWidget {
  final int ts;
  const _BubbleTime({required this.ts});

  @override
  Widget build(BuildContext context) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    final hh = t.hour.toString().padLeft(2, "0");
    final mm = t.minute.toString().padLeft(2, "0");
    return Padding(
      padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
      child: Text("$hh:$mm",
          style: const TextStyle(
              color: Color(0x44FFFFFF),
              fontSize: 10,
              decoration: TextDecoration.none)),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  final int kind;
  final int? ts;
  final VoidCallback onLongPress;
  const _Bubble({
    required this.text,
    required this.mine,
    required this.kind,
    required this.onLongPress,
    this.ts,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.86;
    if (kind == 1 || kind == 2) {
      final isCall = kind == 1;
      return GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1620),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isCall ? const Color(0x3300FFCC) : const Color(0x22FFFFFF)),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: isCall ? const Color(0xCC00FFCC) : const Color(0x99FFFFFF),
              fontSize: 12.5,
              height: 1.45,
              fontFamily: 'monospace',
              decoration: TextDecoration.none,
              decorationColor: Colors.transparent,
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              mine ? const Color(0xFF14524A) : const Color(0xFF141A22),
          borderRadius: BorderRadius.circular(14),
        ),
        child: _MarkdownBody(text: text),
      ),
    );
  }

  Widget _timeLabel() {
    if (ts == null) return const SizedBox.shrink();
    final t = DateTime.fromMillisecondsSinceEpoch(ts!);
    final hh = t.hour.toString().padLeft(2, "0");
    final mm = t.minute.toString().padLeft(2, "0");
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text("$hh:$mm",
          style: const TextStyle(
              color: Color(0x55FFFFFF),
              fontSize: 10,
              decoration: TextDecoration.none)),
    );
  }
}

class _MarkdownBody extends StatelessWidget {
  final String text;
  const _MarkdownBody({required this.text});

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    final re = RegExp(r'```([a-zA-Z0-9_+-]*)\n([\s\S]*?)```');
    int cursor = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > cursor) {
        final t = text.substring(cursor, m.start);
        if (t.trim().isNotEmpty) parts.add(_plain(t.trimRight()));
      }
      final code = (m.group(2) ?? "").trimRight();
      parts.add(_codeBlock(context, code));
      cursor = m.end;
    }
    if (cursor < text.length) {
      final t = text.substring(cursor);
      if (t.trim().isNotEmpty) parts.add(_plain(t.trim()));
    }
    if (parts.isEmpty) parts.add(_plain(text));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          parts[i],
        ],
      ],
    );
  }

  Widget _plain(String t) => Text(
        t,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.5,
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
      );

  Widget _codeBlock(BuildContext context, String code) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080D13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 10),
              const Icon(Icons.code, size: 14, color: Color(0x88FFFFFF)),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text("代码已复制"),
                      duration: Duration(milliseconds: 900),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text("复制",
                      style: TextStyle(
                          color: Color(0xCC00FFCC), fontSize: 11)),
                ),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Text(
              code,
              style: const TextStyle(
                color: Color(0xFFDDEFEA),
                fontSize: 12.5,
                height: 1.45,
                fontFamily: 'monospace',
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
