import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
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
  
  late AnimationController _weatherController;
  bool _isLightningStriking = false;
  Timer? _lightningTimer;
  final math.Random _random = math.Random();
  
  List<RainDrop> _raindrops = [];
  final double logoSize = 160.0; 

  @override
  void initState() {
    super.initState();
    _weatherController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _weatherController.addListener(_updateParticles);
    _initRain();
    _startLightningLoop();
  }

  void _initRain() {
    for (int i = 0; i < 100; i++) {
      int layer = _random.nextInt(3);
      _raindrops.add(RainDrop(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        // 立体感核心：远近雨滴速度、长度、粗细、倾斜度完全不同
        speed: layer == 2 ? 2.0 + _random.nextDouble() : (layer == 1 ? 1.2 : 0.5),
        length: layer == 2 ? 50.0 : (layer == 1 ? 25.0 : 10.0),
        thickness: layer == 2 ? 2.5 : (layer == 1 ? 1.2 : 0.6),
        opacity: layer == 2 ? 0.6 : (layer == 1 ? 0.3 : 0.1),
        windOffset: -0.3, // 被风吹歪的倾斜度
      ));
    }
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (var drop in _raindrops) {
        drop.y += drop.speed * 0.02;
        drop.x += drop.windOffset * 0.02;
        if (drop.y > 1.0 || drop.x < 0) {
          drop.y = 0;
          drop.x = _random.nextDouble() + 0.3;
        }
      }
    });
  }

  void _startLightningLoop() {
    int randomDelay = 3000 + _random.nextInt(4000); 
    _lightningTimer = Timer(Duration(milliseconds: randomDelay), () {
      if (mounted) {
        setState(() => _isLightningStriking = true);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) setState(() => _isLightningStriking = false);
          _startLightningLoop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 深度立体感：背景用径向渐变，中间亮四周暗
      backgroundColor: Colors.transparent, 
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.0,
            colors: [
              Color(0xFF101826), // 微微透亮的夜空蓝
              Color(0xFF05070A), // 边缘极限黑
            ],
          ),
        ),
        child: Stack(
          children: [
            // 1. 景深暴雨
            Positioned.fill(
              child: CustomPaint(painter: RainPainter(_raindrops)),
            ),

            // 2. 落锤与湿滑倒影
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 落锤带立体光晕
                  Container(
                    width: logoSize,
                    height: logoSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: _isLightningStriking ? [
                        const BoxShadow(color: Colors.white, blurRadius: 50, spreadRadius: 20)
                      ] : null, // 只有闪电时爆光，平时靠边框
                    ),
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      color: _isLightningStriking ? Colors.white : Colors.white70,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                  ),
                  
                  // 湿滑倒影 (利用 ShaderMask 做渐隐)
                  Transform(
                    transform: Matrix4.identity()
                      ..scale(1.0, -0.6) // 压缩并翻转
                      ..translate(0.0, -logoSize * 0.6),
                    alignment: Alignment.topCenter,
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Colors.transparent], // 渐隐，越往下越看不见
                        ).createShader(bounds);
                      },
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 3.0, sigmaY: 8.0), // 纵向拉伸模糊，模拟水面
                        child: Opacity(
                          opacity: 0.15,
                          child: Image.asset(
                            'assets/logo.png',
                            width: logoSize,
                            height: logoSize,
                            fit: BoxFit.contain,
                            color: const Color(0xFF00FFCC),
                            colorBlendMode: BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3. 闪电
            if (_isLightningStriking)
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: RealLightningPainter(random: _random))),
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
        ),
      ),
    );
  }
}

class RainDrop {
  double x, y, speed, length, thickness, opacity, windOffset;
  RainDrop({required this.x, required this.y, required this.speed, required this.length, required this.thickness, required this.opacity, required this.windOffset});
}

class RainPainter extends CustomPainter {
  final List<RainDrop> drops;
  RainPainter(this.drops);

  @override
  void paint(Canvas canvas, Size size) {
    for (var drop in drops) {
      final paint = Paint()
        ..color = Colors.white.withOpacity(drop.opacity)
        ..strokeWidth = drop.thickness
        ..strokeCap = StrokeCap.round;
      
      // 近处的雨滴带有动态模糊
      if (drop.thickness > 2.0) {
        paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      }

      final startX = drop.x * size.width;
      final startY = drop.y * size.height;
      // 倾斜终点
      final endX = startX - (drop.length * drop.windOffset);
      final endY = startY + drop.length;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
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
    final flashPaint = Paint()..color = Colors.white.withOpacity(0.1);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flashPaint);
    
    final startX = random.nextDouble() * size.width;
    final endY = size.height * (0.2 + random.nextDouble() * 0.6);
    final boltPaint = Paint()..color = const Color(0xFFF0F8FF)..style = PaintingStyle.stroke..strokeWidth = 2.0;
    final glowPaint = Paint()..color = const Color(0xFF00FFCC)..style = PaintingStyle.stroke..strokeWidth = 10.0..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);

    _drawBolt(canvas, Offset(startX, 0), endY, boltPaint, glowPaint, 0);
  }

  void _drawBolt(Canvas canvas, Offset start, double endY, Paint bolt, Paint glow, int depth) {
    if (depth > 2) return;
    final path = Path()..moveTo(start.dx, start.dy);
    double currentX = start.dx, currentY = start.dy;
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
