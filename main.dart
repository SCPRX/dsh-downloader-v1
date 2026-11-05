import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark)),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  String _status = "正在检查环境...";
  double _progress = 0.0;
  bool _isReady = false;
  static const platform = MethodChannel('com.dsh.dshapp/status');

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler((call) async {
      if (call.method == 'updateStatus') {
        setState(() => _status = call.arguments);
      } else if (call.method == 'updateProgress') {
        setState(() => _progress = (call.arguments as num).toDouble());
      } else if (call.method == 'ready') {
        setState(() => _isReady = true);
      }
    });
    _checkAndDownload();
  }

  Future<void> _checkAndDownload() async {
    final dir = Directory.systemTemp; // 暂时用系统临时目录
    final envFile = File('${dir.path}/env_data.zip');

    if (await envFile.exists()) {
      platform.invokeMethod('startExtract', {'path': envFile.path});
      return;
    }

    setState(() => _status = "首次启动，正在下载...");
    try {
      // 🚨 测试用下载链接，一个几兆的文件
      String downloadUrl = 'https://github.com/deepseek-ai/deepseek-harness/archive/refs/heads/main.zip'; 
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

  void _sendMessage() {
    if (_controller.text.isEmpty || !_isReady) return;
    setState(() => _controller.clear());
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
                  const Icon(Icons.downloading, size: 80, color: Colors.blueAccent),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: 200, height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 160, height: 160,
                          child: CircularProgressIndicator(
                            value: _progress > 0 ? _progress : null,
                            strokeWidth: 8,
                            color: Colors.blueAccent,
                          ),
                        ),
                        Text("${(_progress * 100).toStringAsFixed(1)}%", style: const TextStyle(fontSize: 30, color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(_status, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(child: Center(child: Text("Node 引擎已就绪！", style: TextStyle(fontSize: 20)))),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: "输入指令..."),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ],
            ),
    );
  }
}
