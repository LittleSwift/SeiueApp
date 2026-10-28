import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'notice_images.dart';
import 'platform_services.dart';
import 'theme.dart';

class DocumentBlock {
  const DocumentBlock({
    required this.text,
    this.type = 'unstyled',
    this.styles = const [],
    this.links = const [],
    this.media = const [],
  });
  final String text, type;
  final List<Json> styles;
  final List<({String label, String url})> links;
  final List<({String label, String url, bool image})> media;
}

String? safeDocumentUrl(dynamic value) {
  if (value is! String || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty
      ? uri.toString()
      : null;
}

List<DocumentBlock> parseDocument(String content) {
  dynamic raw;
  try {
    raw = jsonDecode(content);
  } catch (_) {
    raw = null;
  }
  if (raw is! Map || raw['blocks'] is! List) {
    final plain = content
        .replaceAll(
          RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp('<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    final media = <({String label, String url, bool image})>[];
    for (final match in RegExp(
      r'''<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(content)) {
      final url = safeDocumentUrl(match.group(1));
      if (url != null) media.add((label: '通知图片', url: url, image: true));
    }
    return [
      ...plain.split('\n').map((text) => DocumentBlock(text: text)),
      if (media.isNotEmpty) DocumentBlock(text: '', media: media),
    ];
  }
  final entities = raw['entityMap'] is Map ? raw['entityMap'] as Map : {};
  return (raw['blocks'] as List).whereType<Map>().map((block) {
    final links = <({String label, String url})>[],
        media = <({String label, String url, bool image})>[];
    final text = '${block['text'] ?? ''}';
    for (final range
        in (block['entityRanges'] as List? ?? []).whereType<Map>()) {
      final entity = entities['${range['key']}'];
      if (entity is! Map || entity['data'] is! Map) continue;
      final data = entity['data'] as Map;
      final url = safeDocumentUrl(
        data['url'] ??
            data['src'] ??
            data['href'] ??
            data['downloadUrl'] ??
            data['download_url'],
      );
      if (url == null) continue;
      final type = '${entity['type']}'.toLowerCase();
      final offset = (range['offset'] as num? ?? 0).toInt().clamp(
        0,
        text.length,
      );
      final end = (offset + (range['length'] as num? ?? 0).toInt()).clamp(
        offset,
        text.length,
      );
      final label =
          '${data['name'] ?? data['fileName'] ?? data['filename'] ?? text.substring(offset, end)}';
      if (type.contains('image') ||
          type.contains('file') ||
          type.contains('attachment') ||
          type.contains('video')) {
        media.add((
          label: label.isEmpty
              ? (type.contains('image') ? '通知图片' : '查看附件')
              : label,
          url: url,
          image: type.contains('image'),
        ));
      } else {
        links.add((label: label.isEmpty ? '打开链接' : label, url: url));
      }
    }
    return DocumentBlock(
      text: text,
      type: '${block['type'] ?? 'unstyled'}',
      styles: (block['inlineStyleRanges'] as List? ?? [])
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList(),
      links: links,
      media: media,
    );
  }).toList();
}

class RichDocument extends StatelessWidget {
  const RichDocument({
    super.key,
    required this.content,
    required this.mac,
    this.plainText = false,
  });
  final String content;
  final MacServices mac;
  final bool plainText;
  Future<void> _open(BuildContext context, String url) async {
    try {
      await mac.openUrl(url);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开链接，请稍后重试。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context);
    final blocks = plainText
        ? content.split('\n').map((text) => DocumentBlock(text: text)).toList()
        : parseDocument(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) ...[
          if (block.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (block.type.contains('list-item'))
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 10),
                      child: Icon(
                        CupertinoIcons.circle_fill,
                        size: 5,
                        color: p.ink,
                      ),
                    ),
                  Expanded(
                    child: SelectableText.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: block.type.startsWith('header') ? 21 : 15,
                          height: 1.9,
                          fontWeight: block.type.startsWith('header')
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                        children: styledSpans(block, p),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (block.text.trim().isEmpty && block.media.isEmpty)
            const SizedBox(height: 12),
          for (final link in block.links)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: () => _open(context, link.url),
                icon: const Icon(CupertinoIcons.link, size: 16),
                label: Text(link.label, softWrap: true),
              ),
            ),
          for (final media in block.media)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: media.image
                  ? _DocumentImage(
                      url: media.url,
                      label: media.label,
                      onOpen: () => _open(context, media.url),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _open(context, media.url),
                      icon: const Icon(CupertinoIcons.doc, size: 18),
                      label: Text(media.label, softWrap: true),
                    ),
            ),
        ],
        if (!blocks.any((block) => block.links.isNotEmpty))
          for (final match in RegExp(
            r'https?://[^\s<>"\u3000]+',
          ).allMatches(blocks.map((block) => block.text).join('\n')).take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton.icon(
                onPressed: () => _open(context, match.group(0)!),
                icon: const Icon(
                  CupertinoIcons.arrow_up_right_square,
                  size: 16,
                ),
                label: Text(Uri.tryParse(match.group(0)!)?.host ?? '打开链接'),
              ),
            ),
      ],
    );
  }
}

List<TextSpan> styledSpans(DocumentBlock block, CampusPalette p) {
  if (block.styles.isEmpty) return [TextSpan(text: block.text)];
  final boundaries = <int>{0, block.text.length};
  for (final style in block.styles) {
    final start = (style['offset'] as num? ?? 0).toInt().clamp(
      0,
      block.text.length,
    );
    final end = (start + (style['length'] as num? ?? 0).toInt()).clamp(
      start,
      block.text.length,
    );
    boundaries.addAll([start, end]);
  }
  final points = boundaries.toList()..sort();
  return [
    for (int i = 0; i < points.length - 1; i++)
      TextSpan(
        text: block.text.substring(points[i], points[i + 1]),
        style: _styleAt(block, points[i], p),
      ),
  ];
}

TextStyle _styleAt(DocumentBlock block, int offset, CampusPalette p) {
  final styles = block.styles
      .where(
        (range) =>
            (range['offset'] as num? ?? 0) <= offset &&
            (range['offset'] as num? ?? 0) + (range['length'] as num? ?? 0) >
                offset,
      )
      .map((range) => '${range['style']}'.toUpperCase())
      .toSet();
  return TextStyle(
    fontWeight: styles.contains('BOLD') ? FontWeight.w700 : null,
    fontStyle: styles.contains('ITALIC') ? FontStyle.italic : null,
    decoration: styles.contains('UNDERLINE') ? TextDecoration.underline : null,
    color: styles.any((style) => style.contains('RED'))
        ? p.warm
        : styles.any((style) => style.contains('THEME'))
        ? p.primary
        : null,
  );
}

class _DocumentImage extends StatefulWidget {
  const _DocumentImage({
    required this.url,
    required this.label,
    required this.onOpen,
  });
  final String url, label;
  final VoidCallback onOpen;
  @override
  State<_DocumentImage> createState() => _DocumentImageState();
}

class _DocumentImageState extends State<_DocumentImage> {
  int attempt = 0;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: widget.onOpen,
    child: Image(
      key: ValueKey('${widget.url}:$attempt'),
      image: noticeImageProvider(widget.url),
      semanticLabel: widget.label,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : SizedBox(
              height: 160,
              child: Center(
                child: Semantics(
                  label: '正在加载通知图片',
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
      errorBuilder: (_, _, _) => Wrap(
        spacing: 12,
        children: [
          OutlinedButton(
            onPressed: () async {
              await noticeImageProvider(widget.url).evict();
              if (mounted) setState(() => attempt++);
            },
            child: const Text('图片加载失败，重试'),
          ),
          TextButton(onPressed: widget.onOpen, child: const Text('在浏览器查看')),
        ],
      ),
    ),
  );
}
