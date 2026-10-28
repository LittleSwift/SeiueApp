import 'dart:async';

import 'package:flutter/painting.dart';

import 'models.dart';
import 'rich_document.dart';

/// Shared provider keys make a prefetched decode available to the reader.
ImageProvider noticeImageProvider(String url) =>
    ResizeImage.resizeIfNeeded(1600, null, NetworkImage(url));

class NoticeImagePreloader {
  final _queued = <String>[];
  final _seen = <String>{};
  int _active = 0, _generation = 0;
  bool _disposed = false;

  void enqueue(Iterable<CampusMessage> messages) {
    if (_disposed) return;
    for (final message in messages.where((message) => !message.cached)) {
      for (final block in parseDocument(message.content)) {
        for (final media in block.media.where((media) => media.image)) {
          if (_seen.add(media.url)) _queued.add(media.url);
        }
      }
    }
    _drain();
  }

  void _drain() {
    while (!_disposed && _active < 3 && _queued.isNotEmpty) {
      final url = _queued.removeAt(0), generation = _generation;
      _active++;
      unawaited(
        _warm(url)
            .catchError((Object _) {
              if (generation == _generation) _seen.remove(url);
            })
            .whenComplete(() {
              _active--;
              _drain();
            }),
      );
    }
  }

  Future<void> _warm(String url) async {
    final completer = Completer<void>();
    final stream = noticeImageProvider(url).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    try {
      await completer.future.timeout(const Duration(seconds: 20));
    } finally {
      stream.removeListener(listener);
    }
  }

  void reset() {
    _generation++;
    _queued.clear();
    _seen.clear();
  }

  void dispose() {
    reset();
    _disposed = true;
  }
}
