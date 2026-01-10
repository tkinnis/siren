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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadHtmlString(_getHtml(widget.code, widget.isDark));
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

    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body { margin: 0; padding: 0; background-color: transparent; }
          .mermaid { display: flex; justify-content: center; }
        </style>
        <script type="module">
          import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
          mermaid.initialize({ startOnLoad: true, theme: '$theme' });
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
    // A fixed height is problematic for diagrams.
    // Ideally we'd get the height from the webview content.
    // For now, let's use a reasonable default or AspectRatio.
    // Better yet, we can use a JS channel to report height.

    // For this prototype, I'll set a fixed height that's scrollable if needed
    // or just large enough.

    return SizedBox(height: 300, child: WebViewWidget(controller: _controller));
  }
}
