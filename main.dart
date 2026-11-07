import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFF000000)),
      home: const DshHome(),
    );
  }
}

class DshHome extends StatefulWidget {
  const DshHome({super.key});
  @override
  State<DshHome> createState() => _DshHomeState();
}

class _DshHomeState extends State<DshHome> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _ch = const MethodChannel('dsh/native');
  double? _progress = 0.0;
  String _status = '首次启动，正在下载核心环境(847MB)...';
  
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'sendStatus' && mounted) {
        setState(() => _status = call.arguments as String);
      }
    });
    _start();
  }
  
  Future<void> _start() async {
    // 哥们，把你原本的下载逻辑写在这里！
    // 记得下载进度更新时：setState(() => _progress = 下载百分比);
    // 下载完成后调用解压：
    // setState(() { _progress = null; _status = '正在解压...'; });
    // await _ch.invokeMethod('unzip', {'zipPath': '你的zip路径', 'destPath': '你的解压路径'});
  }
  
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) => CustomPaint(
              painter: StarFieldPainter(_ctrl.value * 10),
              size: MediaQuery.of(context).size,
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 190,
                        height: 190,
                        child: CircularProgressIndicator(
                          value: _progress,
                          strokeWidth: 4,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                        ),
                      ),
                      Container(
                        width: 170,
                        height: 170,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
                      ),
                      const Icon(Icons.gavel, size: 90, color: Colors.white),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                ExcludeSemantics(
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StarFieldPainter extends CustomPainter {
  final double time;
  StarFieldPainter(this.time);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final rand = Random(42);
    for (int i = 0; i < 80; i++) {
      final x = rand.nextDouble() * size.width;
      final y = rand.nextDouble() * size.height;
      final r = rand.nextDouble() * 1.5 + 0.5;
      final twinkle = (sin(time * 2 + i) + 1) / 2;
      paint.color = Colors.white.withOpacity(0.1 + twinkle * 0.7);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
    _drawCloud(canvas, Offset(size.width * 0.9, size.height * 0.25), 180, const Color(0xFF00E5FF));
    _drawCloud(canvas, Offset(size.width * 0.95, size.height * 0.85), 220, const Color(0xFF7C4DFF));
    _drawCloud(canvas, Offset(-size.width * 0.1, size.height * 0.7), 250, const Color(0xFF00E5FF));
  }
  void _drawCloud(Canvas canvas, Offset center, double radius, Color tint) {
    final paint = Paint()..isAntiAlias = true;
    paint.shader = RadialGradient(
      colors: [const Color(0xFF0B1021), Colors.transparent],
      stops: const [0.0, 0.8],
    ).createShader(Rect.fromCircle(center: center.translate(10, 20), radius: radius));
    canvas.drawCircle(center.translate(10, 20), radius, paint);
    paint.shader = RadialGradient(
      colors: [Colors.white.withOpacity(0.2), tint.withOpacity(0.1), tint.withOpacity(0.02), Colors.transparent],
      stops: const [0.0, 0.3, 0.6, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
    paint.shader = RadialGradient(
      colors: [Colors.white.withOpacity(0.35), Colors.white.withOpacity(0.0)],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromCircle(center: center.translate(-radius * 0.2, -radius * 0.2), radius: radius * 0.5));
    canvas.drawCircle(center.translate(-radius * 0.2, -radius * 0.2), radius * 0.5, paint);
    paint.shader = RadialGradient(
      colors: [tint.withOpacity(0.12), Colors.transparent],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromCircle(center: center.translate(radius * 0.4, radius * 0.3), radius: radius * 0.7));
    canvas.drawCircle(center.translate(radius * 0.4, radius * 0.3), radius * 0.7, paint);
  }
  @override
  bool shouldRepaint(covariant StarFieldPainter oldDelegate) => oldDelegate.time != time;
}
