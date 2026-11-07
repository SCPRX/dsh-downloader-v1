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

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  static const MethodChannel _platform = MethodChannel('com.dsh.dshapp/status');

  /// 下载源按顺序尝试：主源是 GitHub，后面是 ghproxy 类镜像（国内可直连）。
  /// 某个源挂了就把那一行换掉或删掉；以后自己传了 OSS/R2 直接排在第一位。
  static const List<String> _envUrls = [
    'https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://ghfast.top/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://gh-proxy.com/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
    'https://mirror.ghproxy.com/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip',
  ];

  String _status = "正在检查环境...";
  double _progress = 0.0;
  bool _isReady = false;
  bool _failed = false;
  bool _busy = false;

  late AnimationController _bgController;
  final double logoSize = 160.0;
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

  /// 多源 + 断点续传下载：源挂了自动换下一个，断了重进会接着下。
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

    Object? lastError;
    for (int i = 0; i < _envUrls.length; i++) {
      try {
        await _downloadFrom(_envUrls[i], i + 1, _envUrls.length, part,
            start: start);
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        if (await part.exists()) start = await part.length();
        if (i + 1 < _envUrls.length && mounted) {
          setState(() => _status = "源 ${i + 1} 失败，换第 ${i + 2} 个源继续...");
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
  }

  /// 从一个源下载；成功返回，失败抛异常（.part 保留，供续传/换源）。
  Future<void> _downloadFrom(
      String url, int index, int total, File part, {required int start}) async {
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
      final sub = resp.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (totalBytes > 0 &&
              now.difference(_lastProgressPaint).inMilliseconds > 250 &&
              mounted) {
            _lastProgressPaint = now;
            setState(() {
              _progress = (received / totalBytes).clamp(0.0, 1.0).toDouble();
              _status =
                  "下载中 ${_mb(received)} / ${_mb(totalBytes)}（源 $index/$total）";
            });
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

      await done.future;
      await sub.cancel();
      await sink.close();

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

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF03060A),
      child: _isReady ? _buildReady() : _buildSplash(),
    );
  }

  Widget _buildReady() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 96, color: Color(0xFF00FFCC)),
          const SizedBox(height: 24),
          const Text("引擎已就绪",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("http://127.0.0.1:3080",
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
    );
  }

  Widget _buildSplash() {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: StarryCloudPainter(_clouds, _stars)),
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: logoSize,
                height: logoSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset('assets/logo.png',
                        width: logoSize,
                        height: logoSize,
                        fit: BoxFit.contain,
                        color: Colors.white,
                        colorBlendMode: BlendMode.srcIn),
                    SizedBox(
                      width: logoSize,
                      height: logoSize,
                      child: CircularProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        strokeWidth: 3.0,
                        backgroundColor: Colors.white12,
                        color: const Color(0xFF00FFCC),
                        strokeAlign: CircularProgressIndicator.strokeAlignCenter,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              ExcludeSemantics(
                child: Text(
                  _status,
                  textAlign: TextAlign.center,
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
                const SizedBox(height: 20),
                TextButton(
                  onPressed: _start,
                  child: const Text("重试",
                      style: TextStyle(color: Color(0xFF00FFCC))),
                ),
              ],
            ],
          ),
        ),
      ],
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
