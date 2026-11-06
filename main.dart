import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:math' as math;

void main() {
  // 🚨 强制全屏沉浸，隐藏顶部状态栏和导航栏
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
  String _status = "正在检查环境...";
  double _progress = 0.0;
  bool _isReady = false;
  static const platform = MethodChannel('com.dsh.dshapp/status');
  
  late AnimationController _bgController;
  final double logoSize = 160.0;
  final math.Random _random = math.Random();
  
  List<StarParticle> _stars = [];
  List<CloudParticle> _clouds = [];

  @override
  void initState() {
    super.initState();
    // 约60FPS的刷新率
    _bgController = AnimationController(vsync: this, duration: const Duration(milliseconds: 16))..repeat();
    _bgController.addListener(_updateParticles);
    
    // 初始化原生云团
    for (int i = 0; i < 4; i++) {
      _clouds.add(_spawnCloud());
    }
    // 初始化星星
    for (int i = 0; i < 60; i++) {
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
    // 🚨 原生云：从左右两侧随机飘入，用灰白色
    return CloudParticle(
      x: _random.nextBool() ? -0.6 : 1.6, 
      y: _random.nextDouble() * 0.8 + 0.1, 
      radius: 0.25 + _random.nextDouble() * 0.2, // 云团大小
      opacity: 0.15 + _random.nextDouble() * 0.15, // 云团厚度 (透明度)
      vx: (_random.nextBool() ? 1 : -1) * (0.0005 + _random.nextDouble() * 0.0005), // 飘动速度
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
      // 星星生灭
      for (int i = _stars.length - 1; i >= 0; i--) {
        var star = _stars[i];
        star.life += 1;
        if (star.life > star.maxLife) {
          _stars[i] = _spawnStar();
        }
      }

      // 云团飘动
      for (int i = _clouds.length - 1; i >= 0; i--) {
        var cloud = _clouds[i];
        cloud.x += cloud.vx;
        
        // 飘出屏幕后重新生成
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
    // 🚨 注意：这里没有任何 AppBar，纯全屏
    return Scaffold(
      backgroundColor: const Color(0xFF03060A), // 深邃夜空
      body: !_isReady
          ? Stack(
              children: [
                // 1. 动态星空与原生云
                Positioned.fill(
                  child: CustomPaint(
                    painter: StarryCloudPainter(_clouds, _stars),
                  ),
                ),

                // 2. 中心落锤
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
                            Image.asset(
                              'assets/logo.png',
                              width: logoSize,
                              height: logoSize,
                              fit: BoxFit.contain,
                              color: Colors.white,
                              colorBlendMode: BlendMode.srcIn,
                            ),
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
                      
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.0, 
                          color: Color(0xFF00FFCC),
                          fontWeight: FontWeight.bold,
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

class StarParticle {
  double x, y, radius, maxLife, life;
  StarParticle({required this.x, required this.y, required this.radius, required this.maxLife, required this.life});
}

class CloudParticle {
  double x, y, radius, opacity, vx;
  CloudParticle({
    required this.x, required this.y, required this.radius,
    required this.opacity, required this.vx,
  });
}

class StarryCloudPainter extends CustomPainter {
  final List<CloudParticle> clouds;
  final List<StarParticle> stars;

  StarryCloudPainter(this.clouds, this.stars);

  @override
  void paint(Canvas canvas, Size size) {
    // 🌌 1. 绘制原生云层
    final cloudPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50.0); // 云的高斯模糊

    for (var cloud in clouds) {
      final centerOffset = Offset(cloud.x * size.width, cloud.y * size.height);
      final baseRadius = cloud.radius * size.width;

      // 🚨 核心：用 3 个大小不一的灰白模糊圆拼成一个云团，这样看起来才像自然界的云，有厚度和起伏
      // 颜色使用半透明灰白，而不是纯白
      cloudPaint.color = Colors.grey.withOpacity(cloud.opacity);
      
      // 云团主体
      canvas.drawCircle(centerOffset, baseRadius, cloudPaint);
      
      // 左侧凸起
      canvas.drawCircle(
        Offset(centerOffset.dx - baseRadius * 0.6, centerOffset.dy + baseRadius * 0.1), 
        baseRadius * 0.7, 
        cloudPaint
      );
      
      // 右侧凸起
      canvas.drawCircle(
        Offset(centerOffset.dx + baseRadius * 0.7, centerOffset.dy - baseRadius * 0.1), 
        baseRadius * 0.8, 
        cloudPaint
      );
    }

    // ✨ 2. 绘制星星
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (var star in stars) {
      double lifeProgress = star.life / star.maxLife;
      double opacity = math.sin(lifeProgress * math.pi); // 生命周期透明度
      
      starPaint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(star.x * size.width, star.y * size.height), star.radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StarryCloudPainter oldDelegate) => true;
}
