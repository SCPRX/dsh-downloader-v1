import 'package:flutter/material.dart';
import 'dart:math' as math;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9C27B0), brightness: Brightness.dark)),
      home: const EnchantedScreen(),
    );
  }
}

class EnchantedScreen extends StatefulWidget {
  const EnchantedScreen({super.key});
  @override
  State<EnchantedScreen> createState() => _EnchantedScreenState();
}

class _EnchantedScreenState extends State<EnchantedScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('附魔落锤')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return SweepGradient(
                        colors: const [Colors.purple, Colors.blueAccent, Colors.pinkAccent, Colors.purple],
                        stops: const [0.0, 0.3, 0.7, 1.0],
                        transform: GradientRotation(_controller.value * 2 * math.pi),
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.srcIn,
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, color: Colors.red),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
            const Text("附魔成功！", style: TextStyle(color: Colors.purpleAccent, fontSize: 24)),
          ],
        ),
      ),
    );
  }
}
