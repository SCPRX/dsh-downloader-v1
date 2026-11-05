import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:ui';

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
              seedColor: Colors.blue, brightness: Brightness.dark)),
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
        setState(() {
          _isReady = true;
          _progress = 1.0;
        });
      }
    });
    _checkAndDownload();
  }

  Future<void> _checkAndDownload() async {
    final dir = Directory.systemTemp;
    final envFile = File('${dir.path}/env_data.zip');

    if (await envFile.exists()) {
      platform.invokeMethod('startExtract', {'path': envFile.path});
      return;
    }

    setState(() => _status = "首次启动，正在下载核心环境...");
    try {
      // 🚨 注意：这里目前还是测试的源码包。等咱们真正打包好环境后，换成真实的 700M 下载链接。
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('原生 DSH')),
      body: !_isReady
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 🚨 落锤图标（已去掉引发报错的 const）
                  SizedBox(
                    width: 160.0,
                    height: 160.0,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: 512.0,
                        height: 512.0,
                        child: CustomPaint(painter: HammerDownPainter()),
                      ),
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
                            color: Colors.blueAccent,
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
                  Text(_status,
                      style: const TextStyle(fontSize: 16.0, color: Colors.grey)),
                ],
              ),
            )
          : Column(
              children: [
                const Expanded(
                  child: Center(
                      child: Text("Node 引擎已就绪！可以开始对话。",
                          style: TextStyle(
                              fontSize: 20, color: Colors.blueAccent))),
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

// 🎨 你的完美落锤代码（所有数字已转 double）
class HammerDownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double unit = 512.0;
    canvas.save();
    canvas.scale(size.width / unit, size.height / unit);

    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12.0
      ..isAntiAlias = true;

    canvas.drawCircle(const Offset(256.0, 256.0), 232.0, stroke);

    final head = Path()
      ..moveTo(62.0, 188.0)
      ..lineTo(330.0, 82.0)
      ..quadraticBezierTo(350.0, 75.0, 365.0, 94.0)
      ..lineTo(425.0, 170.0)
      ..lineTo(285.0, 250.0)
      ..lineTo(115.0, 330.0)
      ..close();

    final notch = Path()
      ..moveTo(62.0, 188.0)
      ..lineTo(115.0, 330.0)
      ..lineTo(205.0, 280.0)
      ..quadraticBezierTo(170.0, 282.0, 145.0, 260.0)
      ..quadraticBezierTo(125.0, 245.0, 130.0, 220.0)
      ..quadraticBezierTo(145.0, 250.0, 185.0, 260.0)
      ..quadraticBezierTo(155.0, 235.0, 155.0, 205.0)
      ..quadraticBezierTo(175.0, 235.0, 220.0, 240.0)
      ..lineTo(285.0, 250.0)
      ..close();

    final headWithNotch = Path.combine(PathOperation.difference, head, notch);

    final handle = Path()
      ..moveTo(270.0, 242.0)
      ..lineTo(300.0, 225.0)
      ..lineTo(405.0, 420.0)
      ..lineTo(365.0, 445.0)
      ..close();

    final hammer = Path.combine(PathOperation.union, headWithNotch, handle);

    final holes = Path()
      ..addOval(Rect.fromCircle(center: const Offset(250.0, 190.0), radius: 42.0))
      ..addOval(Rect.fromCircle(center: const Offset(330.0, 150.0), radius: 20.0))
      ..addOval(Rect.fromCircle(center: const Offset(380.0, 125.0), radius: 11.0));

    final finalHammer = Path.combine(PathOperation.difference, hammer, holes);
    canvas.drawPath(finalHammer, white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
