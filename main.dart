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
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  
  String _status = "正在检查环境...";
  double _progress = 0.0;
  bool _isReady = false;
  static const platform = MethodChannel('com.dsh.dshapp/status');
  late AnimationController _auroraController;
  
  // ⚡ 控制雷击状态
  bool _isLightningStriking = false;
  Timer? _lightningTimer;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _auroraController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    
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

  // ⚡ 真实的雷击时间控制
  void _startLightningLoop() {
    // 随机 2 到 7 秒劈一次
    int randomDelay = 2000 + _random.nextInt(5000);
    
    _lightningTimer = Timer(Duration(milliseconds: randomDelay), () {
      if (mounted) {
        setState(() => _isLightningStriking = true);
        
        // 闪电持续时间极短：120毫秒
        Future.delayed(const Duration(milliseconds: 120), () {
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
    _auroraController.dispose();
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
      backgroundColor: const Color(0xFF06080F),
      body: !_isReady
          ? Stack(
              children: [
                // 1. 底层：极光与落锤
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 260.0, 
                        height: 260.0,
                        child: AnimatedBuilder(
                          animation: _auroraController,
                          builder: (context, child) {
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                // 落锤被劈中时会爆亮
                                Image.asset(
                                  'assets/logo.png',
                                  width: 140.0,
                                  height: 140.0,
                                  fit: BoxFit.contain,
                                  color: _isLightningStriking ? Colors.white : Colors.white70,
                                  colorBlendMode: BlendMode.srcIn,
                                ),
                                CustomPaint(
                                  size: const Size(240.0, 240.0),
                                  painter: AuroraPainter(
                                    progress: _progress,
                                    animationValue: _auroraController.value,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 50.0),
                      Text(
                        _status, 
                        style: const TextStyle(fontSize: 16.0, color: Color(0xFF00FFCC), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                
                // 2. 顶层：从天而降的雷电特效
                if (_isLightningStriking)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: TrueLightningPainter(random: _random),
                      ),
                    ),
                  ),
              ],
            )
          : const Center(child: Text("引擎就绪")), // 聊天界面代码保持不变，这里省去
    );
  }
}

// 🌌 极光画笔 (保留原来的好看部分)
class AuroraPainter extends CustomPainter {
  final double progress;
  final double animationValue;

  AuroraPainter({required this.progress, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius - 4);

    final auroraColors = [
      const Color(0xFF0044FF), const Color(0xFF00FFCC),
      const Color(0xFF00FF88), const Color(0xFFAA00FF), const Color(0xFF0044FF),
    ];

    final trackPaint = Paint()..color = Colors.white.withOpacity(0.05)..style = PaintingStyle.stroke..strokeWidth = 6.0;
    canvas.drawCircle(center, radius - 4, trackPaint);

    final sweepGradient = SweepGradient(
      colors: auroraColors,
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(animationValue * 2 * math.pi),
    );

    for (int i = 0; i < 3; i++) {
      double startAngle = (animationValue * 2 * math.pi) + (i * math.pi / 1.5);
      double sweepAngle = progress > 0 ? (progress * 2 * math.pi) : 1.5;
      if (progress > 0) startAngle = -math.pi / 2;

      final glowPaint = Paint()
        ..shader = sweepGradient.createShader(rect)..style = PaintingStyle.stroke
        ..strokeWidth = 12.0 + (i * 4.0)..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10.0 + (i * 5.0));

      final corePaint = Paint()
        ..shader = sweepGradient.createShader(rect)..style = PaintingStyle.stroke
        ..strokeWidth = 4.0..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
      canvas.drawArc(rect, startAngle, sweepAngle, false, corePaint);
    }
  }
  @override
  bool shouldRepaint(covariant AuroraPainter oldDelegate) => true;
}

// ⚡ 电视级别的真实雷电画笔
class TrueLightningPainter extends CustomPainter {
  final math.Random random;
  TrueLightningPainter({required this.random});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // 1. 全屏爆闪（劈中瞬间的白光）
    final flashPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flashPaint);

    // 2. 绘制从天而降的闪电
    final lightningPaint = Paint()
      ..color = const Color(0xFFE0FFFF) // 极光青白色
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.miter;

    final glowPaint = Paint()
      ..color = const Color(0xFF00FFCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.miter
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15.0); // 巨大的发光

    // 主干路径
    final mainBolt = Path();
    // 起点：屏幕顶部中间偏左一点
    double startX = size.width / 2 + (random.nextDouble() - 0.5) * 100;
    mainBolt.moveTo(startX, 0);
    
    double currentX = startX;
    double currentY = 0;
    double endY = center.dy; // 终点直接劈到落锤中心

    // 主干曲折向下
    while (currentY < endY) {
      currentY += 30 + random.nextDouble() * 40;
      if (currentY > endY) currentY = endY;
      
      // 水平左右横跳
      currentX += (random.nextDouble() - 0.5) * 80; 
      mainBolt.lineTo(currentX, currentY);
      
      // 随机产生分叉（树枝）
      if (random.nextBool() && currentY < endY - 50) {
        final branch = Path();
        branch.moveTo(currentX, currentY);
        double bx = currentX;
        double by = currentY;
        int branchSegs = 3 + random.nextInt(3);
        for (int i = 0; i < branchSegs; i++) {
          bx += (random.nextDouble() - 0.5) * 60;
          by += random.nextDouble() * 30;
          branch.lineTo(bx, by);
        }
        // 分叉比主干细
        final branchPaint = Paint()
          ..color = const Color(0xFF00FFCC).withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;
        final branchGlow = Paint()
          ..color = const Color(0xFF00FFCC).withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
          
        canvas.drawPath(branch, branchGlow);
        canvas.drawPath(branch, branchPaint);
      }
    }

    // 绘制主干闪电（先发光，再画核心）
    canvas.drawPath(mainBolt, glowPaint);
    canvas.drawPath(mainBolt, lightningPaint);

    // 3. 落锤中心的爆裂点（雷击点的高光）
    final impactPaint = Paint()
      ..color = Colors.white
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20.0);
    canvas.drawCircle(Offset(currentX, endY), 40, impactPaint);
  }

  @override
  bool shouldRepaint(covariant TrueLightningPainter oldDelegate) => true;
}
