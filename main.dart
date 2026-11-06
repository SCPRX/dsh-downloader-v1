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

  // 🌌 极光渐变色：青绿 -> 湛蓝 -> 幻紫
  final List<Color> _auroraColors = [
    const Color(0xFF00FFCC), // 极光青
    const Color(0xFF00BFFF), // 深天蓝
    const Color(0xFF8A2BE2), // 蓝紫
    const Color(0xFF00FFCC), // 闭环
  ];

  @override
  void initState() {
    super.initState();
    _auroraController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

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
      body: !_isReady
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  
                  // 🌌 极光魔法阵
                  SizedBox(
                    width: 240.0,
                    height: 240.0,
                    child: AnimatedBuilder(
                      animation: _auroraController,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // 1. 底层：极光落锤
                            SizedBox(
                              width: 180.0,
                              height: 180.0,
                              child: ShaderMask(
                                shaderCallback: (Rect bounds) {
                                  return SweepGradient(
                                    colors: _auroraColors,
                                    stops: const [0.0, 0.4, 0.7, 1.0],
                                    transform: GradientRotation(_auroraController.value * 2 * math.pi),
                                  ).createShader(bounds);
                                },
                                blendMode: BlendMode.srcIn,
                                child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                              ),
                            ),
                            
                            // 2. 顶层：极光进度圈
                            CustomPaint(
                              size: const Size(220.0, 220.0),
                              painter: AuroraProgressPainter(
                                progress: _progress,
                                colors: _auroraColors,
                                rotation: _auroraController.value,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 40.0),
                  // 底部状态文字
                  Text(
                    _status, 
                    style: const TextStyle(
                      fontSize: 16.0, 
                      color: Color(0xFF00FFCC), // 文字也换成极光青
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
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF8A2BE2)), // 发送按钮也改色
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

// 🎨 极光进度条画笔
class AuroraProgressPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final double rotation;

  AuroraProgressPainter({
    required this.progress,
    required this.colors,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // 底部的暗色轨道
    final trackPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius - 5, trackPaint);

    // 进度弧线的极光渐变
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      colors: colors,
      stops: const [0.0, 0.4, 0.7, 1.0],
      transform: GradientRotation(rotation * 2 * math.pi), // 让颜色跟着转
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // 如果还没开始下载，画一个旋转的极光弧线（加载动画）
    if (progress == 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 5),
        rotation * 2 * math.pi, 
        1.5, // 弧长
        false, 
        progressPaint
      );
    } else {
      // 如果有进度，画出对应比例的圆弧
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 5),
        -math.pi / 2, // 从正上方开始
        progress * 2 * math.pi, // 进度对应的角度
        false, 
        progressPaint
      );
    }
  }

  @override
  bool shouldRepaint(covariant AuroraProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.rotation != rotation;
  }
}
