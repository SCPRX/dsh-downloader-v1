import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:math' as math;

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
    _bgController = AnimationController(vsync: this, duration: const Duration(milliseconds: 16))..repeat();
    _bgController.addListener(_updateParticles);
    
    for (int i = 0; i < 5; i++) { _clouds.add(_spawnCloud()); }
    for (int i = 0; i < 60; i++) { _stars.add(_spawnStar()); }

    platform.setMethodCallHandler((call) async {
      if (call.method == 'updateStatus') setState(() => _status = call.arguments);
      if (call.method == 'updateProgress') setState(() => _progress = (call.arguments as num).toDouble());
      if (call.method == 'ready') setState(() => _isReady = true);
    });
    _start();
  }

  CloudParticle _spawnCloud() {
    // 1. 随机决定云团由几个小圆组成 (3 到 6 个)
    int partCount = 3 + _random.nextInt(4);
    List<CloudPart> parts = [];
    
    // 2. 随机生成每个小圆的相对位置和大小
    for (int i = 0; i < partCount; i++) {
      parts.add(CloudPart(
        dx: (_random.nextDouble() - 0.5) * 1.5, // 水平相对偏移
        dy: (_random.nextDouble() - 0.5) * 0.8, // 垂直相对偏移
        radiusMultiplier: 0.5 + _random.nextDouble() * 0.6, // 相对大小
      ));
    }

    // 3. 在屏幕外侧很远的地方生成，这样飘进来绝对丝滑
    bool fromLeft = _random.nextBool();
    return CloudParticle(
      x: fromLeft ? -1.2 : 1.2, 
      y: _random.nextDouble() * 0.8 + 0.1, 
      radius: 0.25 + _random.nextDouble() * 0.15, 
      opacity: 0.1 + _random.nextDouble() * 0.1, 
      vx: (fromLeft ? 1 : -1) * (0.0003 + _random.nextDouble() * 0.0003), 
      parts: parts,
    );
  }

  StarParticle _spawnStar() {
    return StarParticle(
      x: _random.nextDouble(), y: _random.nextDouble(),
      radius: 0.5 + _random.nextDouble() * 1.2,
      maxLife: 100 + _random.nextDouble() * 200, life: 0,
    );
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      // 星星生灭
      for (int i = _stars.length - 1; i >= 0; i--) {
        var star = _stars[i]; star.life += 1;
        if (star.life > star.maxLife) { _stars[i] = _spawnStar(); }
      }
      
      // 云团飘动
      for (int i = _clouds.length - 1; i >= 0; i--) {
        var cloud = _clouds[i]; 
        cloud.x += cloud.vx;
        
        // 只有完全彻底飘出屏幕很远后，才回收并重新生成，防止边缘突变
        if (cloud.x < -1.5 || cloud.x > 1.5) { 
          _clouds[i] = _spawnCloud(); 
        }
      }
    });
  }

  @override
  void dispose() { _bgController.dispose(); super.dispose(); }

  Future<void> _start() async {
    final envFile = File('${Directory.systemTemp.path}/env_data.zip');
    if (await envFile.exists()) { try { envFile.deleteSync(); } catch(e) {} }
    
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
    } catch (e) { setState(() => _status = "下载失败: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF03060A), 
      child: !_isReady
          ? Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: StarryCloudPainter(_clouds, _stars)),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: logoSize, height: logoSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.asset('assets/logo.png', width: logoSize, height: logoSize, fit: BoxFit.contain, color: Colors.white, colorBlendMode: BlendMode.srcIn),
                            SizedBox(
                              width: logoSize, height: logoSize,
                              child: CircularProgressIndicator(value: _progress > 0 ? _progress : null, strokeWidth: 3.0, backgroundColor: Colors.white12, color: const Color(0xFF00FFCC), strokeAlign: CircularProgressIndicator.strokeAlignCenter),
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

// 云的组成部件
class CloudPart {
  final double dx, dy, radiusMultiplier;
  CloudPart({required this.dx, required this.dy, required this.radiusMultiplier});
}

class CloudParticle {
  double x, y, radius, opacity, vx;
  List<CloudPart> parts;
  CloudParticle({
    required this.x, required this.y, required this.radius, 
    required this.opacity, required this.vx, required this.parts
  });
}

class StarParticle {
  double x, y, radius, maxLife, life;
  StarParticle({required this.x, required this.y, required this.radius, required this.maxLife, required this.life});
}

class StarryCloudPainter extends CustomPainter {
  final List<CloudParticle> clouds;
  final List<StarParticle> stars;
  StarryCloudPainter(this.clouds, this.stars);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制云层
    final cloudPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50.0); 
    
    for (var cloud in clouds) {
      final centerOffset = Offset(cloud.x * size.width, cloud.y * size.height);
      final baseRadius = cloud.radius * size.width;
      
      // 🚨 核心丝滑算法：动态计算云在屏幕边缘的透明度
      double edgeAlpha = 1.0;
      // 刚进来时 (x < 0)：慢慢变清晰
      if (cloud.x < 0) edgeAlpha = (cloud.x + 1.0) / 1.0;
      // 快出去时 (x > 0.8)：慢慢变透明
      if (cloud.x > 0.8) edgeAlpha = (1.8 - cloud.x) / 1.0; 
      
      // 限制透明度范围，防止负数
      edgeAlpha = edgeAlpha.clamp(0.0, 1.0);
      
      cloudPaint.color = Colors.grey.withOpacity(cloud.opacity * edgeAlpha);
      
      // 根据随机生成的部件，把它们画出来拼成云
      for (var part in cloud.parts) {
        canvas.drawCircle(
          Offset(
            centerOffset.dx + part.dx * baseRadius, 
            centerOffset.dy + part.dy * baseRadius
          ), 
          baseRadius * part.radiusMultiplier, 
          cloudPaint
        );
      }
    }

    // 2. 绘制星星
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (var star in stars) {
      double lifeProgress = star.life / star.maxLife;
      double opacity = math.sin(lifeProgress * math.pi); 
      starPaint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(star.x * size.width, star.y * size.height), star.radius, starPaint);
    }
  }
  @override
  bool shouldRepaint(covariant StarryCloudPainter oldDelegate) => true;
}
