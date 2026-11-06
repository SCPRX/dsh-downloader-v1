import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:async';

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
    
    // 模拟初始化
    _start();
  }

  void _initRain() {
    for (int i = 0; i < 100; i++) {
      // 随机生成三层雨滴，营造景深感
      int layer = _random.nextInt(3); // 0: 远景, 1: 中景, 2: 近景
      _raindrops.add(RainDrop(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: layer == 2 ? 2.5 + _random.nextDouble() : (layer == 1 ? 1.5 : 0.8),
        length: layer == 2 ? 40.0 : (layer == 1 ? 20.0 : 10.0),
        thickness: layer == 2 ? 2.0 : (layer == 1 ? 1.0 : 0.5),
        opacity: layer == 2 ? 0.6 : (layer == 1 ? 0.3 : 0.1),
        windOffset: -0.2, // 风的倾斜度
      ));
    }
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (var drop in _raindrops) {
        drop.y += drop.speed * 0.02;
        drop.x += drop.windOffset * 0.02; // 受风影响
        if (drop.y > 1.0 || drop.x < 0) {
          // 落地，生成水花
          if (_splashes.length < 30 && drop.speed > 1.5) {
            _splashes.add(Splash(x: drop.x, y: 0.95));
          }
          drop.y = 0;
          drop.x = _random.nextDouble() + 0.2; // 重新从偏右上方落下
        }
      }
      
      // 更新水花
      _splashes.removeWhere((splash) => splash.life <= 0);
      for (var splash in _splashes) {
        splash.life -= 0.05; // 消散
      }
    });
  }

  void _startLightningLoop() {
    int randomDelay = 1500 + _random.nextInt(4000);
    _lightningTimer = Timer(Duration(milliseconds: randomDelay), () {
      if (mounted) {
        setState(() => _isLightningStriking = true);
        // 真实闪电会有连续闪烁 (双闪)
        Future.delayed(const Duration(milliseconds: 80), () {
          if (mounted) {
            setState(() => _isLightningStriking = false);
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) {
                setState(() => _isLightningStriking = true);
                Future.delayed(const Duration(milliseconds: 100), () {
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
    // 真实的下载逻辑不变
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070A), // 暴风雨夜空底色
      appBar: AppBar(
        title: const Text('原生 DSH'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: !_isReady
          ? Stack(
              children: [
                // 1. 底层：落锤与积水倒影
                Positioned.fill(
                  child: CustomPaint(
                    painter: GroundReflectionPainter(
                      progress: _progress,
                      isStriking: _isLightningStriking,
                    ),
                  ),
                ),

                // 2. 中层：暴雨粒子
                Positioned.fill(
                  child: CustomPaint(
                    painter: RainPainter(_raindrops, _splashes),
                  ),
                ),

                // 3. 顶层：全屏闪电与屏幕爆闪
                if (_isLightningStriking)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: RealLightningPainter(random: _random),
                      ),
                    ),
                  ),

                // UI 文字
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 60.0),
                    child: Text(
                      _status,
                      style: const TextStyle(fontSize: 16.0, color: Color(0xFF00FFCC), fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: Text("引擎就绪", style: TextStyle(color: Colors.white))),
    );
  }
}

// 💧 雨滴类 (加入景深参数)
class RainDrop {
  double x, y, speed, length, thickness, opacity, windOffset;
  RainDrop({
    required this.x, required this.y, required this.speed, 
    required this.length, required this.thickness, required this.opacity, required this.windOffset
  });
}

// 💦 水花类
class Splash {
  double x, y, life;
  Splash({required this.x, required this.y}) : life = 1.0;
}

// 🌧️ 真实暴雨画笔
class RainPainter extends CustomPainter {
  final List<RainDrop> drops;
  final List<Splash> splashes;
  RainPainter(this.drops, this.splashes);

  @override
  void paint(Canvas canvas, Size size) {
    // 画雨滴
    for (var drop in drops) {
      final paint = Paint()
        ..color = Colors.white.withOpacity(drop.opacity)
        ..strokeWidth = drop.thickness
        ..strokeCap = StrokeCap.round;
      
      // 只有近景的雨滴加模糊，模拟真实镜头景深
      if (drop.thickness == 2.0) {
        paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);
      }

      final startX = drop.x * size.width;
      final startY = drop.y * size.height;
      // 根据风偏计算终点
      final endX = startX - (drop.length * drop.windOffset);
      final endY = startY + drop.length;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }

    // 画水花/涟漪
    for (var splash in splashes) {
      final splashPaint = Paint()
        ..color = Colors.white.withOpacity(splash.life * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      
      // 水花砸地的椭圆涟漪，迅速扩大并消散
      double radius = (1.0 - splash.life) * 30;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(splash.x * size.width, splash.y * size.height),
          width: radius * 2.5,
          height: radius * 0.8, // 压扁，模拟地面视角
        ),
        splashPaint
      );
    }
  }
  @override
  bool shouldRepaint(covariant RainPainter oldDelegate) => true;
}

// 🪞 湿滑地面与落锤倒影
class GroundReflectionPainter extends CustomPainter {
  final double progress;
  final bool isStriking;
  GroundReflectionPainter({required this.progress, required this.isStriking});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 20);

    // 1. 地面湿滑反光（落锤下方的一滩积水）
    final puddlePaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.cyanAccent.withOpacity(0.15), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(center.dx, size.height * 0.8), radius: 150));
    canvas.drawCircle(Offset(center.dx, size.height * 0.8), 150, puddlePaint);

    // 2. 倒影 (通过翻转画布和透明度实现)
    canvas.save();
    canvas.translate(0, size.height * 0.8); // 移到水面位置
    canvas.scale(1.0, -0.6); // Y轴翻转并按比例压缩，产生透视感
    final opacity = isStriking ? 1.0 : 0.2;
    
    // 画倒影中的落锤
    final logoPaint = Paint()
      ..color = Colors.white.withOpacity(opacity * 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
    // 注意：这里用一张带圆形的底色模拟倒影，实际中可以用 Image.asset
    canvas.drawCircle(Offset(0, -120), 70, logoPaint); 
    canvas.restore();

    // 3. 画真实的落锤
    final logoColor = isStriking ? Colors.white : const Color(0xFFAAAAAA);
    final logoPaint = Paint()
      ..color = logoColor
      ..maskFilter = isStriking ? const MaskFilter.blur(BlurStyle.normal, 10.0) : null;
    // (为了代码简洁，落锤这里用圆圈代替，你的实际代码里应该用 Image.asset('assets/logo.png'))
    canvas.drawCircle(center, 70, logoPaint);
    
    // 画进度圈
    final trackPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(center, 90, trackPaint);

    final progressPaint = Paint()
      ..color = const Color(0xFF00FFCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 90),
        -math.pi / 2,
        progress * 2 * math.pi,
        false,
        progressPaint,
      );
    }
  }
  @override
  bool shouldRepaint(covariant GroundReflectionPainter oldDelegate) => true;
}

// ⚡ 撕裂天空的真实闪电
class RealLightningPainter extends CustomPainter {
  final math.Random random;
  RealLightningPainter({required this.random});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 全屏环境光爆闪
    final flashPaint = Paint()..color = Colors.white.withOpacity(0.15);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flashPaint);

    // 2. 闪电主干（随机落在屏幕任意位置）
    final startX = random.nextDouble() * size.width;
    final endY = size.height * (0.3 + random.nextDouble() * 0.5); // 劈到屏幕中部

    final boltPaint = Paint()
      ..color = const Color(0xFFF0F8FF) // 亮青白色
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.miter;

    // 极度明亮的发光层
    final glowPaint = Paint()
      ..color = const Color(0xFF00FFCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15.0);

    _drawBolt(canvas, Offset(startX, 0), endY, boltPaint, glowPaint, 0);
  }

  // 递归画闪电及分叉
  void _drawBolt(Canvas canvas, Offset start, double endY, Paint bolt, Paint glow, int depth) {
    if (depth > 2) return; // 限制递归深度防卡顿

    final path = Path()..moveTo(start.dx, start.dy);
    double currentX = start.dx;
    double currentY = start.dy;

    while (currentY < endY) {
      currentY += 20 + random.nextDouble() * 30;
      if (currentY > endY) currentY = endY;
      // 左右横跳幅度随深度递减
      currentX += (random.nextDouble() - 0.5) * (depth == 0 ? 60 : 30);
      path.lineTo(currentX, currentY);

      // 随机产生分叉
      if (random.nextDouble() > 0.7 && depth < 2) {
        _drawBolt(canvas, Offset(currentX, currentY), currentY + 80, bolt, glow, depth + 1);
      }
    }

    canvas.drawPath(path, glow);
    canvas.drawPath(path, bolt);
  }

  @override
  bool shouldRepaint(covariant RealLightningPainter oldDelegate) => true;
}
