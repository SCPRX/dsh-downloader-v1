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
      home: const AppRoot(),
    );
  }
}

/// 用户手动换源时用来打断正在进行的下载
class _SwitchRequested implements Exception {}

/// 一条聊天消息
class ChatMsg {
  final String text;
  final bool mine;
  ChatMsg(this.text, this.mine);
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with SingleTickerProviderStateMixin {
  static const MethodChannel _ch = MethodChannel('com.dsh.dshapp/status');

  // ---------- 阶段 ----------
  // env：下载/解压环境；setup：填 API Key；starting：起引擎；chat：原生聊天；web：网页兜底
  String _phase = 'env';

  // ---------- 通用状态 ----------
  String _status = "正在检查环境...";
  bool _failed = false;
  double _progress = 0.0;

  // ---------- 下载 ----------
  static const List<String> _envUrls = [
    'https://ghfast.top/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://gh-proxy.com/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
  ];
  static const List<String> _envNames = ['高速镜像', '极速镜像', '官方源'];
  /// 环境包的标准大小，用于判断源上是不是旧文件 / 下载是否完整
  static const int _envSize = 923708522;
  int? _pinnedSrc;
  int _runId = 0;
  int _activeSrc = -1;
  int get _selectedSrc => _pinnedSrc ?? (_activeSrc >= 0 ? _activeSrc : -1);
  bool _downloading = false;
  String _speed = "";
  String _curName = "";
  final Map<int, String> _srcInfo = {};
  final Map<int, double> _srcBps = {};
  DateTime _lastProgressPaint = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _keepAliveTimer;

  static const String _libsUrl =
      'https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/runtime-libs.zip';
  Completer<void>? _libsDone;
  Completer<void>? _linksDone;

  static const List<String> _models = ['deepseek-flash', 'deepseek-v4-pro'];
  bool _testing = false;
  String _testResult = "";

  // ---------- 设置 ----------
  String _apiKey = "";
  String _model = "deepseek-flash";
  String _appDir = "";
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _modelCtrl =
      TextEditingController(text: "deepseek-flash");

  // ---------- JSON-RPC ----------
  int _rpcId = 0;
  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  String _sessionId = "";
  bool _rpcReady = false;

  // ---------- 聊天 ----------
  final List<ChatMsg> _msgs = [];
  String _streamText = "";
  bool _sending = false;
  bool _chunkSeen = false;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // ---------- 网页兜底 ----------
  WebViewController? _web;
  String _engineUrl = "http://127.0.0.1:3090";

  // ---------- 背景 ----------
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
          setState(() {
            _failed = true;
            _status = call.arguments as String;
          });
          _stopKeepAliveLoop();
          unawaited(_keepAlive(false));
          break;
        case 'envReady':
          _afterEnvReady();
          break;
        case 'libsReady':
          if (_libsDone != null && !_libsDone!.isCompleted) {
            _libsDone!.complete();
          }
          break;
        case 'linksReady':
          if (_linksDone != null && !_linksDone!.isCompleted) {
            _linksDone!.complete();
          }
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
          // 引擎底层日志，忽略即可
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
    super.dispose();
  }

  // ---------------- 启动 ----------------

  Future<void> _bootstrap() async {
    try {
      _appDir = (await _ch.invokeMethod<String>('filesDirPath')) ?? "";
      await _loadSettings();

      final bool installed = await _ch.invokeMethod<bool>('checkEnv') ?? false;
      if (installed) {
        _afterEnvReady();
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
    }
  }

  Future<void> _afterEnvReady() async {
    if (!mounted) return;
    // 解压已经结束，前台服务可以撤了
    _stopKeepAliveLoop();
    unawaited(_keepAlive(false));
    try {
      await _ensureLibs();
      await _repairLinks();
    } catch (_) {
      return;
    }
    if (_apiKey.isEmpty) {
      setState(() {
        _phase = "setup";
        _failed = false;
        _status = "需要填一次 API Key";
      });
      return;
    }
    await _startEngine();
  }

  // ---------------- 运行库（node 缺的 .so） ----------------

  Future<void> _ensureLibs() async {
    final libz = File("$_appDir/dsh-env/libz.so.1");
    if (await libz.exists()) return;

    setState(() {
      _phase = "starting";
      _failed = false;
      _status = "首次运行，正在下载运行库(约 17MB)...";
    });
    try {
      final zip = File("${Directory.systemTemp.path}/runtime-libs.zip");
      if (await zip.exists()) await zip.delete();
      final resp = await http
          .get(Uri.parse(_libsUrl))
          .timeout(const Duration(minutes: 5));
      if (resp.statusCode != 200) {
        throw '下载失败 HTTP ${resp.statusCode}';
      }
      await zip.writeAsBytes(resp.bodyBytes);

      setState(() => _status = "正在安装运行库...");
      _libsDone = Completer<void>();
      await _ch.invokeMethod('installLibs', {'path': zip.path});
      await _libsDone!.future.timeout(const Duration(minutes: 3));
      setState(() => _status = "运行库就绪");
    } catch (e) {
      setState(() {
        _failed = true;
        _status = "运行库下载失败: $e";
      });
      rethrow;
    }
  }

  /// 让原生层把 node_modules 里的符号链接修好（老环境没有链接，node 找不到模块）
  Future<void> _repairLinks() async {
    _linksDone = Completer<void>();
    await _ch.invokeMethod('repairLinks');
    try {
      await _linksDone!.future.timeout(const Duration(minutes: 5));
    } catch (_) {}
  }

  // ---------------- 设置读写 ----------------

  File get _settingsFile => File("$_appDir/native_chat_settings.json");

  Future<void> _loadSettings() async {
    try {
      if (await _settingsFile.exists()) {
        final m = jsonDecode(await _settingsFile.readAsString());
        if (m is Map) {
          _apiKey = (m['apiKey'] ?? "").toString();
          _model = (m['model'] ?? "deepseek-flash").toString();
        }
      }
    } catch (_) {}
    _keyCtrl.text = _apiKey;
    _modelCtrl.text = _model;
  }

  Future<void> _saveSettings() async {
    try {
      await _settingsFile.writeAsString(
          jsonEncode({'apiKey': _apiKey, 'model': _model}));
    } catch (_) {}
  }

  // ---------------- 下载环境（多源 + 断点续传） ----------------

  Future<void> _downloadEnv() async {
    final String? zipPath = await _ch.invokeMethod<String>('envZipPath');
    if (zipPath == null || zipPath.isEmpty) throw '拿不到安装包路径';
    setState(() => _phase = 'env');
    while (true) {
      try {
        await _download(zipPath);
        break;
      } on _SwitchRequested {
        // 用户点了换源：带着新设置重新开始
        continue;
      }
    }
    setState(() {
      _progress = 1.0;
      _status = "下载完成，正在解压(耗时较长)...";
    });
    // 前台服务先留着：解压阶段也需要保活，等环境就绪后再撤
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
      // 已经是完整大小但上次解压失败：说明是坏包，删掉重下
      await part.delete();
      start = 0;
    }

    setState(() {
      _status = start > 0
          ? "继续下载核心环境（已有 ${_mb(start)}）..."
          : "首次启动，正在下载核心环境(约 850MB)...";
    });

    unawaited(_keepAlive(true));
    _startKeepAliveLoop();

    final runId = _runId;
    _downloading = true;
    if (_pinnedSrc == null) {
      if (_srcBps.isEmpty) await _testSources();
    }
    final order = _pinnedSrc != null
        ? <int>[_pinnedSrc!]
        : <int>[for (int i = 0; i < _envUrls.length; i++) i]
      ..sort((a, b) => (_srcBps[b] ?? -1).compareTo(_srcBps[a] ?? -1));

    Object? lastError;
    try {
      for (final i in order) {
        if (runId != _runId) throw _SwitchRequested();
        _activeSrc = i;
        setState(() {
          _speed = "";
          _curName = _envNames[i];
        });
        try {
          await _downloadFrom(i, runId, part, start: start);
          lastError = null;
          _srcInfo[i] = "✓ 可用";
          break;
        } catch (e) {
          lastError = e;
          if (await part.exists()) start = await part.length();
          _srcInfo[i] = "$e";
          final next = order.indexOf(i) + 1;
          if (next < order.length && mounted) {
            setState(() =>
                _status = "${_envNames[i]} 不行，换 ${_envNames[order[next]]}...");
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
      _activeSrc = -1;
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
              _srcInfo[index] = _speed;
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
  }

  // ---------------- 手动换源 ----------------

  void _autoRetest() {
    _pinnedSrc = null;
    _srcBps.clear();
    _srcInfo.clear();
    _runId++;
    setState(() {
      _failed = false;
      _speed = "";
      _curName = "";
      _status = "正在重新测速...";
    });
    if (!_downloading) unawaited(_bootstrap());
  }

  void _switchSource(int i) {
    _pinnedSrc = i;
    _runId++;
    setState(() {
      _failed = false;
      _speed = "";
      _status = "切换到 ${_envNames[i]} 下载...";
    });
    if (!_downloading) unawaited(_bootstrap());
  }

  void _showSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _SourceSheet(this),
    );
  }

  /// 换源面板的内容；由 _SourceSheet 定时重绘，测速结果能实时刷新
  Widget buildSourceSheetContent(BuildContext ctx) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("选择下载源",
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const SizedBox(
                  width: 24,
                  child:
                      Icon(Icons.speed, size: 20, color: Color(0xFF00FFCC))),
              title: const Text("自动测速",
                  style: TextStyle(color: Colors.white)),
              trailing: _selectedSrc == -1
                  ? const Icon(Icons.check_circle, color: Color(0xFF00FFCC))
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _autoRetest();
              },
            ),
            for (int i = 0; i < _envNames.length; i++)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const SizedBox(
                    width: 24,
                    child: Icon(Icons.link,
                        size: 20, color: Color(0xCC00FFCC))),
                title: Text(_envNames[i],
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                    (_srcInfo[i] == null || _srcInfo[i]!.isEmpty)
                        ? "未测"
                        : _srcInfo[i]!,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12)),
                trailing: _selectedSrc == i
                    ? const Icon(Icons.check_circle,
                        color: Color(0xFF00FFCC))
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _switchSource(i);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------- 前台服务（下载/解压时保活） ----------------

  Future<void> _keepAlive(bool on) async {
    try {
      await _ch.invokeMethod('keepAlive', {'on': on});
    } catch (_) {}
  }

  void _startKeepAliveLoop() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_keepAlive(true));
    });
  }

  void _stopKeepAliveLoop() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  // ---------------- 原生引擎（dsh --profile sdk） ----------------

  Future<void> _startEngine() async {
    setState(() {
      _phase = "starting";
      _failed = false;
      _status = "正在启动引擎...";
    });
    try {
      await _ch.invokeMethod('startSdk', {
        'apiKey': _apiKey,
        'model': _model,
      });
      // stdin 会先缓冲，引擎读完自然会回 initialize
      final res = await _rpc('initialize', {
        'cwd': _appDir,
        'provider': 'deepseek-official',
        'model': _model,
        'approvalRequests': false,
      }, timeout: const Duration(seconds: 120));
      if (res == null) throw '引擎没有响应';
      _rpcReady = true;
      setState(() {
        _phase = "chat";
        _failed = false;
        _status = "";
      });
    } catch (e) {
      setState(() {
        _phase = "starting";
        _failed = true;
        _status = "引擎启动失败: $e";
      });
      _stopKeepAliveLoop();
      unawaited(_keepAlive(false));
    }
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
      if (type == 'assistant/chunk') {
        final txt = _textOf(data);
        if (txt.isNotEmpty) {
          _chunkSeen = true;
          setState(() => _streamText += txt);
          _scrollToEnd();
        }
      } else if (type == 'assistant/message') {
        final txt = _textOf(data);
        setState(() {
          if (txt.isNotEmpty && !_chunkSeen) {
            _streamText += txt;
          }
          if (_streamText.isNotEmpty) {
            _msgs.add(ChatMsg(_streamText, false));
          }
          _streamText = "";
          _chunkSeen = false;
          _sending = false;
        });
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
        _scrollToEnd();
      }
    } else if (method == 'session.status') {
      // 可以在这里显示"思考中"等状态，先不处理
    }
  }

  /// 从引擎事件里尽量抽出文字（兼容 chunk / message 两种结构）
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
    if (text.isEmpty || _sending || !_rpcReady) return;
    _inputCtrl.clear();
    setState(() {
      _msgs.add(ChatMsg(text, true));
      _sending = true;
      _streamText = "";
      _chunkSeen = false;
    });
    _scrollToEnd();
    try {
      await _rpc('session/query', {
        'contentBlocks': [
          {'type': 'text', 'text': text}
        ],
        if (_sessionId.isNotEmpty) 'sessionId': _sessionId,
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

  // ---------------- 网页兜底 ----------------

  Future<void> _switchToWeb() async {
    setState(() {
      _status = "正在启动网页版...";
      _failed = false;
    });
    try {
      await _ch.invokeMethod('startWeb');
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
    final model =
        _modelCtrl.text.trim().isEmpty ? "deepseek-flash" : _modelCtrl.text.trim();
    setState(() {
      _apiKey = key;
      _model = model;
    });
    unawaited(_saveSettings());
    unawaited(_startEngine());
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final web = _web;
    if (web != null) return _buildWeb(web);

    switch (_phase) {
      case "chat":
        return _buildChat();
      case "setup":
        return _buildSetup();
      default:
        return _buildSplash();
    }
  }

  Widget _buildSplash() {
    final logo = math.min(150.0, MediaQuery.sizeOf(context).width * 0.36);
    return Container(
      color: const Color(0xFF03060A),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: StarryCloudPainter(_clouds, _stars)),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (ctx, c) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: logo,
                          height: logo,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.asset('assets/logo.png',
                                  width: logo,
                                  height: logo,
                                  fit: BoxFit.contain,
                                  color: Colors.white,
                                  colorBlendMode: BlendMode.srcIn),
                              SizedBox(
                                width: logo,
                                height: logo,
                                child: CircularProgressIndicator(
                                  value: _progress > 0 ? _progress : null,
                                  strokeWidth: 3.0,
                                  backgroundColor: Colors.white12,
                                  color: const Color(0xFF00FFCC),
                                  strokeAlign: CircularProgressIndicator
                                      .strokeAlignCenter,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        _CenterText(_status,
                            style: const TextStyle(
                              fontSize: 14.0,
                              color: Color(0xFF00FFCC),
                              fontWeight: FontWeight.bold,
                            )),
                        if (_downloading) ...[
                          const SizedBox(height: 10),
                          _CenterText(
                              _curName.isEmpty
                                  ? ""
                                  : "$_curName · ${_speed.isEmpty ? "连接中..." : _speed}",
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 13)),
                        ],
                        if (_failed) ...[
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: _bootstrap,
                            child: const Text("重试",
                                style: TextStyle(color: Color(0xFF00FFCC))),
                          ),
                          TextButton(
                            onPressed: _switchToWeb,
                            child: const Text("用网页版打开",
                                style: TextStyle(color: Colors.white54)),
                          ),
                        ],
                        if (_downloading || _failed) ...[
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _showSourceSheet,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0x4400FFCC)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              minimumSize: const Size(120, 40),
                            ),
                            child: const Text("换源",
                                style: TextStyle(
                                    color: Color(0xFF00FFCC), fontSize: 14)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
    return Container(
      color: const Color(0xFF03060A),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: StarryCloudPainter(_clouds, _stars)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.vpn_key_outlined,
                        size: 44, color: Color(0xFF00FFCC)),
                    const SizedBox(height: 20),
                    _CenterText("第一次使用，需要填一下模型信息",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            height: 1.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    _CenterText("API Key 只保存在本机，不会上传",
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12, height: 1.5)),
                    const SizedBox(height: 30),
                    TextField(
                      controller: _keyCtrl,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: "DeepSeek API Key",
                        hintText: "sk-…",
                        labelStyle:
                            TextStyle(color: Color(0x99FFFFFF), fontSize: 13),
                        hintStyle:
                            TextStyle(color: Color(0x44FFFFFF), fontSize: 13),
                        filled: true,
                        fillColor: Color(0xFF0E141B),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        enabledBorder: fieldBorder,
                        focusedBorder: OutlineInputBorder(
                          borderRadius: radius,
                          borderSide: BorderSide(color: Color(0x9900FFCC)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E141B),
                        borderRadius: radius,
                        border: Border.all(color: const Color(0x22FFFFFF)),
                      ),
                      child: Row(
                        children: [
                          _LeftText("模型",
                              style: const TextStyle(
                                  color: Color(0x99FFFFFF), fontSize: 13)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: currentModel,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF0E141B),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
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
                    ),
                    const SizedBox(height: 10),
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
                                  size: 16, color: Color(0xFF00FFCC)),
                          label: const Text("测试连接",
                              style: TextStyle(
                                  color: Color(0xFF00FFCC), fontSize: 13)),
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
                    const SizedBox(height: 14),
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
                        child: const Text("保存并启动",
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _switchToWeb,
                      child: const Text("先用网页版",
                          style:
                              TextStyle(color: Colors.white38, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 直接打 DeepSeek 的模型列表接口，验证 Key 是否有效
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

  Widget _buildChat() {
    return Container(
      color: const Color(0xFF03060A),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  const Text("原生 DSH",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    tooltip: "网页版",
                    onPressed: _switchToWeb,
                    icon: const Icon(Icons.public,
                        size: 20, color: Color(0xFF00FFCC)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _msgs.length + (_streamText.isNotEmpty ? 1 : 0),
                itemBuilder: (ctx, i) {
                  final isStream = i == _msgs.length;
                  final text = isStream ? _streamText : _msgs[i].text;
                  final mine = isStream ? false : _msgs[i].mine;
                  return Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      constraints: const BoxConstraints(maxWidth: 560),
                      decoration: BoxDecoration(
                        color: mine
                            ? const Color(0xFF14524A)
                            : const Color(0xFF141A22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(text,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14, height: 1.4)),
                    ),
                  );
                },
              ),
            ),
            if (_sending)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00FFCC))),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: const TextStyle(color: Colors.white),
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: "说点什么…",
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: Icon(Icons.send,
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
    );
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
                    _webButton(Icons.refresh, () => web.reload()),
                    const SizedBox(width: 8),
                    _webButton(Icons.open_in_browser, () async {
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
}

/// 换源面板：自己定时重绘，这样测速结果能边测边显示
class _SourceSheet extends StatefulWidget {
  final _AppRootState host;
  const _SourceSheet(this.host);

  @override
  State<_SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<_SourceSheet> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.host.buildSourceSheetContent(context);
}

/// 左对齐的自绘文字（避免系统给 Text 画下划线）
class _LeftText extends StatelessWidget {
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

/// 不用 Text 组件画状态文字，避免系统乱画下划线
class _CenterText extends StatelessWidget {
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
