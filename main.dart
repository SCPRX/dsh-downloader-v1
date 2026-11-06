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
              seedColor: const Color(0xFF9C27B0), brightness: Brightness.dark)),
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
  late AnimationController _enchantController;

  @override
  void initState() {
    super.initState();
    _enchantController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

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
    _enchantController.dispose();
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
                  
                  // 🚨 去掉数字，让圈和图片完美贴合
                  SizedBox(
                    width: 210.0,
                    height: 210.0,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 1. 底层：落锤图片放大到 210
                        SizedBox(
                          width: 210.0,
                          height: 210.0,
                          child: AnimatedBuilder(
                            animation: _enchantController,
                            builder: (context, child) {
                              return ShaderMask(
                                shaderCallback: (Rect bounds) {
                                  return SweepGradient(
                                    colors: const [
                                      Color(0xFF9C27B0),
                                      Color(0xFFE040FB),
                                      Color(0xFFFFFFFF),
                                      Color(0xFF651FFF),
                                      Color(0xFF9C27B0),
                                    ],
                                    stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                                    transform: GradientRotation(_enchantController.value * 2 * math.pi),
                                  ).createShader(bounds);
                                },
                                blendMode: BlendMode.srcIn,
                                child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                              );
                            },
                          ),
                        ),
                        
                        // 2. 外层：进度圈（尺寸调到和图片一样大，加粗），去掉了背景轨道
                        SizedBox(
                          width: 208.0, // 稍微比图片小2像素，刚好卡在内侧
                          height: 208.0,
                          child: CircularProgressIndicator(
                            value: _progress > 0 ? _progress : null,
                            strokeWidth: 8.0, // 加粗，看起来更有力量
                            backgroundColor: Colors.transparent, // 轨道透明
                            color: const Color(0xFFFFFFFF), // 进度条用纯白色，或者用 0xFFE040FB 亮紫
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30.0),
                  // 这里只保留底部的状态文字提示
                  Text(_status, style: const TextStyle(fontSize: 16.0, color: Colors.orangeAccent)),
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
                        IconButton.filled(icon: const Icon(Icons.send), onPressed: _sendMessage),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
