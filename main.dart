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
                  // 🚨 关键修复：用 AspectRatio 锁死正方形，绝对不变形！
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: Container(
                      width: 160.0, // 控制整体大小
                      padding: const EdgeInsets.all(20.0),
                      child: CustomPaint(
                        painter: HammerDownPainter(),
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

// 🎨 完美重构：SCP 落锤标志
class HammerDownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double unit = 512.0;
    canvas.save();
    // 保证缩放比例一致
    canvas.scale(size.width / unit, size.height / unit);

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0
      ..isAntiAlias = true;

    // 1. 画外圈
    canvas.drawCircle(const Offset(256.0, 256.0), 235.0, strokePaint);

    // 2. 画锤头主体
    final head = Path()
      ..moveTo(50.0, 210.0)      // 左侧鸟嘴尖端
      ..lineTo(340.0, 70.0)      // 顶部斜边
      ..quadraticBezierTo(410.0, 50.0, 450.0, 120.0) // 右上角圆滑过渡
      ..lineTo(475.0, 180.0)     // 右侧边缘
      ..lineTo(280.0, 270.0)     // 锤头右下
      ..lineTo(100.0, 380.0)     // 锤头左下
      ..close();

    // 3. 挖掉左侧的波浪形缺口
    final notch = Path()
      ..moveTo(50.0, 210.0)      // 从尖端开始
      ..lineTo(100.0, 380.0)     // 连到底部
      ..lineTo(190.0, 330.0)     // 挖进内部
      ..quadraticBezierTo(140.0, 310.0, 130.0, 270.0) // 第一道弧
      ..quadraticBezierTo(170.0, 290.0, 210.0, 260.0) // 第二道弧
      ..lineTo(280.0, 270.0)     // 回到右侧
      ..close();

    final headWithNotch = Path.combine(PathOperation.difference, head, notch);

    // 4. 画锤柄（加粗加长）
    final handle = Path()
      ..moveTo(260.0, 270.0)     // 柄根左
      ..lineTo(320.0, 230.0)     // 柄根右
      ..lineTo(440.0, 460.0)     // 柄底右
      ..lineTo(380.0, 490.0)     // 柄底左
      ..close();

    // 5. 合并锤头与锤柄
    final hammer = Path.combine(PathOperation.union, headWithNotch, handle);

    // 6. 挖出三个圆孔（大、中、小）
    final holes = Path()
      ..addOval(Rect.fromCircle(center: const Offset(240.0, 190.0), radius: 45.0)) // 大孔
      ..addOval(Rect.fromCircle(center: const Offset(330.0, 140.0), radius: 22.0)) // 中孔
      ..addOval(Rect.fromCircle(center: const Offset(400.0, 100.0), radius: 10.0)); // 小孔

    final finalHammer = Path.combine(PathOperation.difference, hammer, holes);

    // 7. 绘制最终图形
    canvas.drawPath(finalHammer, whitePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
