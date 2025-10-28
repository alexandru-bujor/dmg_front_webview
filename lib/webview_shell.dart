import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class WebViewShell extends StatefulWidget {
  final String startUrl;
  const WebViewShell({super.key, required this.startUrl});

  @override
  State<WebViewShell> createState() => _WebViewShellState();
}

class _WebViewShellState extends State<WebViewShell> {
  late final PullToRefreshController _pullToRefreshController;
  InAppWebViewController? _controller;
  bool _offline = false;

  String get _mobileUA => Platform.isIOS
      ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
      : 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _pullToRefreshController = PullToRefreshController(onRefresh: () async {
      await _controller?.reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_offline) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('You are offline'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => setState(() => _offline = false),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          // WebUri is required by flutter_inappwebview 6.x
          initialUrlRequest: URLRequest(url: WebUri(widget.startUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: false,
            allowsInlineMediaPlayback: true,
            mediaPlaybackRequiresUserGesture: false,
            userAgent: _mobileUA,
            useOnDownloadStart: true,
            useOnLoadResource: true,
            sharedCookiesEnabled: true,
            thirdPartyCookiesEnabled: true,
            allowsBackForwardNavigationGestures: true,
          ),
          pullToRefreshController: _pullToRefreshController,
          onWebViewCreated: (c) async {
            _controller = c;
          },
          onLoadStop: (c, _) async {
            _pullToRefreshController.endRefreshing();
            await c.evaluateJavascript(source: _bridgeScript);
          },
          onPermissionRequest: (c, req) async {
            return PermissionResponse(
              resources: req.resources,
              action: PermissionResponseAction.GRANT,
            );
          },
          shouldOverrideUrlLoading: (c, nav) async {
            final url = nav.request.url; // WebUri?
            if (url == null) return NavigationActionPolicy.ALLOW;

            final host = url.host;
            final isLocal = host == 'localhost' && url.port == 3000;
            if (isLocal) return NavigationActionPolicy.ALLOW;

            // Handle external schemes (convert WebUri -> Uri for url_launcher)
            if (['mailto', 'tel', 'sms', 'maps', 'whatsapp', 'tg', 'intent']
                .contains(url.scheme)) {
              final asUri = Uri.parse(url.toString());
              if (await canLaunchUrl(asUri)) {
                await launchUrl(asUri, mode: LaunchMode.externalApplication);
                return NavigationActionPolicy.CANCEL;
              }
            }

            // Confirm leaving the app
            final leave = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Leave app?'),
                    content:
                        Text('Open ${url.toString()} in external app?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ) ??
                false;

            // Guard context after async gap
            if (!mounted) return NavigationActionPolicy.CANCEL;

            if (leave) {
              await launchUrl(
                Uri.parse(url.toString()),
                mode: LaunchMode.externalApplication,
              );
            }
            return NavigationActionPolicy.CANCEL;
          },
          // New signature in 6.x: (controller, request, error)
          onReceivedError: (c, request, error) {
            setState(() => _offline = true);
          },
        ),
      ),
    );
  }

  String get _bridgeScript =>
      'window.FlutterBridge = { notify:(t,p)=>window.flutter_inappwebview.callHandler("notify",t,p), log:(e,p)=>window.flutter_inappwebview.callHandler("log",e,p), pushToken:(tok)=>window.flutter_inappwebview.callHandler("pushToken",tok) };';
}
