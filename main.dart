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

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 25))..repeat();

    platform.setMethodCallHandler((call) async {
      if (call.method == 'updateStatus') setState(() => _status = call.arguments);
      if (call.method == 'updateProgress') setState(() => _progress = (call.arguments as num).toDouble());
      if (call.method == 'ready') setState(() => _isReady = true);
    });
    _start();
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
                // 1. 背景：纯白动态星空云
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _bgController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: StarryCloudPainter(_bgController.value),
                      );
                    },
                  ),
                ),

                // 2. 中心：落锤、阴影与进度圈
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
                            // 落锤底部光晕 (给纯白一点点缀)
                            Container(
                              width: logoSize * 0.8,
                              height: logoSize * 0.8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.05),
                                    blurRadius: 40,
                                    spreadRadius: 10,
                                  )
                                ],
                              ),
                            ),
                            // 落锤本体
                            Image.asset(
                              'assets/logo.png',
                              width: logoSize * 0.75,
                              height: logoSize * 0.75,
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

// 🌌 纯白星空动态云画笔
class StarryCloudPainter extends CustomPainter {
  final double animationValue;

  StarryCloudPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    final cloudPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80.0); // 极度模糊

    // 星云1：亮白，从左上飘过
    final cloud1Offset = Offset(
      center.dx - 120 + math.sin(animationValue * math.pi * 2) * 40,
      center.dy - 180 + math.cos(animationValue * math.pi * 2) * 30,
    );
    final cloud1Rect = Rect.fromCircle(center: cloud1Offset, radius: 220);
    cloudPaint.shader = RadialGradient(
      colors: [Colors.white.withOpacity(0.12), Colors.transparent],
    ).createShader(cloud1Rect);
    canvas.drawCircle(cloud1Offset, 220, cloudPaint);

    // 星云2：暗白，从右下飘过
    final cloud2Offset = Offset(
      center.dx + 150 + math.cos(animationValue * math.pi * 2) * 50,
      center.dy + 200 + math.sin(animationValue * math.pi * 2) * 40,
    );
    final cloud2Rect = Rect.fromCircle(center: cloud2Offset, radius: 260);
    cloudPaint.shader = RadialGradient(
      colors: [Colors.white.withOpacity(0.08), Colors.transparent],
    ).createShader(cloud2Rect);
    canvas.drawCircle(cloud2Offset, 260, cloudPaint);

    // 满天繁星
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 80; i++) {
      math.Random starRandom = math.Random(i * 100); 
      double x = starRandom.nextDouble() * size.width;
      double y = starRandom.nextDouble() * size.height;
      
      double twinkle = (math.sin(animationValue * math.pi * 4 + i) + 1) / 2;
      double opacity = 0.2 + twinkle * 0.8; 
      
      double radius = starRandom.nextDouble() * 1.5 + 0.5; 
      
      if (radius > 1.8) {
        final glowPaint = Paint()
          ..color = Colors.white.withOpacity(opacity * 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        canvas.drawCircle(Offset(x, y), radius * 2, glowPaint);
      }

      starPaint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StarryCloudPainter oldDelegate) => true;
}
