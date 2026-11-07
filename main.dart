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

  /// 下载源按顺序尝试（实测：gh-proxy ~10MB/s；ghfast ~670KB/s；GitHub ~30KB/s 且要梯子）。
  /// 某个源挂了/太慢会自动跳过；以后自己传了 OSS/R2 直接排在第一位。
  static const List<String> _envUrls = [
    'https://gh-proxy.com/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://ghfast.top/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://mirror.ghproxy.com/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
  ];

  /// 按钮上显示的名字，和上面的地址一一对应
  static const List<String> _envNames = [
    'gh-proxy',
    'ghfast',
    'ghproxy镜像',
    'GitHub',
  ];

  String _status = "正在检查环境...";
  double _progress = 0.0;
  bool _isReady = false;
  bool _failed = false;
  bool _busy = false;
  bool _downloading = false;
  String _speed = "";

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
        setState(() => _speed = "");
        try {
          await _downloadFrom(i, runId, part, start: start);
          lastError = null;
          _srcInfo[i] = "✓";
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
              _srcInfo[index] = _speed;
              _status =
                  "下载中 ${_mb(received)} / ${_mb(totalBytes)}（$name）";
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
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 96, color: Color(0xFF00FFCC)),
              const SizedBox(height: 24),
              const Text("引擎已就绪",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("http://127.0.0.1:3080",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
              const SizedBox(height: 28),
              TextButton.icon(
                onPressed: () => _platform.invokeMethod('openEngine'),
                icon: const Icon(Icons.open_in_browser,
                    color: Color(0xFF00FFCC), size: 18),
                label: const Text("在浏览器打开",
                    style: TextStyle(color: Color(0xFF00FFCC))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSplash(BuildContext context) {
    // 按屏幕宽度自适应，保证不同尺寸手机上 logo 和文字都居中不越界
    final logo = math.min(160.0, MediaQuery.sizeOf(context).width * 0.4);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: StarryCloudPainter(_clouds, _stars)),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
                            strokeAlign:
                                CircularProgressIndicator.strokeAlignCenter,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  ExcludeSemantics(
                    child: Text(
                      _status,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.0,
                        color: Color(0xFF00FFCC),
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                        decorationColor: Colors.transparent,
                      ),
                    ),
                  ),
                  if (_failed) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _start,
                      child: const Text("重试",
                          style: TextStyle(color: Color(0xFF00FFCC))),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // 下载源手动切换：点一下换一个源，「自动」恢复按顺序找
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _srcChip(-1),
                      for (int i = 0; i < _envNames.length; i++) _srcChip(i),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _srcChip(int i) {
    final isAuto = i == -1;
    final bool selected = isAuto ? _pinnedSrc == null : _pinnedSrc == i;
    final String label;
    if (isAuto) {
      label = "自动";
    } else {
      final info = _srcInfo[i];
      label = _envNames[i] + (info == null || info.isEmpty ? "" : " $info");
    }
    return ActionChip(
      onPressed: isAuto ? _setAuto : () => _switchSource(i),
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: selected ? Colors.black : const Color(0xFF00FFCC))),
      backgroundColor: selected ? const Color(0xFF00FFCC) : Colors.white10,
      side: BorderSide(
          color: selected ? const Color(0xFF00FFCC) : Colors.white24),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    );
  }
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
