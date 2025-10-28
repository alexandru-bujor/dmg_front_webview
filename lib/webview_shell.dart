// lib/webview_shell.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class WebViewShell extends StatefulWidget {
  final String startUrl;
  final Set<String> firstPartyHosts;

  const WebViewShell({
    super.key,
    required this.startUrl,
    this.firstPartyHosts = const {
      'estimatemaster.pro',
      'www.estimatemaster.pro',
      'api.estimatemaster.pro',
      'dmg-api.vecdev.md',
    },
  });

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

  // ---------- helpers ----------
  bool _isFirstParty(WebUri? u) {
    if (u == null) return false;
    return widget.firstPartyHosts.contains(u.host.toLowerCase());
  }

  bool _isExternalScheme(WebUri u) {
    const schemes = {
      'mailto', 'tel', 'sms', 'maps', 'whatsapp', 'tg', 'viber', 'intent', 'market'
    };
    return schemes.contains(u.scheme.toLowerCase());
  }

  bool _isBlockedScheme(WebUri u) {
    final s = u.scheme.toLowerCase();
    const blocked = {'chrome-extension', 'chrome', 'devtools', 'about', 'blob', 'data'};
    if (blocked.contains(s)) return true;
    if (s == 'file') return true; // block file:// unless explicitly allowed
    return false;
  }

  Future<bool> _maybeHandleAndroidSpecial(WebUri u) async {
    if (!Platform.isAndroid) return false;
    final s = u.scheme.toLowerCase();
    if (s == 'intent' || s == 'market') {
      return _handleExternal(Uri.parse(u.toString()));
    }
    return false;
  }

  Future<bool> _handleExternal(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  Widget _offlineView() {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Connection or renderer issue'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              if (!mounted) return;
              setState(() => _offline = false);
              await _controller?.reload();
            },
            child: const Text('Retry'),
          ),
        ]),
      ),
    );
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    if (_offline) return _offlineView();

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          await c.goBack();
        } else {
          if (context.mounted) Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: InAppWebView(
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
              supportMultipleWindows: false, // ⬅️ do NOT spawn child webviews
              disableDefaultErrorPage: true,
            ),
            pullToRefreshController: _pullToRefreshController,

            onWebViewCreated: (c) {
              _controller = c;
              // JS bridge (void methods — do not await)
              c.addJavaScriptHandler(
                handlerName: "log",
                callback: (args) {
                  debugPrint("[JS log] $args");
                  return null;
                },
              );
              c.addJavaScriptHandler(
                handlerName: "notify",
                callback: (args) => {"ok": true},
              );
              c.addJavaScriptHandler(
                handlerName: "pushToken",
                callback: (args) => {"stored": true},
              );
            },

            onLoadStop: (c, _) async {
              _pullToRefreshController.endRefreshing();
              if (!mounted) return;
              c.evaluateJavascript(source: _bridgeScript);
            },

            onReceivedError: (c, request, error) {
              // Offline only when top document fails
              if (request.isForMainFrame == true && mounted) {
                setState(() => _offline = true);
              }
            },

            onReceivedHttpError: (c, request, response) {
              if (request.isForMainFrame == true) {
                debugPrint('[WEB HTTP ${response.statusCode}] ${request.url}');
              }
            },

            // Renderer crash → recover gracefully
            onRenderProcessGone: (controller, detail) async {
              if (mounted) setState(() => _offline = true);
              // return type is Future<void> in 6.x → no return value
            },

            onConsoleMessage: (c, msg) {
              // ConsoleMessageLevel may not have `.name` in your version
              debugPrint('[WEB ${msg.messageLevel.toString()}] ${msg.message}');
            },

            // We don’t create child windows; let policy handle all nav
            onCreateWindow: (c, req) async {
              // Return false so target=_blank falls back to policy handler.
              return false;
            },

            onDownloadStartRequest: (c, req) async {
              final uri = Uri.parse(req.url.toString());
              await _handleExternal(uri);
            },

            onPermissionRequest: (c, req) async {
              return PermissionResponse(
                resources: req.resources,
                action: PermissionResponseAction.GRANT,
              );
            },

            shouldOverrideUrlLoading: (c, nav) async {
              final url = nav.request.url;
              if (url == null) return NavigationActionPolicy.ALLOW;

              // 🚫 Block unsupported/extension schemes
              if (_isBlockedScheme(url)) return NavigationActionPolicy.CANCEL;

              // ✅ First-party → load inside
              if (_isFirstParty(url)) {
                // If site attempted to open a popup, force same-view load.
                // (Avoids new WebViews which can crash on some devices.)
                if (nav.androidIsRedirect == false &&
                    nav.iosWKNavigationType == IOSWKNavigationType.LINK_ACTIVATED) {
                  c.loadUrl(urlRequest: URLRequest(url: url));
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              }

              // Android intent/market
              if (await _maybeHandleAndroidSpecial(url)) {
                return NavigationActionPolicy.CANCEL;
              }

              // External deeplinks
              if (_isExternalScheme(url)) {
                await _handleExternal(Uri.parse(url.toString()));
                return NavigationActionPolicy.CANCEL;
              }

              // Other http(s) → confirm leaving the app
              if (url.scheme.startsWith('http')) {
                if (!context.mounted) return NavigationActionPolicy.CANCEL;
                final leave = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Leave app?'),
                        content: Text('Open ${url.toString()} in external app?'),
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

                if (!context.mounted) return NavigationActionPolicy.CANCEL;
                if (leave) {
                  await _handleExternal(Uri.parse(url.toString()));
                }
                return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW;
            },
          ),
        ),
      ),
    );
  }

  String get _bridgeScript =>
      'window.FlutterBridge = { '
      'notify:(t,p)=>window.flutter_inappwebview.callHandler("notify",t,p), '
      'log:(e,p)=>window.flutter_inappwebview.callHandler("log",e,p), '
      'pushToken:(tok)=>window.flutter_inappwebview.callHandler("pushToken",tok) '
      '};';
}
