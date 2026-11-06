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
  
  // ⚡ 控制闪电状态
  bool _isLightningStriking = false;
  Timer? _lightningTimer;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _auroraController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    
    // ⚡ 启动闪电定时循环
    _startLightningLoop();

    platform.setMethodCallHandler((call) async {
      if (call.method == 'updateStatus') {
        setState(() => _status = call.arguments);
        if ((call.arguments as String).startsWith("底层:")) {
          setState(() => _messages.add({"text": call.arguments, "isUser": false}));
        }
      } else if (call.method == 'updateProgress') {
        setState(() => _progress = (call.arguments as num).toDouble());
      } else if (call.method == 'ready') {
        setState(() => _isReady = true);
      }
    });
    _start();
  }

  // ⚡ 真正随机时间的闪电逻辑
  void _startLightningLoop() {
    // 随机间隔：1500毫秒（1.5秒）到 8000毫秒（8秒）之间随机
    int randomDelay = 1500 + _random.nextInt(6500);
    
    _lightningTimer = Timer(Duration(milliseconds: randomDelay), () {
      if (mounted) {
        setState(() => _isLightningStriking = true);
        
        // 随机持续时间：80毫秒（极快闪烁）到 200毫秒（稍微停留）之间随机
        int randomDuration = 80 + _random.nextInt(120);
        
        Future.delayed(Duration(milliseconds: randomDuration), () {
          if (mounted) {
            setState(() => _isLightningStriking = false);
            _startLightningLoop(); // 递归重新触发下一轮
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

  void _sendMessage() async {
    if (_controller.text.isEmpty) return;
    setState(() => _messages.add({"text": _controller.text, "isUser": true}));
    final msg = _controller.text;
    _controller.clear();

    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:3080/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"message": msg}),
      ).timeout(const Duration(seconds: 15));
      setState(() => _messages.add({"text": response.body, "isUser": false}));
    } catch (e) {
      setState(() => _messages.add({"text": "连接失败", "isUser": false}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('原生 DSH')),
      backgroundColor: const Color(0xFF06080F),
      body: !_isReady
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  
                  // 🌌 极光 + 闪电 + 落锤
                  SizedBox(
                    width: 260.0, 
                    height: 260.0,
                    child: AnimatedBuilder(
                      animation: _auroraController,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // 1. 落锤 (雷电闪击时，落锤爆亮白光并带光晕)
                            AnimatedContainer(
                              duration: Duration(milliseconds: 50),
                              width: 140.0,
                              height: 140.0,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  if (_isLightningStriking)
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.8),
                                      blurRadius: 50,
                                      spreadRadius: 15,
                                    )
                                ],
                              ),
                              child: Image.asset(
                                'assets/logo.png',
                                fit: BoxFit.contain,
                                color: _isLightningStriking ? Colors.white : Colors.white70, // 闪击时全白
                                colorBlendMode: BlendMode.srcIn,
                              ),
                            ),
                            
                            // 2. 外层：极光与闪电画笔
                            CustomPaint(
                              size: const Size(240.0, 240.0),
                              painter: AuroraLightningPainter(
                                progress: _progress,
                                animationValue: _auroraController.value,
                                isLightning: _isLightningStriking,
                                random: _random,
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
                    style: const TextStyle(
                      fontSize: 16.0, 
                      color: Color(0xFF00FFCC),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return Align(
                        alignment: msg["isUser"] ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: msg["isUser"] ? Colors.blue[700] : Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(msg["text"], style: const TextStyle(color: Colors.white, fontSize: 14)),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: "输入指令...",
                              filled: true, fillColor: Colors.grey[900],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          icon: const Icon(Icons.send), 
                          onPressed: _sendMessage,
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF00FFCC)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// 🎨 极光流波 + 闪电画笔
class AuroraLightningPainter extends CustomPainter {
  final double progress;
  final double animationValue;
  final bool isLightning;
  final math.Random random;

  AuroraLightningPainter({
    required this.progress, 
    required this.animationValue,
    required this.isLightning,
    required this.random,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius - 4);

    final auroraColors = [
      const Color(0xFF0044FF),
      const Color(0xFF00FFCC),
      const Color(0xFF00FF88),
      const Color(0xFFAA00FF),
      const Color(0xFF0044FF),
    ];

    // 1. 底圈
    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawCircle(center, radius - 4, trackPaint);

    // 2. 极光渐变
    final sweepGradient = SweepGradient(
      colors: auroraColors,
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(animationValue * 2 * math.pi),
    );

    // 3. 极光流波
    for (int i = 0; i < 3; i++) {
      double startAngle = (animationValue * 2 * math.pi) + (i * math.pi / 1.5);
      double sweepAngle = progress > 0 ? (progress * 2 * math.pi) : 1.5;
      if (progress > 0) startAngle = -math.pi / 2;

      final glowPaint = Paint()
        ..shader = sweepGradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0 + (i * 4.0)
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10.0 + (i * 5.0));

      final corePaint = Paint()
        ..shader = sweepGradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
      canvas.drawArc(rect, startAngle, sweepAngle, false, corePaint);
    }

    // 4. ⚡ 闪电降临
    if (isLightning) {
      final lightningGlowPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.miter
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);

      final lightningCorePaint = Paint()
        ..color = const Color(0xFF00FFCC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      int numBolts = random.nextInt(2) + 1; 
      for (int b = 0; b < numBolts; b++) {
        final path = Path();
        double startAngle = random.nextDouble() * 2 * math.pi;
        double angleSpan = (random.nextDouble() * 1.5 + 0.5) * (random.nextBool() ? 1 : -1);
        int segments = 8 + random.nextInt(6); 
        
        for (int i = 0; i <= segments; i++) {
          double t = i / segments;
          double currentAngle = startAngle + (angleSpan * t);
          double noise = (random.nextDouble() - 0.5) * 25.0;
          double currentRadius = (radius - 10) + noise;
          
          double x = center.dx + currentRadius * math.cos(currentAngle);
          double y = center.dy + currentRadius * math.sin(currentAngle);
          
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        
        canvas.drawPath(path, lightningGlowPaint);
        canvas.drawPath(path, lightningCorePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant AuroraLightningPainter oldDelegate) {
    return true; 
  }
}
