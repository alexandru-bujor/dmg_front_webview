import 'package:flutter/material.dart';
import 'webview_shell.dart';

void main() => runApp(const DMGWebViewApp());

class DMGWebViewApp extends StatelessWidget {
  const DMGWebViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DMG',
      debugShowCheckedModeBanner: false,
      home: const WebViewShell(startUrl: 'https://pdr.vecdev.md/'),
    );
  }
}
