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
  String _status = "正在检查环境...";
  double _progress = 0.0;
  bool _isReady = false;
  static const platform = MethodChannel('com.dsh.dshapp/status');
  late AnimationController _weatherController;
  
  // 天气与闪电状态
  bool _isLightningStriking = false;
  Timer? _lightningTimer;
  final math.Random _random = math.Random();
  
  // 雨滴粒子系统
  List<RainDrop> _raindrops = [];
  // 波纹粒子系统
  List<Ripple> _ripples = [];

  @override
  void initState() {
    super.initState();
    // 全局天气动画控制器 (驱动雨滴下落、波纹扩散)
    _weatherController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    
    _weatherController.addListener(_updateParticles);
    _initRain();
    _startLightningLoop();

    platform.setMethodCallHandler((call) async {
      if (call.method == 'updateStatus') {
        setState(() => _status = call.arguments);
      } else if (call.method == 'updateProgress') {
        setState(() => _progress = (call.arguments as num).toDouble());
      } else if (call.method == 'ready') {
        setState(() => _isReady = true);
      }
    });
    _start();
  }

  // 初始化雨滴
  void _initRain() {
    for (int i = 0; i < 60; i++) {
      _raindrops.add(RainDrop(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 1.0 + _random.nextDouble() * 2.0, // 下落速度
        length: 10 + _random.nextDouble() * 20,  // 雨丝长度
      ));
    }
  }

  // 每帧更新粒子状态
  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      // 更新雨滴
      for (var drop in _raindrops) {
        drop.y += drop.speed * 0.01;
        if (drop.y > 1.0) {
          drop.y = 0;
          drop.x = _random.nextDouble();
          // 当雨滴落到底部，生成一个波纹
          if (_ripples.length < 20) { // 限制波纹数量防卡顿
            _ripples.add(Ripple(
              x: drop.x,
              y: drop.y,
              radius: 0,
              maxRadius: 10 + _random.nextDouble() * 30,
            ));
          }
        }
      }
      
      // 更新波纹(扩散并消失)
      _ripples.removeWhere((ripple) => ripple.radius >= ripple.maxRadius);
      for (var ripple in _ripples) {
        ripple.radius += 1.5;
      }
    });
  }

  void _startLightningLoop() {
    int randomDelay = 2000 + _random.nextInt(4000);
    _lightningTimer = Timer(Duration(milliseconds: randomDelay), () {
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

    setState(() => _status = "首次启动，正在下载核心环境(847MB)...");
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
      appBar: AppBar(title: const Text('原生 DSH')),
      backgroundColor: const Color(0xFF03050A), // 极度深邃的夜空黑
      body: !_isReady
          ? Stack(
              children: [
                // 1. 背景：雨与波纹
                Positioned.fill(
                  child: CustomPaint(
                    painter: WeatherPainter(raindrops: _raindrops, ripples: _ripples),
                  ),
                ),
                
                // 2. 中心：落锤与倒影
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 进度圈与落锤
                      SizedBox(
                        width: 240.0, 
                        height: 240.0,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 落锤本体 (雷击时全屏亮)
                            Image.asset(
                              'assets/logo.png',
                              width: 140.0,
                              height: 140.0,
                              fit: BoxFit.contain,
                              color: _isLightningStriking ? Colors.white : Colors.white70,
                              colorBlendMode: BlendMode.srcIn,
                            ),
                            // 极光进度条
                            CircularProgressIndicator(
                              value: _progress > 0 ? _progress : null,
                              strokeWidth: 4.0,
                              backgroundColor: Colors.white10,
                              color: const Color(0xFF00FFCC),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 40.0),
                      Text(
                        _status, 
                        style: const TextStyle(fontSize: 16.0, color: Color(0xFF00FFCC), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                
                // 3. 前景：全屏随机闪电与屏幕爆闪
                if (_isLightningStriking)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: FullScreenLightningPainter(random: _random),
                      ),
                    ),
                  ),
              ],
            )
          : const Center(child: Text("引擎就绪", style: TextStyle(color: Colors.white))),
    );
  }
}

// 💧 雨滴类
class RainDrop {
  double x, y, speed, length;
  RainDrop({required this.x, required this.y, required this.speed, required this.length});
}

// 💧 波纹类
class Ripple {
  double x, y, radius, maxRadius;
  Ripple({required this.x, required this.y, required this.radius, required this.maxRadius});
}

// 🌧️ 天气画笔 (画雨滴和波纹)
class WeatherPainter extends CustomPainter {
  final List<RainDrop> raindrops;
  final List<Ripple> ripples;

  WeatherPainter({required this.raindrops, required this.ripples});

  @override
  void paint(Canvas canvas, Size size) {
    final rainPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final ripplePaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 画雨丝 (稍微带点倾斜)
    for (var drop in raindrops) {
      double startX = drop.x * size.width;
      double startY = drop.y * size.height;
      canvas.drawLine(
          Offset(startX, startY), 
          Offset(startX - 5, startY + drop.length), // 倾斜角度
          rainPaint);
    }

    // 画波纹 (椭圆)
    for (var ripple in ripples) {
      double centerX = ripple.x * size.width;
      double centerY = size.height - 20; // 假设波纹都在底部生成
      double opacity = 1.0 - (ripple.radius / ripple.maxRadius); // 越扩散越透明
      
      ripplePaint.color = Colors.white.withOpacity(opacity * 0.5);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(centerX, centerY), 
          width: ripple.radius * 2, 
          height: ripple.radius * 0.5 // 压扁成椭圆模拟视角
        ), 
        ripplePaint
      );
    }
  }

  @override
  bool shouldRepaint(covariant WeatherPainter oldDelegate) => true;
}

// ⚡ 全屏闪电画笔 (随机位置劈落)
class FullScreenLightningPainter extends CustomPainter {
  final math.Random random;
  FullScreenLightningPainter({required this.random});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 屏幕爆闪 (全屏白底半透明)
    final flashPaint = Paint()..color = Colors.white.withOpacity(0.2);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flashPaint);

    // 2. 主闪电绘制
    final lightningPaint = Paint()
      ..color = const Color(0xFFE0FFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = const Color(0xFF00FFCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);

    // 随机起点 (在屏幕上半部分)
    double startX = random.nextDouble() * size.width;
    double startY = random.nextDouble() * (size.height * 0.3);
    
    final boltPath = Path();
    boltPath.moveTo(startX, startY);
    
    double currentX = startX;
    double currentY = startY;
    // 随机终点 (在屏幕下半部分或中间)
    double endY = size.height * 0.5 + random.nextDouble() * (size.height * 0.5);

    while (currentY < endY) {
      currentY += 20 + random.nextDouble() * 30;
      currentX += (random.nextDouble() - 0.5) * 50; // 左右横跳
      boltPath.lineTo(currentX, currentY);
      
      // 随机分叉
      if (random.nextBool() && currentY < endY - 30) {
        final branch = Path();
        branch.moveTo(currentX, currentY);
        double bx = currentX;
        double by = currentY;
        for (int i = 0; i < 3; i++) {
          bx += (random.nextDouble() - 0.5) * 40;
          by += random.nextDouble() * 20;
          branch.lineTo(bx, by);
        }
        canvas.drawPath(branch, glowPaint);
        canvas.drawPath(branch, lightningPaint);
      }
    }

    canvas.drawPath(boltPath, glowPaint);
    canvas.drawPath(boltPath, lightningPaint);
  }

  @override
  bool shouldRepaint(covariant FullScreenLightningPainter oldDelegate) => true;
}
