import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MermaidDiagram extends StatefulWidget {
  final String code;
  final bool isDark;

  const MermaidDiagram({super.key, required this.code, required this.isDark});

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  late final WebViewController _controller;
  double _height = 100;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'HeightChannel',
        onMessageReceived: (JavaScriptMessage message) {
          final double? newHeight = double.tryParse(message.message);
          if (newHeight != null && newHeight != _height) {
            if (mounted) {
              setState(() {
                _height = newHeight;
              });
            }
          }
        },
      )
      ..addJavaScriptChannel(
        'ScrollChannel',
        onMessageReceived: (JavaScriptMessage message) {
          final deltaY = double.tryParse(message.message);
          if (deltaY != null && mounted) {
            _forwardScroll(deltaY);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) {
              _updateHeight();
            }
          },
        ),
      )
      ..loadHtmlString(_getHtml(widget.code, widget.isDark));
  }

  void _updateHeight() async {
    // Small delay to ensure Mermaid has finished rendering
    await Future.delayed(const Duration(milliseconds: 500));
    await _controller.runJavaScript(
      'HeightChannel.postMessage(document.body.scrollHeight.toString());',
    );
  }

  void _forwardScroll(double deltaY) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != null && scrollable.position.hasPixels) {
      final newPos = scrollable.position.pixels + deltaY;
      scrollable.position.jumpTo(
        newPos.clamp(
          scrollable.position.minScrollExtent,
          scrollable.position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code || oldWidget.isDark != widget.isDark) {
      _controller.loadHtmlString(_getHtml(widget.code, widget.isDark));
    }
  }

  String _getHtml(String code, bool isDark) {
    // Escaping backticks and other characters in code
    final encodedCode = const HtmlEscape().convert(code);
    final theme = isDark ? 'dark' : 'default';
    final bgColor = isDark ? '#1E1E1E' : '#ffffff';

    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body { 
            margin: 0; 
            padding: 0; 
            background-color: $bgColor; 
            overflow: hidden; 
          }
          .mermaid { 
            display: flex; 
            justify-content: center; 
            padding: 10px;
          }
        </style>
        <script type="module">
          import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
          mermaid.initialize({
            startOnLoad: true,
            theme: '$theme',
            securityLevel: 'loose',
          });

          // Watch for changes and report height
          const observer = new ResizeObserver(entries => {
            HeightChannel.postMessage(document.body.scrollHeight.toString());
          });
          observer.observe(document.body);

          // Forward scroll events to Flutter
          document.addEventListener('wheel', (e) => {
            e.preventDefault();
            e.stopPropagation();
            ScrollChannel.postMessage(e.deltaY.toString());
          }, { passive: false });
        </script>
      </head>
      <body>
        <div class="mermaid">
          $encodedCode
        </div>
      </body>
      </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: WebViewWidget(controller: _controller),
    );
  }
}
