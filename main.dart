import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  
  String _status = "正在检查环境...";
  double _progress = 0.0;
  bool _isReady = false;
  static const platform = MethodChannel('com.dsh.dshapp/status');
  late AnimationController _auroraController;

  @override
  void initState() {
    super.initState();
    // 极光波浪动画
    _auroraController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

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

  @override
  void dispose() {
    _auroraController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final envFile = File('${Directory.systemTemp.path}/env_data.zip');
    if (await envFile.exists()) {
      platform.invokeMethod('startExtract', {'path': envFile.path});
      return;
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
      backgroundColor: const Color(0xFF0B0F19), // 极光深空底色
      body: !_isReady
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  
                  // 🌌 极光波浪包裹落锤
                  SizedBox(
                    width: 300.0, // 放大容器，给极光留出蔓延的空间
                    height: 300.0,
                    child: AnimatedBuilder(
                      animation: _auroraController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: AuroraWavePainter(
                            animationValue: _auroraController.value,
                            progress: _progress,
                          ),
                          child: Center(
                            // 落锤放在中间，保持纯白，不染特效
                            child: Image.asset(
                              'assets/logo.png',
                              width: 140.0,
                              height: 140.0,
                              fit: BoxFit.contain,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 40.0),
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
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF8A2BE2)),
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

// 🎨 真正的极光波浪画笔 (Aurora Wave Painter)
class AuroraWavePainter extends CustomPainter {
  final double animationValue;
  final double progress;

  AuroraWavePainter({required this.animationValue, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 极光色板：绿色、青色、蓝紫色
    final auroraColors = [
      const Color(0xFF00FF88), // 极光绿
      const Color(0xFF00CCFF), // 极光青
      const Color(0xFF6600FF), // 极光紫
    ];

    // 1. 画底部的暗色进度环
    final trackPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius - 20, trackPaint);

    // 2. 画进度弧线 (跟随进度)
    final progressPaint = Paint()
      ..color = auroraColors[0].withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0); // 进度条也加点发光

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 20),
        -math.pi / 2,
        progress * 2 * math.pi,
        false,
        progressPaint,
      );
    }

    // 3. 画流动的极光波浪
    canvas.save();
    // 限制在圆形区域内，防止波浪溢出
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius - 10)));

    // 画三层不同速度、不同颜色的波浪
    for (int i = 0; i < 3; i++) {
      final wavePaint = Paint()
        ..color = auroraColors[i].withOpacity(0.3 + (progress * 0.4)) // 进度越高，极光越亮
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20.0); // 极光的高斯模糊

      final path = Path();
      // 每层波浪的速度和相位偏移不同
      final speed = (animationValue * 2 * math.pi) + (i * math.pi / 2);
      final amplitude = 20.0 + (i * 10);
      final waveHeight = center.dy + (i * 20) - 30;

      path.moveTo(0, size.height);
      path.lineTo(0, waveHeight);

      // 用正弦波画曲线
      for (double x = 0; x <= size.width; x += 10) {
        final y = waveHeight + amplitude * math.sin((x / size.width * 2 * math.pi) + speed);
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.close();

      canvas.drawPath(path, wavePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AuroraWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.progress != progress;
  }
}
