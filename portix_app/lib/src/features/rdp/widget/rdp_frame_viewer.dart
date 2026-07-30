import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';

/// Simple viewer that listens to RDP frame stream and renders the latest
/// frame for a given session id.
class RdpFrameViewer extends StatefulWidget {
  const RdpFrameViewer({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<RdpFrameViewer> createState() => _RdpFrameViewerState();
}

class _RdpFrameViewerState extends State<RdpFrameViewer> {
  StreamSubscription<RdpFrameEvent>? _frameSub;
  StreamSubscription<RdpStatusEvent>? _statusSub;
  StreamSubscription<RdpErrorEvent>? _errorSub;
  ui.Image? _image;
  bool _loggedFrame = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final svc = sl<RdpBackendService>();
    // ignore: avoid_print
    print('RDP frame viewer subscribing to session ${widget.sessionId}');
    _frameSub = svc
        .frameStream()
        .where((f) => f.sessionId == widget.sessionId)
        .listen(
          _onFrame,
          onError: (error) {
            // ignore: avoid_print
            print('RDP frame listener error for ${widget.sessionId}: $error');
          },
          onDone: () {
            // ignore: avoid_print
            print('RDP frame listener done for ${widget.sessionId}');
          },
        );
    _statusSub = svc
        .statusStream()
        .where((event) => event.sessionId == widget.sessionId)
        .listen(
          _onStatus,
          onError: (error) {
            // ignore: avoid_print
            print('RDP status listener error for ${widget.sessionId}: $error');
          },
          onDone: () {
            // ignore: avoid_print
            print('RDP status listener done for ${widget.sessionId}');
          },
        );
    _errorSub = svc
        .errorStream()
        .where((event) => event.sessionId == widget.sessionId)
        .listen(
          _onErrorEvent,
          onError: (error) {
            // ignore: avoid_print
            print(
              'RDP error stream subscription error for ${widget.sessionId}: $error',
            );
          },
          onDone: () {
            // ignore: avoid_print
            print('RDP error stream done for ${widget.sessionId}');
          },
        );
  }

  Future<void> _onFrame(RdpFrameEvent frame) async {
    try {
      // ignore: avoid_print
      print(
        'RDP frame event: session=${frame.sessionId}, width=${frame.width}, height=${frame.height}, data=${frame.data.length}',
      );
      if (!_loggedFrame) {
        _loggedFrame = true;
      }
      final bytes = Uint8List.fromList(frame.data);
      final img = await decodeImageFromPixels(
        bytes,
        frame.width,
        frame.height,
        ui.PixelFormat.rgba8888,
      );
      if (!mounted) return;
      setState(() {
        _image = img;
      });
    } catch (error, stackTrace) {
      // ignore: avoid_print
      print('RDP frame decode failed for ${widget.sessionId}: $error');
      // ignore: avoid_print
      print(stackTrace);
    }
  }

  void _onStatus(RdpStatusEvent event) {
    // ignore: avoid_print
    print(
      'RDP status event: session=${event.sessionId}, status=${event.status}, message=${event.message}',
    );
    if (!mounted) return;
    setState(() {
      _statusMessage = event.message ?? event.status.name;
    });
  }

  void _onErrorEvent(RdpErrorEvent event) {
    // ignore: avoid_print
    print(
      'RDP error event: session=${event.sessionId}, message=${event.message}',
    );
    if (!mounted) return;
    setState(() {
      _statusMessage = 'Error: ${event.message}';
    });
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Waiting for frame...'),
            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          child: RawImage(image: _image),
        ),
        if (_statusMessage != null)
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

// Helper using dart:ui API
Future<ui.Image> decodeImageFromPixels(
  Uint8List pixels,
  int width,
  int height,
  ui.PixelFormat format,
) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, width, height, format, (img) {
    completer.complete(img);
  });
  return completer.future;
}
