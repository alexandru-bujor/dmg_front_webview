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
  bool _isDisposed = false;

  bool get _safe => mounted && !_isDisposed;

  String get _mobileUA => Platform.isIOS
      ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
      : 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _pullToRefreshController = PullToRefreshController(onRefresh: () async {
      try {
        await _controller?.reload();
      } finally {
        _pullToRefreshController.endRefreshing();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller = null;
    super.dispose();
  }

  bool _isFirstParty(WebUri? u) {
    if (u == null) return false;
    final host = u.host.toLowerCase();
    return widget.firstPartyHosts.contains(host);
  }

  bool _isExternalScheme(WebUri u) {
    const schemes = {
      'mailto',
      'tel',
      'sms',
      'maps',
      'whatsapp',
      'tg',
      'viber',
      'intent',
      'market'
    };
    return schemes.contains(u.scheme.toLowerCase());
  }

  bool _isBlockedScheme(WebUri u) {
    final s = u.scheme.toLowerCase();
    const blocked = {'chrome-extension', 'chrome', 'devtools', 'about', 'blob', 'data'};
    if (blocked.contains(s)) return true;
    if (s == 'file') return true;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Connection or renderer issue'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                if (!_safe) return;
                setState(() => _offline = false);
                try {
                  await _controller?.reload();
                } catch (_) {}
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_offline) return _offlineView();

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Future<void>(() async {
          final c = _controller;
          if (c == null || !_safe) return;
          try {
            final canBack = await c.canGoBack();
            if (canBack) {
              await c.goBack();
            } else {
              if (_safe && context.mounted) Navigator.of(context).maybePop();
            }
          } catch (_) {}
        });
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

              /// Important for iOS popup links (target=_blank / window.open)
              supportMultipleWindows: true,
              javaScriptCanOpenWindowsAutomatically: true,

              /// Important for Android stability (fixes various picker crashes)
              android: AndroidInAppWebViewOptions(
                useHybridComposition: true, // ← reduces crashes with inputs/pickers
                builtInZoomControls: false,
                displayZoomControls: false,
                // Optional: improves forms
                domStorageEnabled: true,
                databaseEnabled: true,
                allowFileAccess: false,
                allowContentAccess: true,
              ),

              /// Disable Flutter’s default error page
              disableDefaultErrorPage: true,
            ),

            pullToRefreshController: _pullToRefreshController,

            onWebViewCreated: (c) {
              _controller = c;
            },

            onLoadStart: (c, _) {
              if (_safe && _offline) setState(() => _offline = false);
            },

            onLoadStop: (c, _) async {
              _pullToRefreshController.endRefreshing();

              // Force web-style <input type="time"> (prevents Android picker crashes)
              await c.evaluateJavascript(source: _forceWebTimeUiJs);

              // Keep all new windows in the same tab (prevents iOS → Safari)
              await c.evaluateJavascript(source: _forceSameTabJs);
            },

            onReceivedError: (c, request, error) {
              if (request.isForMainFrame == true && _safe) {
                setState(() => _offline = true);
              }
            },

            onReceivedHttpError: (c, request, response) {
              if (request.isForMainFrame == true) {
                debugPrint('[WEB HTTP ${response.statusCode}] ${request.url}');
              }
            },

            onRenderProcessGone: (controller, detail) async {
              if (_safe) setState(() => _offline = true);
              _controller = null;
            },

            onConsoleMessage: (c, msg) {
              debugPrint('[WEB ${msg.messageLevel}] ${msg.message}');
            },

            /// iOS new-window handler: load popup URLs in the SAME webview
            onCreateWindow: (c, req) async {
              final u = req.request.url;
              if (u != null) {
                try {
                  await c.loadUrl(urlRequest: URLRequest(url: u));
                } catch (_) {}
              }
              // We didn't create a new view – we consumed it.
              return false;
            },

            onCloseWindow: (c) async {
              // No new window was created; nothing to close.
            },

            onDownloadStartRequest: (c, req) async {
              await _handleExternal(Uri.parse(req.url.toString()));
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

              if (_isBlockedScheme(url)) return NavigationActionPolicy.CANCEL;

              // First-party → keep in-app
              if (_isFirstParty(url)) {
                // iOS LINK_ACTIVATED to same-view for consistency
                if (nav.androidIsRedirect == false &&
                    nav.iosWKNavigationType == IOSWKNavigationType.LINK_ACTIVATED) {
                  try {
                    await c.loadUrl(urlRequest: URLRequest(url: url));
                  } catch (_) {}
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              }

              // Android special schemes (intent / market)
              if (await _maybeHandleAndroidSpecial(url)) {
                return NavigationActionPolicy.CANCEL;
              }

              // External apps (tel:, mailto:, etc.)
              if (_isExternalScheme(url)) {
                await _handleExternal(Uri.parse(url.toString()));
                return NavigationActionPolicy.CANCEL;
              }

              // Other http(s): ask user before leaving app
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

                if (leave) await _handleExternal(Uri.parse(url.toString()));
                return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW;
            },
          ),
        ),
      ),
    );
  }

  // --- JS: force web-style time input (prevents native picker crashes on Android) ---
  String get _forceWebTimeUiJs => r'''
    (function () {
      if (window.__FORCE_WEB_TIME_UI__) return;
      window.__FORCE_WEB_TIME_UI__ = true;

      function upgrade(el) {
        if (!el || el.__web_time_upgraded) return;

        var val = el.value;
        var ph  = el.getAttribute('placeholder') || 'HH:MM';

        try { el.type = 'text'; } catch (e) {
          var n = el.cloneNode(true);
          n.setAttribute('type','text');
          el.parentNode && el.parentNode.replaceChild(n, el);
          el = n;
        }

        el.setAttribute('inputmode', 'numeric');
        el.setAttribute('pattern', '\\\\d{2}:\\\\d{2}');
        if (val && /^\d{2}:\d{2}$/.test(val)) el.value = val;
        if (!el.getAttribute('placeholder')) el.setAttribute('placeholder', ph);

        el.__web_time_upgraded = true;
      }

      function scan(root) {
        (root || document).querySelectorAll('input[type="time"]').forEach(upgrade);
      }

      scan(document);

      var obs = new MutationObserver(function (muts) {
        muts.forEach(function (m) {
          if (m.type === 'childList') {
            m.addedNodes && m.addedNodes.forEach(function (n) {
              if (n && n.nodeType === 1) scan(n);
            });
          } else if (m.type === 'attributes' && m.target && m.target.matches && m.target.matches('input[type="time"]')) {
            upgrade(m.target);
          }
        });
      });
      obs.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['type'] });

      var style = document.createElement('style');
      style.textContent = `
        input[type="time"]::-webkit-calendar-picker-indicator { display: none !important; }
        input[type="time"]::-webkit-clear-button { display: none !important; }
      `;
      document.documentElement.appendChild(style);
    })();
  ''';

  // --- JS: keep target=_blank / window.open inside the same tab (iOS & Android) ---
  String get _forceSameTabJs => r'''
    (function () {
      if (window.__FORCE_SAME_TAB__) return;
      window.__FORCE_SAME_TAB__ = true;

      var _open = window.open;
      window.open = function (url, name, specs) {
        try {
          if (typeof url === 'string' && url.length) {
            location.href = url;
            return null;
          }
        } catch (e) {}
        return _open.apply(window, arguments);
      };

      function retarget(root) {
        (root || document).querySelectorAll('a[target="_blank"]').forEach(function(a){
          a.setAttribute('target','_self');
        });
      }

      retarget(document);
      new MutationObserver(function(muts){
        muts.forEach(function(m){
          if (m.addedNodes) {
            m.addedNodes.forEach(function(n){
              if (n && n.querySelectorAll) retarget(n);
            });
          }
        });
      }).observe(document.documentElement, {subtree:true, childList:true});
    })();
  ''';
}
