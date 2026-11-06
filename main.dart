import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:math' as math;

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
  
  late AnimationController _bgController;
  final double logoSize = 160.0;
  final math.Random _random = math.Random();
  
  // 粒子系统列表
  List<StarParticle> _stars = [];
  List<CloudParticle> _clouds = [];

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(vsync: this, duration: const Duration(milliseconds: 16))..repeat(); // 约60FPS
    _bgController.addListener(_updateParticles);
    
    // 初始化云层
    for (int i = 0; i < 4; i++) {
      _clouds.add(_spawnCloud());
    }
    // 初始化星星
    for (int i = 0; i < 80; i++) {
      _stars.add(_spawnStar());
    }

    platform.setMethodCallHandler((call) async {
      if (call.method == 'updateStatus') setState(() => _status = call.arguments);
      if (call.method == 'updateProgress') setState(() => _progress = (call.arguments as num).toDouble());
      if (call.method == 'ready') setState(() => _isReady = true);
    });
    _start();
  }

  CloudParticle _spawnCloud() {
    // 随机从屏幕四周外缘生成
    bool fromLeft = _random.nextBool();
    bool fromTop = _random.nextBool();
    return CloudParticle(
      x: fromLeft ? -0.5 : 1.5, // 从左边外或右边外进来
      y: fromTop ? _random.nextDouble() : _random.nextDouble(),
      radius: 0.2 + _random.nextDouble() * 0.3, // 半径占屏幕宽度比例
      opacity: 0.1 + _random.nextDouble() * 0.15, // 云层透明度 0.1~0.25
      vx: fromLeft ? (0.0002 + _random.nextDouble() * 0.0005) : -(0.0002 + _random.nextDouble() * 0.0005), // 缓慢横移
      vy: (fromTop ? -1 : 1) * (0.0001 + _random.nextDouble() * 0.0002), // 缓慢纵移
    );
  }

  StarParticle _spawnStar() {
    return StarParticle(
      x: _random.nextDouble(),
      y: _random.nextDouble(),
      radius: 0.5 + _random.nextDouble() * 1.5,
      maxLife: 100 + _random.nextDouble() * 200, // 寿命
      life: 0,
      twinkleSpeed: 0.02 + _random.nextDouble() * 0.05,
    );
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      // 更新星星
      for (int i = _stars.length - 1; i >= 0; i--) {
        var star = _stars[i];
        star.life += 1;
        // 如果星星寿命到了，重置它或者移除并生成新的
        if (star.life > star.maxLife) {
          _stars[i] = _spawnStar(); // 随机重生
        }
      }

      // 更新云层
      for (int i = _clouds.length - 1; i >= 0; i--) {
        var cloud = _clouds[i];
        cloud.x += cloud.vx;
        cloud.y += cloud.vy;
        
        // 如果云完全飘出屏幕外，就回收并随机生成新的
        if (cloud.x < -0.8 || cloud.x > 1.8 || cloud.y < -0.8 || cloud.y > 1.8) {
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
      setState(() => _status = "下载完成，正在解压(耗时较长)...");
      platform.invokeMethod('startExtract', {'path': envFile.path});
    } catch (e) {
      setState(() => _status = "下载失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF02050A), 
      body: !_isReady
          ? Stack(
              children: [
                // 1. 动态星空云背景
                Positioned.fill(
                  child: CustomPaint(
                    painter: StarryCloudPainter(_clouds, _stars),
                  ),
                ),

                // 2. 中心：落锤与进度
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
                            // 落锤本体 (加了个淡淡的光晕使其立体)
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00FFCC).withOpacity(0.1),
                                    blurRadius: 40,
                                    spreadRadius: 5,
                                  )
                                ],
                              ),
                            ),
                            Image.asset(
                              'assets/logo.png',
                              width: logoSize,
                              height: logoSize,
                              fit: BoxFit.contain,
                              color: Colors.white,
                              colorBlendMode: BlendMode.srcIn,
                            ),
                            // 进度圈
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
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14.0, 
                            color: Color(0xFF00FFCC),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : const Center(child: Text("引擎就绪", style: TextStyle(color: Colors.white, fontSize: 18))),
    );
  }
}

// 🌟 星星粒子
class StarParticle {
  double x, y, radius, maxLife, life, twinkleSpeed;
  StarParticle({
    required this.x, required this.y, required this.radius,
    required this.maxLife, required this.life, required this.twinkleSpeed,
  });
}

// ☁️ 云层粒子
class CloudParticle {
  double x, y, radius, opacity, vx, vy;
  CloudParticle({
    required this.x, required this.y, required this.radius,
    required this.opacity, required this.vx, required this.vy,
  });
}

// 🎨 画笔：星星与云
class StarryCloudPainter extends CustomPainter {
  final List<CloudParticle> clouds;
  final List<StarParticle> stars;

  StarryCloudPainter(this.clouds, this.stars);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 画云层 (纯白高斯模糊)
    final cloudPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60.0); // 极度模糊

    for (var cloud in clouds) {
      final cloudOffset = Offset(cloud.x * size.width, cloud.y * size.height);
      final cloudRect = Rect.fromCircle(center: cloudOffset, radius: cloud.radius * size.width);
      
      // 渐变让边缘柔和
      cloudPaint.shader = RadialGradient(
        colors: [Colors.white.withOpacity(cloud.opacity), Colors.transparent],
      ).createShader(cloudRect);
      
      canvas.drawCircle(cloudOffset, cloud.radius * size.width, cloudPaint);
    }

    // 2. 画星星 (随机生灭)
    final starPaint = Paint()..style = PaintingStyle.fill;
    
    for (var star in stars) {
      // 计算生命周期内的透明度 (正弦波：亮起 -> 变暗 -> 消失)
      double lifeProgress = star.life / star.maxLife;
      // 如果是生命周期的前 20% 和 后 20%，让它淡入淡出
      double opacity = math.sin(lifeProgress * math.pi);
      
      // 如果过大，加点光晕
      if (star.radius > 1.5) {
        final glowPaint = Paint()
          ..color = Colors.white.withOpacity(opacity * 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
        canvas.drawCircle(Offset(star.x * size.width, star.y * size.height), star.radius * 2, glowPaint);
      }

      starPaint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(star.x * size.width, star.y * size.height), star.radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StarryCloudPainter oldDelegate) => true;
}
