import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;

void main() => runApp(const MyApp());

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
  String _status = "首次启动，正在下载核心环境(847MB)...";
  double _progress = 0.0;
  bool _isReady = false;
  static const platform = MethodChannel('com.dsh.dshapp/status');
  
  late AnimationController _weatherController;
  bool _isLightningStriking = false;
  Timer? _lightningTimer;
  final math.Random _random = math.Random();
  
  List<RainDrop> _raindrops = [];
  List<Splash> _splashes = [];

  // 🚨 统一尺寸配置：想放大缩小直接改这一个数就行
  final double logoSize = 160.0; 

  @override
  void initState() {
    super.initState();
    _weatherController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _weatherController.addListener(_updateParticles);
    
    _initRain();
    _startLightningLoop();

    platform.setMethodCallHandler((call) async {
      if (call.method == 'updateStatus') setState(() => _status = call.arguments);
      if (call.method == 'updateProgress') setState(() => _progress = (call.arguments as num).toDouble());
      if (call.method == 'ready') setState(() => _isReady = true);
    });
    
    _start();
  }

  void _initRain() {
    for (int i = 0; i < 80; i++) { 
      int layer = _random.nextInt(3);
      _raindrops.add(RainDrop(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: layer == 2 ? 1.5 + _random.nextDouble() : (layer == 1 ? 0.8 : 0.4),
        length: layer == 2 ? 30.0 : (layer == 1 ? 15.0 : 8.0),
        thickness: layer == 2 ? 1.5 : (layer == 1 ? 1.0 : 0.5),
        opacity: layer == 2 ? 0.4 : (layer == 1 ? 0.2 : 0.1),
        windOffset: -0.15,
      ));
    }
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (var drop in _raindrops) {
        drop.y += drop.speed * 0.01;
        drop.x += drop.windOffset * 0.01;
        
        if (drop.y > 1.0 || drop.x < 0) {
          if (_splashes.length < 10 && drop.thickness >= 1.0) {
            _splashes.add(Splash(x: drop.x, y: 0.92));
          }
          drop.y = 0;
          drop.x = _random.nextDouble() + 0.2;
        }
      }
      _splashes.removeWhere((splash) => splash.life <= 0);
      for (var splash in _splashes) {
        splash.life -= 0.04; 
      }
    });
  }

  void _startLightningLoop() {
    int randomDelay = 3000 + _random.nextInt(4000); 
    _lightningTimer = Timer(Duration(milliseconds: randomDelay), () {
      if (mounted) {
        setState(() => _isLightningStriking = true);
        Future.delayed(const Duration(milliseconds: 80), () {
          if (mounted) {
            setState(() => _isLightningStriking = false);
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) {
                setState(() => _isLightningStriking = true);
                Future.delayed(const Duration(milliseconds: 120), () {
                  if (mounted) {
                    setState(() => _isLightningStriking = false);
                    _startLightningLoop();
                  }
                });
              }
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _lightningTimer?.cancel();
    _weatherController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final envFile = File('${Directory.systemTemp.path}/env_data.zip');
    if (await envFile.exists()) {
      try { envFile.deleteSync(); } catch(e) {}
    }

    try {
      String url = 'https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip';
      var request = http.Request('GET', Uri.parse(url));
      var response = await http.Client().send(request);
      var contentLength = response.contentLength ?? 0;
      var received = 0;
      var sink = envFile.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) setState(() => _progress = received / contentLength);
      }).asFuture();

      await sink.close();
      setState(() => _status = "下载完成，正在解压...");
      platform.invokeMethod('startExtract', {'path': envFile.path});
    } catch (e) {
      setState(() => _status = "下载失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070A),
      appBar: AppBar(
        title: const Text('原生 DSH'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: !_isReady
          ? Stack(
              children: [
                // 1. 底层：暴雨粒子
                Positioned.fill(
                  child: CustomPaint(
                    painter: RainPainter(_raindrops, _splashes),
                  ),
                ),

                // 2. 中层：落锤、倒影与进度圈
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 🚨 核心修复：图片和进度圈用一个完全相同的 SizedBox 包裹
                      SizedBox(
                        width: logoSize,
                        height: logoSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 落锤图片，铺满整个正方形
                            Image.asset(
                              'assets/logo.png',
                              width: logoSize,
                              height: logoSize,
                              fit: BoxFit.contain,
                              color: _isLightningStriking ? Colors.white : Colors.white70,
                              colorBlendMode: BlendMode.srcIn,
                            ),
                            // 进度圈，也用相同的大小，并让描边居中对齐
                            SizedBox(
                              width: logoSize,
                              height: logoSize,
                              child: CircularProgressIndicator(
                                value: _progress > 0 ? _progress : null,
                                strokeWidth: 3.0, // 稍微加粗一点
                                backgroundColor: Colors.transparent, // 去掉底色轨道
                                color: const Color(0xFF00FFCC),
                                strokeAlign: CircularProgressIndicator.strokeAlignCenter, // 让线居中压在图片边缘
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // 倒影
                      Transform(
                        transform: Matrix4.identity()
                          ..scale(1.0, -0.5) 
                          ..translate(0.0, -logoSize * 0.8), // 根据尺寸动态调整位移
                        alignment: Alignment.topCenter,
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0), 
                          child: Opacity(
                            opacity: 0.08, 
                            child: Image.asset(
                              'assets/logo.png',
                              width: logoSize, // 倒影大小和原图一致
                              height: logoSize,
                              fit: BoxFit.contain,
                              color: const Color(0xFF00FFCC), 
                              colorBlendMode: BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. 顶层：闪电
                if (_isLightningStriking)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: RealLightningPainter(random: _random),
                      ),
                    ),
                  ),

                // 底部文字
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 60.0),
                    child: Text(
                      _status,
                      style: const TextStyle(fontSize: 14.0, color: Color(0xFF00FFCC), fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: Text("引擎就绪", style: TextStyle(color: Colors.white))),
    );
  }
}

// ================== 以下为粒子系统与画笔 ==================

class RainDrop {
  double x, y, speed, length, thickness, opacity, windOffset;
  RainDrop({
    required this.x, required this.y, required this.speed, 
    required this.length, required this.thickness, required this.opacity, required this.windOffset
  });
}

class Splash {
  double x, y, life;
  Splash({required this.x, required this.y}) : life = 1.0;
}

class RainPainter extends CustomPainter {
  final List<RainDrop> drops;
  final List<Splash> splashes;
  RainPainter(this.drops, this.splashes);

  @override
  void paint(Canvas canvas, Size size) {
    for (var drop in drops) {
      final paint = Paint()
        ..color = Colors.white.withOpacity(drop.opacity)
        ..strokeWidth = drop.thickness
        ..strokeCap = StrokeCap.round;
      
      if (drop.thickness == 1.5) {
        paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8);
      }

      final startX = drop.x * size.width;
      final startY = drop.y * size.height;
      final endX = startX - (drop.length * drop.windOffset);
      final endY = startY + drop.length;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }

    for (var splash in splashes) {
      final splashPaint = Paint()
        ..color = Colors.white.withOpacity(splash.life * 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      
      double radius = (1.0 - splash.life) * 15; 
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(splash.x * size.width, splash.y * size.height),
          width: radius * 2.0,
          height: radius * 0.5, 
        ),
        splashPaint
      );
    }
  }
  @override
  bool shouldRepaint(covariant RainPainter oldDelegate) => true;
}

class RealLightningPainter extends CustomPainter {
  final math.Random random;
  RealLightningPainter({required this.random});

  @override
  void paint(Canvas canvas, Size size) {
    final flashPaint = Paint()..color = Colors.white.withOpacity(0.08);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flashPaint);

    final startX = random.nextDouble() * size.width;
    final endY = size.height * (0.2 + random.nextDouble() * 0.6);

    final boltPaint = Paint()
      ..color = const Color(0xFFF0F8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.miter;

    final glowPaint = Paint()
      ..color = const Color(0xFF00FFCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);

    _drawBolt(canvas, Offset(startX, 0), endY, boltPaint, glowPaint, 0);
  }

  void _drawBolt(Canvas canvas, Offset start, double endY, Paint bolt, Paint glow, int depth) {
    if (depth > 2) return;

    final path = Path()..moveTo(start.dx, start.dy);
    double currentX = start.dx;
    double currentY = start.dy;

    while (currentY < endY) {
      currentY += 15 + random.nextDouble() * 20;
      if (currentY > endY) currentY = endY;
      currentX += (random.nextDouble() - 0.5) * (depth == 0 ? 40 : 20);
      path.lineTo(currentX, currentY);

      if (random.nextDouble() > 0.8 && depth < 2) {
        _drawBolt(canvas, Offset(currentX, currentY), currentY + 60, bolt, glow, depth + 1);
      }
    }

    canvas.drawPath(path, glow);
    canvas.drawPath(path, bolt);
  }

  @override
  bool shouldRepaint(covariant RealLightningPainter oldDelegate) => true;
}
