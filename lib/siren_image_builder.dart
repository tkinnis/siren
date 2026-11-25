import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart'
    show ImageNode;
import 'package:path/path.dart' as p;
import 'package:vector_graphics/vector_graphics_compat.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

import 'image_zoom_dialog.dart';
import 'mermaid_zoom_dialog.dart' show CompiledMermaidBytesLoader;

Map<String, String> _parseSvgAttributes(String rawAttributes) {
  final attrRegex = RegExp(
    r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
  );
  final attrs = <String, String>{};
  for (final match in attrRegex.allMatches(rawAttributes)) {
    final key = match.group(1)!.toLowerCase();
    final val = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    attrs[key] = val;
  }
  return attrs;
}

class _CompiledSvgResult {
  const _CompiledSvgResult({
    required this.compiledBytes,
    required this.normalizedSvg,
    required this.logicalWidth,
    required this.logicalHeight,
  });

  final Uint8List compiledBytes;
  final String normalizedSvg;
  final double logicalWidth;
  final double logicalHeight;
}

class _NetworkImagePayload {
  final Uint8List bytes;
  final String contentType;
  final bool isSvg;
  final String? svgXml;

  const _NetworkImagePayload({
    required this.bytes,
    required this.contentType,
    required this.isSvg,
    this.svgXml,
  });
}

/// Normalizes SVG XML (including `img.shields.io` badges with embedded
/// `data:image/svg+xml;base64,...` `<image>` logos, `<linearGradient>` stops
/// without `stop-color`, and `<text transform="scale(.1)">` typography) into
/// pure SVG 1.1 primitives and compiles them into `vector_graphics` bytecode.
class _SvgVectorService {
  _SvgVectorService._();

  static final _SvgVectorService instance = _SvgVectorService._();

  static const int _maxCacheEntries = 128;
  static const String _browserUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
  static const String _browserAcceptHeader =
      'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8';

  final LinkedHashMap<String, _CompiledSvgResult> _cache =
      LinkedHashMap<String, _CompiledSvgResult>();
  final LinkedHashMap<String, _NetworkImagePayload> _payloadCache =
      LinkedHashMap<String, _NetworkImagePayload>();
  final Map<String, Future<_NetworkImagePayload?>> _payloadInFlight =
      <String, Future<_NetworkImagePayload?>>{};
  final Map<String, Future<_CompiledSvgResult?>> _inFlight =
      <String, Future<_CompiledSvgResult?>>{};

  static String buildCacheKey(
    String sourceKey,
    double? targetWidth,
    double? targetHeight,
  ) => '$sourceKey|w=${targetWidth ?? 'auto'}|h=${targetHeight ?? 'auto'}';

  _CompiledSvgResult? peek(String cacheKey) {
    final existing = _cache.remove(cacheKey);
    if (existing != null) {
      _cache[cacheKey] = existing;
    }
    return existing;
  }

  _NetworkImagePayload? peekPayload(String url) {
    final existing = _payloadCache.remove(url);
    if (existing != null) {
      _payloadCache[url] = existing;
    }
    return existing;
  }

  void _putCache(String key, _CompiledSvgResult value) {
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _putPayloadCache(String url, _NetworkImagePayload value) {
    _payloadCache.remove(url);
    _payloadCache[url] = value;
    while (_payloadCache.length > _maxCacheEntries) {
      _payloadCache.remove(_payloadCache.keys.first);
    }
  }

  Future<_NetworkImagePayload?> fetchNetworkPayload(String url) {
    final cached = peekPayload(url);
    if (cached != null) {
      return Future<_NetworkImagePayload?>.value(cached);
    }
    final inFlight = _payloadInFlight[url];
    if (inFlight != null) {
      return inFlight;
    }
    final future = _doFetchNetworkPayload(url);
    _payloadInFlight[url] = future;
    return future.whenComplete(() {
      _payloadInFlight.remove(url);
    });
  }

  Future<_NetworkImagePayload?> _doFetchNetworkPayload(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
      request.headers.set(HttpHeaders.acceptHeader, _browserAcceptHeader);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(response)
          .timeout(const Duration(seconds: 10));
      if (bytes.isEmpty) {
        return null;
      }
      final contentType =
          response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      final isSvg = SirenImageBuilder.isSvgPayload(
        contentType: contentType,
        bytes: bytes,
      );
      final payload = _NetworkImagePayload(
        bytes: bytes,
        contentType: contentType,
        isSvg: isSvg,
        svgXml: isSvg ? utf8.decode(bytes, allowMalformed: true) : null,
      );
      _putPayloadCache(url, payload);
      return payload;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<_CompiledSvgResult?> compileSvg({
    required String cacheKey,
    required String svgXml,
    double? targetWidth,
    double? targetHeight,
  }) {
    final cached = peek(cacheKey);
    if (cached != null) {
      return Future<_CompiledSvgResult?>.value(cached);
    }
    final existing = _inFlight[cacheKey];
    if (existing != null) {
      return existing;
    }

    final future =
        Future<_CompiledSvgResult?>(() {
          return compileSvgXml(
            svgXml: svgXml,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
          );
        }).then((result) {
          _inFlight.remove(cacheKey);
          if (result != null) {
            _putCache(cacheKey, result);
          }
          return result;
        });

    _inFlight[cacheKey] = future;
    return future;
  }

  static final RegExp _rootSvgRegex = RegExp(
    r'<svg\b([^>]*)>',
    caseSensitive: false,
  );
  static final RegExp _nestedImageSvgRegex = RegExp(
    r'<image\b([^>]*?)(?:/>|>[\s\S]*?</image>)',
    caseSensitive: false,
  );
  static final RegExp _innerSvgContentRegex = RegExp(
    r'<svg\b([^>]*)>([\s\S]*?)</svg>',
    caseSensitive: false,
  );
  static final RegExp _stripTitleDescRegex = RegExp(
    r'<(?:title|desc|metadata)\b[^>]*>[\s\S]*?</(?:title|desc|metadata)>',
    caseSensitive: false,
  );
  static final RegExp _stopTagRegex = RegExp(
    r'<stop\b([^>]*?)/?>',
    caseSensitive: false,
  );
  static final RegExp _filterElementRegex = RegExp(
    r'<filter\b[^>]*>[\s\S]*?</filter>',
    caseSensitive: false,
  );
  static final RegExp _filteredTextRegex = RegExp(
    r'<text\b[^>]*\bfilter\s*=\s*(?:"[^"]*"|'
    r"'[^']*')"
    r'[^>]*>[\s\S]*?</text>',
    caseSensitive: false,
  );
  static final RegExp _groupOrTextTokenRegex = RegExp(
    r'<(/?g)\b([^>]*?)(/?)>|<text\b([^>]*)>([\s\S]*?)</text>',
    caseSensitive: false,
  );
  static final RegExp _scaleTransformRegex = RegExp(
    r'^scale\(\s*([0-9.]+)(?:[\s,]+([0-9.]+))?\s*\)$',
    caseSensitive: false,
  );

  static double? _parsePositiveNum(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.endsWith('%')) return null;
    final cleaned = trimmed.replaceFirst(
      RegExp(r'(?:px|pt)$', caseSensitive: false),
      '',
    );
    final val = double.tryParse(cleaned);
    return (val != null && val.isFinite && val > 0) ? val : null;
  }

  static String _formatSvgNum(double value) {
    final rounded = (value * 1000).round() / 1000;
    if (rounded == rounded.roundToDouble()) {
      return rounded.round().toString();
    }
    return rounded.toString();
  }

  static String _inlineNestedSvgDataImages(String svg) {
    return svg.replaceAllMapped(_nestedImageSvgRegex, (match) {
      final rawAttrs = match.group(1) ?? '';
      final attrs = _parseSvgAttributes(rawAttrs);
      final href = (attrs['href'] ?? attrs['xlink:href'] ?? '').trim();
      if (!href.toLowerCase().startsWith('data:image/svg+xml')) {
        return match.group(0)!;
      }

      final commaIdx = href.indexOf(',');
      if (commaIdx < 0) return match.group(0)!;
      final header = href.substring(0, commaIdx).toLowerCase();
      final payloadPart = href.substring(commaIdx + 1).trim();

      String decodedSvg;
      try {
        if (header.contains(';base64')) {
          final cleanBase64 = payloadPart.replaceAll(RegExp(r'\s+'), '');
          decodedSvg = utf8.decode(
            base64Decode(cleanBase64),
            allowMalformed: true,
          );
        } else {
          decodedSvg = Uri.decodeFull(payloadPart);
        }
      } catch (_) {
        return match.group(0)!;
      }

      final innerMatch = _innerSvgContentRegex.firstMatch(decodedSvg);
      if (innerMatch == null) return match.group(0)!;

      final innerAttrs = _parseSvgAttributes(innerMatch.group(1) ?? '');
      final innerBody = (innerMatch.group(2) ?? '').replaceAll(
        _stripTitleDescRegex,
        '',
      );
      if (innerBody.trim().isEmpty) return '';

      final x = double.tryParse(attrs['x'] ?? '') ?? 0.0;
      final y = double.tryParse(attrs['y'] ?? '') ?? 0.0;
      final w = _parsePositiveNum(attrs['width']) ?? 14.0;
      final h = _parsePositiveNum(attrs['height']) ?? 14.0;

      double vw = _parsePositiveNum(innerAttrs['width']) ?? 24.0;
      double vh = _parsePositiveNum(innerAttrs['height']) ?? 24.0;
      double vx = 0.0;
      double vy = 0.0;
      final vb = innerAttrs['viewbox'];
      if (vb != null) {
        final parts = vb
            .trim()
            .split(RegExp(r'[\s,]+'))
            .map(double.tryParse)
            .toList();
        if (parts.length == 4 &&
            parts[0] != null &&
            parts[1] != null &&
            parts[2] != null &&
            parts[3] != null &&
            parts[2]! > 0 &&
            parts[3]! > 0) {
          vx = parts[0]!;
          vy = parts[1]!;
          vw = parts[2]!;
          vh = parts[3]!;
        }
      }

      final sx = w / vw;
      final sy = h / vh;
      final transforms = <String>[
        if (x != 0 || y != 0)
          'translate(${_formatSvgNum(x)}, ${_formatSvgNum(y)})',
        if ((sx - 1.0).abs() > 1e-4 || (sy - 1.0).abs() > 1e-4)
          'scale(${_formatSvgNum(sx)}, ${_formatSvgNum(sy)})',
        if (vx != 0 || vy != 0)
          'translate(${_formatSvgNum(-vx)}, ${_formatSvgNum(-vy)})',
      ];

      final groupAttrs = StringBuffer();
      if (transforms.isNotEmpty) {
        groupAttrs.write(' transform="${transforms.join(' ')}"');
      }
      for (final key in const [
        'fill',
        'stroke',
        'stroke-width',
        'stroke-linecap',
        'stroke-linejoin',
      ]) {
        final val = innerAttrs[key];
        if (val != null && val.isNotEmpty) {
          groupAttrs.write(' $key="$val"');
        }
      }
      return '<g$groupAttrs>$innerBody</g>';
    });
  }

  static String? _resolveSvgFontFamily(String? rawFamily) {
    if (rawFamily == null) return null;
    for (final candidate in rawFamily.split(',')) {
      var cleaned = candidate.trim();
      if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
          (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
        cleaned = cleaned.substring(1, cleaned.length - 1).trim();
      }
      if (cleaned.isEmpty) continue;
      final lower = cleaned.toLowerCase();
      if (lower == 'sans-serif' ||
          lower == 'serif' ||
          lower == 'monospace' ||
          lower == 'system-ui') {
        continue;
      }
      return cleaned;
    }
    return null;
  }

  static String _normalizeBadgeTextGroups(String svg) {
    final cleaned = svg
        .replaceAll(_filterElementRegex, '')
        .replaceAll(_filteredTextRegex, '');

    final stack =
        <
          ({
            double scaleX,
            double scaleY,
            double? rawFontSize,
            String? fill,
            String? fillOpacity,
            String? textAnchor,
            String? fontFamily,
          })
        >[];

    return cleaned.replaceAllMapped(_groupOrTextTokenRegex, (match) {
      final groupTag = match.group(1);
      if (groupTag != null) {
        if (groupTag.toLowerCase() == '/g') {
          if (stack.isNotEmpty) {
            stack.removeLast();
          }
          return '</g>';
        }

        final groupRawAttrs = match.group(2) ?? '';
        final selfClose = match.group(3) ?? '';
        final groupAttrs = _parseSvgAttributes(groupRawAttrs);
        final parent = stack.isNotEmpty
            ? stack.last
            : (
                scaleX: 1.0,
                scaleY: 1.0,
                rawFontSize: null,
                fill: null,
                fillOpacity: null,
                textAnchor: null,
                fontFamily: null,
              );

        double ownScaleX = 1.0;
        double ownScaleY = 1.0;
        final transformAttr = groupAttrs['transform']?.trim();
        if (transformAttr != null) {
          final scaleMatch = _scaleTransformRegex.firstMatch(transformAttr);
          if (scaleMatch != null) {
            final sx = double.tryParse(scaleMatch.group(1) ?? '');
            final sy = double.tryParse(
              scaleMatch.group(2) ?? scaleMatch.group(1) ?? '',
            );
            if (sx != null && sx > 0 && sy != null && sy > 0) {
              ownScaleX = sx;
              ownScaleY = sy;
              groupAttrs.remove('transform');
            }
          }
        }

        final ownFontSize = _parsePositiveNum(groupAttrs['font-size']);
        if (ownFontSize != null) {
          groupAttrs.remove('font-size');
        }

        final resolvedFamily = _resolveSvgFontFamily(groupAttrs['font-family']);
        if (resolvedFamily != null) {
          groupAttrs['font-family'] = resolvedFamily;
        }

        final nextFrame = (
          scaleX: parent.scaleX * ownScaleX,
          scaleY: parent.scaleY * ownScaleY,
          rawFontSize: ownFontSize ?? parent.rawFontSize,
          fill: groupAttrs['fill'] ?? parent.fill,
          fillOpacity: groupAttrs['fill-opacity'] ?? parent.fillOpacity,
          textAnchor: groupAttrs['text-anchor'] ?? parent.textAnchor,
          fontFamily: resolvedFamily ?? parent.fontFamily,
        );

        if (selfClose != '/') {
          stack.add(nextFrame);
        }

        final attrBuf = StringBuffer();
        groupAttrs.forEach((k, v) {
          attrBuf.write(' $k="$v"');
        });
        return '<g$attrBuf$selfClose>';
      }

      final textRawAttrs = match.group(4) ?? '';
      final textContent = match.group(5) ?? '';
      final textAttrs = _parseSvgAttributes(textRawAttrs);
      final frame = stack.isNotEmpty
          ? stack.last
          : (
              scaleX: 1.0,
              scaleY: 1.0,
              rawFontSize: null,
              fill: null,
              fillOpacity: null,
              textAnchor: null,
              fontFamily: null,
            );

      double ownScaleX = 1.0;
      double ownScaleY = 1.0;
      final transformAttr = textAttrs['transform']?.trim();
      if (transformAttr != null) {
        final scaleMatch = _scaleTransformRegex.firstMatch(transformAttr);
        if (scaleMatch != null) {
          final sx = double.tryParse(scaleMatch.group(1) ?? '');
          final sy = double.tryParse(
            scaleMatch.group(2) ?? scaleMatch.group(1) ?? '',
          );
          if (sx != null && sx > 0 && sy != null && sy > 0) {
            ownScaleX = sx;
            ownScaleY = sy;
            textAttrs.remove('transform');
          }
        }
      }

      final effScaleX = frame.scaleX * ownScaleX;
      final effScaleY = frame.scaleY * ownScaleY;

      final baseFontSize =
          _parsePositiveNum(textAttrs['font-size']) ?? frame.rawFontSize;
      if (baseFontSize != null) {
        textAttrs['font-size'] = _formatSvgNum(baseFontSize * effScaleY);
      }

      if (effScaleX != 1.0 || effScaleY != 1.0) {
        final xVal = double.tryParse(textAttrs['x'] ?? '');
        final yVal = double.tryParse(textAttrs['y'] ?? '');
        if (xVal != null) {
          textAttrs['x'] = _formatSvgNum(xVal * effScaleX);
        }
        if (yVal != null) {
          textAttrs['y'] = _formatSvgNum(yVal * effScaleY);
        }
      }

      textAttrs.remove('textlength');
      textAttrs.remove('lengthadjust');
      textAttrs.remove('filter');

      if (!textAttrs.containsKey('fill') && frame.fill != null) {
        textAttrs['fill'] = frame.fill!;
      }
      if (!textAttrs.containsKey('fill-opacity') && frame.fillOpacity != null) {
        textAttrs['fill-opacity'] = frame.fillOpacity!;
      }
      if (!textAttrs.containsKey('text-anchor') && frame.textAnchor != null) {
        textAttrs['text-anchor'] = frame.textAnchor!;
      }
      final textFamily =
          _resolveSvgFontFamily(textAttrs['font-family']) ?? frame.fontFamily;
      if (textFamily != null) {
        textAttrs['font-family'] = textFamily;
      }

      final attrBuf = StringBuffer();
      textAttrs.forEach((k, v) {
        attrBuf.write(' $k="$v"');
      });
      return '<text$attrBuf>$textContent</text>';
    });
  }

  static String _ensureGradientStopColors(String svg) {
    if (!svg.contains('<stop')) return svg;
    return svg.replaceAllMapped(_stopTagRegex, (match) {
      final rawAttrs = match.group(1) ?? '';
      if (RegExp(
        r'\bstop-color\s*=',
        caseSensitive: false,
      ).hasMatch(rawAttrs)) {
        return match.group(0)!;
      }
      final full = match.group(0)!;
      if (full.endsWith('/>')) {
        return '<stop$rawAttrs stop-color="#000000"/>';
      }
      return '<stop$rawAttrs stop-color="#000000">';
    });
  }

  static _CompiledSvgResult? compileSvgXml({
    required String svgXml,
    double? targetWidth,
    double? targetHeight,
  }) {
    final rootMatch = _rootSvgRegex.firstMatch(svgXml);
    if (rootMatch == null) return null;

    final rootAttrs = _parseSvgAttributes(rootMatch.group(1) ?? '');
    double? naturalW = _parsePositiveNum(rootAttrs['width']);
    double? naturalH = _parsePositiveNum(rootAttrs['height']);
    final vbAttr = rootAttrs['viewbox'];
    if (vbAttr != null) {
      final parts = vbAttr
          .trim()
          .split(RegExp(r'[\s,]+'))
          .map(double.tryParse)
          .toList();
      if (parts.length == 4 &&
          parts[2] != null &&
          parts[3] != null &&
          parts[2]! > 0 &&
          parts[3]! > 0) {
        naturalW ??= parts[2];
        naturalH ??= parts[3];
      }
    }

    naturalW ??= 100.0;
    naturalH ??= 20.0;

    double logicalW = (targetWidth != null && targetWidth > 0)
        ? targetWidth
        : 0.0;
    double logicalH = (targetHeight != null && targetHeight > 0)
        ? targetHeight
        : 0.0;
    if (logicalW > 0 && logicalH <= 0) {
      logicalH = logicalW * (naturalH / naturalW);
    } else if (logicalH > 0 && logicalW <= 0) {
      logicalW = logicalH * (naturalW / naturalH);
    } else if (logicalW <= 0 && logicalH <= 0) {
      logicalW = naturalW;
      logicalH = naturalH;
    }

    var normalized = _normalizeBadgeTextGroups(svgXml);
    normalized = _inlineNestedSvgDataImages(normalized);
    normalized = _ensureGradientStopColors(normalized);

    if (vbAttr == null) {
      normalized = normalized.replaceFirstMapped(_rootSvgRegex, (m) {
        return '<svg${m.group(1)} viewBox="0 0 ${_formatSvgNum(naturalW!)} ${_formatSvgNum(naturalH!)}">';
      });
    }

    try {
      final compiledBytes = vg.encodeSvg(
        xml: normalized,
        debugName: 'markdown_svg',
        theme: const vg.SvgTheme(),
        enableClippingOptimizer: false,
        enableMaskingOptimizer: false,
        enableOverdrawOptimizer: false,
      );
      return _CompiledSvgResult(
        compiledBytes: compiledBytes,
        normalizedSvg: normalized,
        logicalWidth: logicalW,
        logicalHeight: logicalH,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Renders a browser/GitHub-style broken image fallback that preserves the
/// `alt` text in the surrounding typography (such as inside an `<h1>`).
class _BrokenImageFallback extends StatelessWidget {
  final String? altText;
  final String? semanticsLabel;

  const _BrokenImageFallback({this.altText, this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    final cleanAlt = altText?.trim() ?? '';
    final label = semanticsLabel?.trim() ?? cleanAlt;
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final iconColor =
        inheritedStyle.color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    return Semantics(
      label: label.isNotEmpty
          ? 'Image failed to load: $label'
          : 'Image failed to load',
      child: cleanAlt.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  size: (inheritedStyle.fontSize ?? 16.0).clamp(16.0, 28.0),
                  color: iconColor.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 6.0),
                Flexible(child: Text(cleanAlt, style: inheritedStyle)),
              ],
            )
          : Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: iconColor.withValues(alpha: 0.65),
            ),
    );
  }
}

/// Loads network or local SVG/raster images by inspecting the HTTP
/// `Content-Type` header and payload bytes rather than guessing from URL paths.
class _BrowserSvgImage extends StatefulWidget {
  final String? networkUrl;
  final File? localFile;
  final double? width;
  final double? height;
  final String? semanticsLabel;
  final String? altText;

  const _BrowserSvgImage({
    this.networkUrl,
    this.localFile,
    this.width,
    this.height,
    this.semanticsLabel,
    this.altText,
  });

  @override
  State<_BrowserSvgImage> createState() => _BrowserSvgImageState();
}

class _BrowserSvgImageState extends State<_BrowserSvgImage> {
  _CompiledSvgResult? _svgResult;
  Uint8List? _rasterBytes;
  String? _fallbackSvgXml;
  bool _failed = false;
  bool _loading = true;

  String get _cacheKey => _SvgVectorService.buildCacheKey(
    widget.networkUrl ?? widget.localFile?.path ?? '',
    widget.width,
    widget.height,
  );

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _BrowserSvgImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.localFile?.path != widget.localFile?.path ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final key = _cacheKey;
    final cachedSvg = _SvgVectorService.instance.peek(key);
    if (cachedSvg != null) {
      setState(() {
        _svgResult = cachedSvg;
        _rasterBytes = null;
        _fallbackSvgXml = null;
        _loading = false;
        _failed = false;
      });
      return;
    }

    if (widget.networkUrl != null) {
      final cachedPayload = _SvgVectorService.instance.peekPayload(
        widget.networkUrl!,
      );
      if (cachedPayload != null && !cachedPayload.isSvg) {
        setState(() {
          _rasterBytes = cachedPayload.bytes;
          _svgResult = null;
          _fallbackSvgXml = null;
          _loading = false;
          _failed = false;
        });
        return;
      }
    }

    setState(() {
      _loading = true;
      _failed = false;
      _svgResult = null;
      _rasterBytes = null;
      _fallbackSvgXml = null;
    });

    String? svgXml;
    if (widget.networkUrl != null) {
      final payload = await _SvgVectorService.instance.fetchNetworkPayload(
        widget.networkUrl!,
      );
      if (!mounted) return;
      if (payload == null) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      if (!payload.isSvg) {
        setState(() {
          _rasterBytes = payload.bytes;
          _loading = false;
          _failed = false;
        });
        return;
      }
      svgXml = payload.svgXml;
    } else if (widget.localFile != null) {
      try {
        svgXml = await widget.localFile!.readAsString();
      } catch (_) {
        svgXml = null;
      }
    }

    if (!mounted) return;
    if (svgXml == null || svgXml.trim().isEmpty) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }

    final compiledSvg = await _SvgVectorService.instance.compileSvg(
      cacheKey: key,
      svgXml: svgXml,
      targetWidth: widget.width,
      targetHeight: widget.height,
    );

    if (!mounted) return;
    if (compiledSvg != null) {
      setState(() {
        _svgResult = compiledSvg;
        _loading = false;
        _failed = false;
      });
    } else {
      setState(() {
        _fallbackSvgXml = svgXml;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_svgResult != null) {
      return createCompatVectorGraphic(
        loader: CompiledMermaidBytesLoader(_svgResult!.compiledBytes),
        width: _svgResult!.logicalWidth,
        height: _svgResult!.logicalHeight,
        fit: BoxFit.contain,
        strategy: RenderingStrategy.picture,
        semanticsLabel: widget.semanticsLabel,
      );
    }

    if (_rasterBytes != null) {
      return Image.memory(
        _rasterBytes!,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: widget.semanticsLabel,
        errorBuilder: (context, error, stackTrace) => _BrokenImageFallback(
          altText: widget.altText,
          semanticsLabel: widget.semanticsLabel,
        ),
      );
    }

    if (_fallbackSvgXml != null) {
      return SvgPicture.string(
        _fallbackSvgXml!,
        width: widget.width,
        height: widget.height,
        semanticsLabel: widget.semanticsLabel,
      );
    }

    if (_loading) {
      return SizedBox(
        width: widget.width ?? 80.0,
        height: widget.height ?? 20.0,
      );
    }

    if (_failed) {
      return _BrokenImageFallback(
        altText: widget.altText,
        semanticsLabel: widget.semanticsLabel,
      );
    }

    return const SizedBox.shrink();
  }
}

/// Custom image builder for `MarkdownView` handling Siren's local path
/// resolution, HTTP Content-Type/payload SVG detection, `img.shields.io` vector
/// badge compilation, and the interactive [ImageZoomDialog] lightbox.
class SirenImageBuilder {
  final String basePath;
  final String? explorerRootPath;

  const SirenImageBuilder({
    required this.basePath,
    required this.explorerRootPath,
  });

  /// Normalizes and compiles arbitrary SVG XML (including `img.shields.io`
  /// badges with embedded `data:image/svg+xml` `<image>` logos and scaled text)
  /// into `vector_graphics` bytecode.
  @visibleForTesting
  static ({
    Uint8List compiledBytes,
    String normalizedSvg,
    double width,
    double height,
  })?
  compileSvgBadge(String svgXml, {double? width, double? height}) {
    final result = _SvgVectorService.compileSvgXml(
      svgXml: svgXml,
      targetWidth: width,
      targetHeight: height,
    );
    if (result == null) return null;
    return (
      compiledBytes: result.compiledBytes,
      normalizedSvg: result.normalizedSvg,
      width: result.logicalWidth,
      height: result.logicalHeight,
    );
  }

  /// Determines whether an HTTP response or file payload is SVG XML by
  /// inspecting the MIME `Content-Type` and leading bytes (ignoring URL paths
  /// or file extensions).
  @visibleForTesting
  static bool isSvgPayload({
    required String? contentType,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty) return false;

    // Fast path for binary raster magic bytes (PNG, JPEG, GIF, WebP)
    if (bytes.length >= 4) {
      // PNG: 89 50 4E 47
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return false;
      }
      // JPEG: FF D8 FF
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return false;
      }
      // GIF: 'GIF8'
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38) {
        return false;
      }
      // WebP: 'RIFF'....'WEBP'
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return false;
      }
    }

    final lowerType = (contentType ?? '').toLowerCase();
    if (lowerType.contains('image/svg+xml')) {
      return true;
    }

    final sampleLen = bytes.length > 2048 ? 2048 : bytes.length;
    final head = utf8
        .decode(bytes.sublist(0, sampleLen), allowMalformed: true)
        .replaceFirst('\uFEFF', '')
        .trimLeft();

    if (head.isEmpty) return false;
    if (RegExp(r'^<svg[\s>]', caseSensitive: false).hasMatch(head)) {
      return true;
    }
    if ((head.startsWith('<?xml') ||
            RegExp(r'^<!DOCTYPE\s+svg', caseSensitive: false).hasMatch(head) ||
            head.startsWith('<!--')) &&
        RegExp(r'<svg[\s>]', caseSensitive: false).hasMatch(head) &&
        !RegExp(
          r'<!DOCTYPE\s+html|<html[\s>]',
          caseSensitive: false,
        ).hasMatch(head)) {
      return true;
    }
    return false;
  }

  static bool _isLocalSvgFile(File file) {
    if (file.path.toLowerCase().endsWith('.svg')) {
      return true;
    }
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final sample = raf.readSync(512);
        return isSvgPayload(contentType: null, bytes: sample);
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  File? _resolveLocalFile(String localPath) {
    final decoded = Uri.decodeComponent(localPath);
    if (decoded.isEmpty) return null;
    final cleanRel = decoded.startsWith('/') ? decoded.substring(1) : decoded;
    final primaryPath = p.normalize(p.join(basePath, decoded));
    final primaryFile = File(primaryPath);
    if (primaryFile.existsSync()) return primaryFile;

    if (explorerRootPath != null && explorerRootPath!.isNotEmpty) {
      final rootCandidate = p.normalize(p.join(explorerRootPath!, cleanRel));
      final rootFile = File(rootCandidate);
      if (rootFile.existsSync()) return rootFile;
    }

    // Walk up ancestor directories (up to 4 levels or repository root) so
    // repo-root-relative paths (e.g. 'assets/images/...') resolve even when a
    // subfolder like 'docs/' is opened as the Explorer workspace root.
    if (basePath.isNotEmpty) {
      String currentDir = p.normalize(p.absolute(basePath));
      for (int depth = 0; depth < 4; depth++) {
        final parentDir = p.dirname(currentDir);
        if (parentDir == currentDir) break;
        currentDir = parentDir;
        final candidate = File(p.normalize(p.join(currentDir, cleanRel)));
        if (candidate.existsSync()) return candidate;
        if (Directory(p.join(currentDir, '.git')).existsSync()) {
          break;
        }
      }
    }
    return null;
  }

  static Uint8List? _decodeSafeDataImage(String destination) {
    final commaIdx = destination.indexOf(',');
    if (commaIdx < 0) return null;
    final header = destination.substring(0, commaIdx).toLowerCase();
    if (!header.contains(';base64')) return null;
    try {
      final payload = destination
          .substring(commaIdx + 1)
          .replaceAll(RegExp(r'\s+'), '');
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  /// Builds a Flutter widget for an allowed [ImageNode], matching
  /// [MarkdownImageBuilder].
  Widget build(BuildContext context, ImageNode node) {
    final activeSrc = node.destination.trim();
    final uri = Uri.tryParse(activeSrc);
    if (uri == null || activeSrc.isEmpty) {
      return const SizedBox.shrink();
    }

    final alt = node.alt;
    final title = node.title;
    final width = node.width?.toDouble();
    final height = node.height?.toDouble();

    final label = alt.trim().isNotEmpty
        ? alt.trim()
        : (title != null && title.trim().isNotEmpty
              ? title.trim()
              : (uri.path.isNotEmpty ? p.basename(uri.path) : 'Image'));

    final isInFlutterTest =
        Platform.environment.containsKey('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains(
          'TestWidgetsFlutterBinding',
        );
    final isNetwork =
        uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');

    if (isNetwork) {
      final urlStr = uri.toString();
      final Widget imageWidget;
      if (isInFlutterTest) {
        imageWidget = Semantics(
          key: ValueKey<String>('network_image_$urlStr'),
          label: alt.isNotEmpty ? alt : label,
          image: true,
          child: SizedBox(
            width: width,
            height: height ?? 20.0,
            child: Text(alt.isNotEmpty ? alt : label),
          ),
        );
      } else {
        imageWidget = _BrowserSvgImage(
          networkUrl: urlStr,
          width: width,
          height: height,
          semanticsLabel: alt.isNotEmpty ? alt : label,
          altText: alt,
        );
      }
      return SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
          child: imageWidget,
        ),
      );
    }

    if (uri.scheme == 'data') {
      final bytes = _decodeSafeDataImage(activeSrc);
      if (bytes == null) {
        return _BrokenImageFallback(
          altText: alt,
          semanticsLabel: alt.isNotEmpty ? alt : label,
        );
      }
      final imageWidget = Image.memory(
        bytes,
        width: width,
        height: height,
        fit: BoxFit.contain,
        semanticLabel: alt.isEmpty ? null : alt,
        errorBuilder: (context, error, stackTrace) => _BrokenImageFallback(
          altText: alt,
          semanticsLabel: alt.isNotEmpty ? alt : label,
        ),
      );
      return SelectionContainer.disabled(
        child: Builder(
          builder: (ctx) {
            final insideLink =
                DefaultSelectionStyle.of(ctx).mouseCursor ==
                SystemMouseCursors.click;
            if (insideLink) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2.0,
                  vertical: 2.0,
                ),
                child: imageWidget,
              );
            }
            return MouseRegion(
              cursor: SystemMouseCursors.zoomIn,
              child: GestureDetector(
                onTap: () {
                  ImageZoomDialog.show(
                    ctx,
                    imageProvider: MemoryImage(bytes),
                    title: label,
                  );
                },
                child: imageWidget,
              ),
            );
          },
        ),
      );
    }

    final resolvedLocalFile = _resolveLocalFile(uri.path);
    if (resolvedLocalFile == null) {
      return _BrokenImageFallback(
        altText: alt,
        semanticsLabel: alt.isNotEmpty ? alt : label,
      );
    }

    final isLocalSvg = _isLocalSvgFile(resolvedLocalFile);
    if (isLocalSvg) {
      final Widget svgWidget;
      if (isInFlutterTest) {
        svgWidget = SvgPicture.file(
          resolvedLocalFile,
          width: width,
          height: height,
          semanticsLabel: alt.isEmpty ? null : alt,
        );
      } else {
        svgWidget = _BrowserSvgImage(
          localFile: resolvedLocalFile,
          width: width,
          height: height,
          semanticsLabel: alt.isNotEmpty ? alt : label,
          altText: alt,
        );
      }
      return SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
          child: svgWidget,
        ),
      );
    }

    final rasterWidget = Image.file(
      resolvedLocalFile,
      width: width,
      height: height,
      semanticLabel: alt.isEmpty ? null : alt,
      errorBuilder: (context, error, stackTrace) => _BrokenImageFallback(
        altText: alt,
        semanticsLabel: alt.isNotEmpty ? alt : label,
      ),
    );

    return SelectionContainer.disabled(
      child: Builder(
        builder: (ctx) {
          final insideLink =
              DefaultSelectionStyle.of(ctx).mouseCursor ==
              SystemMouseCursors.click;
          if (insideLink) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 2.0,
                vertical: 2.0,
              ),
              child: rasterWidget,
            );
          }
          return MouseRegion(
            cursor: SystemMouseCursors.zoomIn,
            child: GestureDetector(
              onTap: () {
                ImageZoomDialog.showFile(
                  ctx,
                  file: resolvedLocalFile,
                  title: label,
                );
              },
              child: rasterWidget,
            ),
          );
        },
      ),
    );
  }
}
