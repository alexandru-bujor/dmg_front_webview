import 'package:flutter/material.dart';
import 'webview_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DMGWebViewApp());
}

class DMGWebViewApp extends StatelessWidget {
  const DMGWebViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DMG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      home: const WebViewShell(
        startUrl: 'https://estimatemaster.pro/',
        firstPartyHosts: {
          'estimatemaster.pro',
          'www.estimatemaster.pro',
          'api.estimatemaster.pro',
          'dmg-api.vecdev.md',
        },
      ),
    );
  }
}
