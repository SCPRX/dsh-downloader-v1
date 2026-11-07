import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
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
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// 手动换源时用来打断正在进行的下载
class _SourceCancelled implements Exception {
  final String message;
  _SourceCancelled(this.message);
  @override
  String toString() => message;
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  static const MethodChannel _platform = MethodChannel('com.dsh.dshapp/status');

  /// 下载源按顺序尝试。某个源挂了/太慢会自动跳过；
  /// 以后自己传了 OSS/R2 直接把地址放第一位。
  static const List<String> _envUrls = [
    'https://gh-proxy.com/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://ghfast.top/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://ghproxy.net/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
  ];

  /// 界面上显示的名字，和上面的地址一一对应
  static const List<String> _envNames = [
    '极速镜像',
    '高速镜像',
    '备用镜像',
    '官方源',
  ];

  String _status = "正在检查环境...";
  double _progress = 0.0;
  bool _isReady = false;
  bool _failed = false;
  bool _busy = false;
  bool _downloading = false;
  String _speed = "";
  String _curName = "";

  int? _pinnedSrc; // null = 自动按顺序找源；点按钮后固定用那一个
  int _runId = 0; // 手动换源时 +1，打断正在进行的下载
  final Map<int, String> _srcInfo = {}; // 每个源最近的状态/速度

  late AnimationController _bgController;
  final math.Random _random = math.Random();
  DateTime _lastProgressPaint = DateTime.fromMillisecondsSinceEpoch(0);

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

    _platform.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'updateStatus':
          setState(() => _status = call.arguments as String);
          break;
        case 'updateProgress':
          setState(() => _progress = (call.arguments as num).toDouble());
          break;
        case 'ready':
          setState(() {
            _isReady = true;
            _failed = false;
            _progress = 1.0;
            _status = "引擎已就绪";
          });
          break;
        case 'failed':
          setState(() {
            _failed = true;
            _status = call.arguments as String;
          });
          break;
      }
    });
    _start();
  }

  CloudParticle _spawnCloud() {
    return CloudParticle(
      x: _random.nextBool() ? -0.6 : 1.6,
      y: _random.nextDouble() * 0.8 + 0.1,
      radius: 0.25 + _random.nextDouble() * 0.2,
      opacity: 0.15 + _random.nextDouble() * 0.15,
      vx: (_random.nextBool() ? 1 : -1) * (0.0005 + _random.nextDouble() * 0.0005),
    );
  }

  StarParticle _spawnStar() {
    return StarParticle(
      x: _random.nextDouble(),
      y: _random.nextDouble(),
      radius: 0.5 + _random.nextDouble() * 1.2,
      maxLife: 100 + _random.nextDouble() * 200,
      life: 0,
    );
  }

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
    super.dispose();
  }

  // ---------------- 启动流程 ----------------

  Future<void> _start() async {
    if (_busy) return;
    _busy = true;
    setState(() {
      _failed = false;
      _isReady = false;
      _progress = 0.0;
      _status = "正在检查环境...";
    });

    try {
      final bool installed =
          await _platform.invokeMethod<bool>('checkEnv') ?? false;

      if (installed) {
        setState(() {
          _progress = 1.0;
          _status = "环境已安装，正在启动引擎...";
        });
        await _platform.invokeMethod('startServer');
        return;
      }

      final String? zipPath = await _platform.invokeMethod<String>('envZipPath');
      if (zipPath == null || zipPath.isEmpty) {
        throw '拿不到安装包路径';
      }
      // 一进来就后台探测各源速度，把「换源」列表填满
      if (_srcInfo.isEmpty) unawaited(_testSources());
      await _download(zipPath);
      setState(() {
        _progress = 1.0;
        _status = "下载完成，正在解压(耗时较长)...";
      });
      await _platform.invokeMethod('startExtract', {'path': zipPath});
    } on _SourceCancelled {
      // 手动换源：被打断后按新选的源自动重启
      setState(() {
        _failed = false;
        _speed = "";
        _status = _pinnedSrc != null
            ? "切换到 ${_envNames[_pinnedSrc!]} 下载..."
            : "恢复自动找源...";
      });
      _busy = false;
      Future(() => _start());
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _status = "启动失败: $e";
      });
    } finally {
      _busy = false;
    }
  }

  /// 多源 + 断点续传下载：源挂了/太慢自动换下一个，断了重进会接着下。
  Future<void> _download(String zipPath) async {
    final zip = File(zipPath);
    final part = File('$zipPath.part');

    // 上次已经下完、只是解压失败：直接用，不再重下
    if (await zip.exists() && await zip.length() > 1024) {
      final head = await zip.openRead(0, 2).first;
      if (head.length == 2 && head[0] == 0x50 && head[1] == 0x4B) {
        setState(() => _progress = 1.0);
        return;
      }
      await zip.delete();
    }

    int start = 0;
    if (await part.exists()) {
      start = await part.length();
    }

    setState(() {
      _status = start > 0
          ? "继续下载核心环境（已有 ${_mb(start)}）..."
          : "首次启动，正在下载核心环境(约 850MB)...";
    });

    final runId = _runId;
    final order = _pinnedSrc != null
        ? <int>[_pinnedSrc!]
        : <int>[for (int i = 0; i < _envUrls.length; i++) i];

    Object? lastError;
    _downloading = true;
    try {
      for (final i in order) {
        if (runId != _runId) {
          lastError = _SourceCancelled('换源');
          break;
        }
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
          if (e is _SourceCancelled) break;
          _srcInfo[i] = _srcReason(e);
          if (await part.exists()) start = await part.length();
          final next = order.indexOf(i) + 1;
          if (next < order.length && mounted) {
            setState(() =>
                _status = "${_envNames[i]} 不行（${_srcReason(e)}），换 ${_envNames[order[next]]}...");
          }
        }
      }
      if (lastError != null) throw lastError;

      // 简单校验：zip 头是 PK
      final bool partOk = await part.exists() && await part.length() >= 1024;
      if (!partOk) {
        throw '下载文件不存在或不完整';
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

  /// 从一个源下载；成功返回，失败抛异常（.part 保留，供续传/换源）。
  Future<void> _downloadFrom(int index, int runId, File part,
      {required int start}) async {
    final url = _envUrls[index];
    final name = _envNames[index];
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      if (start > 0) req.headers['range'] = 'bytes=$start-';
      final resp = await client.send(req).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 416 && start > 0) {
        return; // 已经下完了
      }
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw '下载失败: HTTP ${resp.statusCode}';
      }

      int totalBytes = 0;
      IOSink sink;
      int received = start;
      if (resp.statusCode == 206) {
        totalBytes = _totalFromRange(resp.headers['content-range']) ??
            (resp.contentLength ?? 0) + start;
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
          // 手动换源 → 立刻打断
          if (runId != _runId) {
            sub.cancel();
            if (!done.isCompleted) {
              done.completeError(_SourceCancelled('换源'));
            }
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
              _curName = name;
              _srcInfo[index] = _speed;
              _status = "下载中 ${_mb(received)} / ${_mb(totalBytes)}";
            });
          }

          // 20 秒后仍低于 50KB/s = 源太慢，放弃换下一个（已下的会保留续传）
          if (ms > 20000 && bps < 50 * 1024 && !done.isCompleted) {
            sub.cancel();
            done.completeError(
                Exception('该源太慢（${_speedText(bps)}），换下一个'));
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

      if (totalBytes > 0 && received < totalBytes) {
        throw '下载不完整（${_mb(received)} / ${_mb(totalBytes)}），重试会接着下';
      }
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

  String _srcReason(Object e) {
    final s = e.toString();
    if (e is _SourceCancelled) return "已取消";
    if (s.contains("太慢")) return "太慢";
    if (s.contains("HTTP")) return "连不上";
    return "失败";
  }

  // ---------------- 源测速 ----------------

  /// 对每个源做一次小流量探速（只拉 256KB），把结果填进换源列表
  Future<void> _testSources({VoidCallback? onUpdate}) async {
    for (int i = 0; i < _envUrls.length; i++) {
      if (mounted) setState(() => _srcInfo[i] = "测试中...");
      onUpdate?.call();
      final res = await _probeSource(i);
      if (mounted) setState(() => _srcInfo[i] = res);
      onUpdate?.call();
    }
  }

  Future<String> _probeSource(int i) async {
    final client = http.Client();
    try {
      final sw = Stopwatch()..start();
      final req = http.Request('GET', Uri.parse(_envUrls[i]));
      req.headers['range'] = 'bytes=0-262143';
      final resp = await client.send(req).timeout(const Duration(seconds: 10));
      final code = resp.statusCode;
      int got = 0;
      try {
        await for (final chunk
            in resp.stream.timeout(const Duration(seconds: 10))) {
          got += chunk.length;
          if (got >= 262144) break;
        }
      } catch (_) {
        // 超时/中断：下面按 got 的大小判断
      }
      if (code != 200 && code != 206) return "失败";
      if (got < 1024) return "连不上";
      final bps = got * 1000 ~/ math.max(sw.elapsedMilliseconds, 1);
      return "≈${_speedText(bps)}";
    } catch (_) {
      return "连不上";
    } finally {
      client.close();
    }
  }

  // ---------------- 手动换源 ----------------

  void _setAuto() {
    if (_isReady) return;
    if (!_downloading && !_failed) return;
    _pinnedSrc = null;
    _runId++;
    setState(() {
      _failed = false;
      _status = "恢复自动找源...";
    });
    if (!_downloading) _start();
  }

  void _switchSource(int i) {
    if (_isReady) return;
    if (!_downloading && !_failed) return;
    _pinnedSrc = i;
    _runId++;
    setState(() {
      _failed = false;
      _status = "切换到 ${_envNames[i]} 下载...";
    });
    if (!_downloading) _start();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF03060A),
      child: _isReady ? _buildReady() : _buildSplash(context),
    );
  }

  Widget _buildReady() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (ctx, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 96, color: Color(0xFF00FFCC)),
                  const SizedBox(height: 24),
                  _NoSemText("引擎已就绪",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _NoSemText("http://127.0.0.1:3080",
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 28),
                  OutlinedButton(
                    onPressed: () => _platform.invokeMethod('openEngine'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0x4400FFCC)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      minimumSize: const Size(160, 42),
                    ),
                    child: const Text("在浏览器打开",
                        style: TextStyle(
                            color: Color(0xFF00FFCC), fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplash(BuildContext context) {
    // logo 按屏幕宽度自适应；整体居中，小屏自动变成可滚动，不会溢出
    final logo = math.min(150.0, MediaQuery.sizeOf(context).width * 0.36);
    return Stack(
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
                      _NoSemText(_status,
                          style: const TextStyle(
                            fontSize: 14.0,
                            color: Color(0xFF00FFCC),
                            fontWeight: FontWeight.bold,
                          )),
                      if (_failed) ...[
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: _start,
                          child: const Text("重试",
                              style: TextStyle(color: Color(0xFF00FFCC))),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _NoSemText(
                          _curName.isEmpty
                              ? ""
                              : "$_curName · ${_speed.isEmpty ? "连接中..." : _speed}",
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13)),
                      const SizedBox(height: 18),
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
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 底部弹出的换源面板：每个源一行，显示最近状态，点一下立即切换
  void _showSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("选择下载源（点一下立即切换）",
                              style:
                                  TextStyle(color: Colors.white, fontSize: 15)),
                          TextButton.icon(
                            onPressed: () =>
                                _testSources(onUpdate: () => setSheet(() {})),
                            icon: const Icon(Icons.refresh,
                                size: 16, color: Color(0xFF00FFCC)),
                            label: const Text("重新测速",
                                style: TextStyle(
                                    color: Color(0xFF00FFCC), fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      leading: const SizedBox(
                          width: 24,
                          child: Icon(Icons.autorenew,
                              size: 20, color: Color(0xFF00FFCC))),
                      title: const Text("自动",
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text("按顺序自动找最快的源",
                          style: TextStyle(color: Colors.white38, fontSize: 12)),
                      trailing: _pinnedSrc == null
                          ? const Icon(Icons.check_circle,
                              color: Color(0xFF00FFCC))
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _setAuto();
                      },
                    ),
                    for (int i = 0; i < _envNames.length; i++)
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        leading: const SizedBox(
                            width: 24,
                            child: Icon(Icons.link,
                                size: 20,
                                color: Color(0xCC00FFCC))),
                        title: Text(_envNames[i],
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(_srcSubtitle(i),
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                        trailing: _pinnedSrc == i
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
          },
        );
      },
    );
  }

  String _srcSubtitle(int i) {
    final info = _srcInfo[i];
    return (info == null || info.isEmpty) ? "未测" : info;
  }
}

/// 不用 Text 组件、而是自己画出来的纯文字：
/// 没有语义节点、没有拼写检查、没有任何下划线装饰，屏幕上不会被系统画黄线。
class _NoSemText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _NoSemText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: 3,
          ellipsis: '…',
        )..layout(maxWidth: c.maxWidth);
        return CustomPaint(
          size: Size(c.maxWidth, tp.height),
          painter: _TextDrawPainter(text, style),
        );
      },
    );
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
    )..layout(maxWidth: size.width);
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
      canvas.drawCircle(
          Offset(star.x * size.width, star.y * size.height), star.radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StarryCloudPainter oldDelegate) => true;
}
