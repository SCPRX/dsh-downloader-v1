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
  String _status = "正在检查环境...";
  double _progress = 0.0;
  bool _isReady = false;
  static const platform = MethodChannel('com.dsh.dshapp/status');

  late AnimationController _enchantController;

  @override
  void initState() {
    super.initState();
    _enchantController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    platform.setMethodCallHandler((call) async {
      if (call.method == 'updateStatus') {
        setState(() => _status = call.arguments);
      } else if (call.method == 'updateProgress') {
        setState(() => _progress = (call.arguments as num).toDouble());
      } else if (call.method == 'ready') {
        setState(() {
          _isReady = true;
          _progress = 1.0;
        });
      }
    });
    _checkAndDownload();
  }

  @override
  void dispose() {
    _enchantController.dispose();
    super.dispose();
  }

  Future<void> _checkAndDownload() async {
    final dir = Directory.systemTemp;
    final envFile = File('${dir.path}/env_data.zip');

    if (await envFile.exists()) {
      platform.invokeMethod('startExtract', {'path': envFile.path});
      return;
    }

    setState(() => _status = "首次启动，正在下载核心环境(847MB)...");
    try {
      // 🚨 这里已经是你的真实下载链接！
      String downloadUrl = 'https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/env.zip'; 
      var request = http.Request('GET', Uri.parse(downloadUrl));
      var response = await http.Client().send(request);
      
      var contentLength = response.contentLength ?? 0;
      var received = 0;
      var sink = envFile.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          setState(() => _progress = received / contentLength);
        }
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
      appBar: AppBar(title: const Text('原生 DSH (附魔版)')),
      body: !_isReady
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 🚨 附魔落锤特效
                  SizedBox(
                    width: 180.0,
                    height: 180.0,
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
                  const SizedBox(height: 50.0),
                  SizedBox(
                    width: 200.0,
                    height: 200.0,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 160.0,
                          height: 160.0,
                          child: CircularProgressIndicator(
                            value: _progress > 0 ? _progress : null,
                            strokeWidth: 8.0,
                            backgroundColor: Colors.white12,
                            color: const Color(0xFF9C27B0),
                          ),
                        ),
                        Text("${(_progress * 100).toStringAsFixed(1)}%",
                            style: const TextStyle(
                                fontSize: 36.0,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30.0),
                  Text(_status, style: const TextStyle(fontSize: 16.0, color: Colors.grey)),
                ],
              ),
            )
          : Column(
              children: [
                const Expanded(
                  child: Center(
                      child: Text("Node 引擎已就绪！可以开始对话。",
                          style: TextStyle(fontSize: 20, color: Colors.blueAccent))),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: "输入指令...",
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24.0),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
