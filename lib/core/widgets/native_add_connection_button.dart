import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accessibility/hermes_semantics_ids.dart';

const nativeAddConnectionViewType = 'hermes/native_add_connection';
const nativeAddConnectionChannelPrefix = 'hermes/native_add_connection';

bool usesNativeAddConnectionTarget({bool? isAndroid}) =>
    isAndroid ?? Platform.isAndroid;

class NativeAddConnectionButton extends StatefulWidget {
  final VoidCallback onPressed;

  const NativeAddConnectionButton({required this.onPressed, super.key});

  @override
  State<NativeAddConnectionButton> createState() =>
      _NativeAddConnectionButtonState();
}

class _NativeAddConnectionButtonState extends State<NativeAddConnectionButton> {
  MethodChannel? _channel;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'pressed' && mounted) {
      widget.onPressed();
    }
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$nativeAddConnectionChannelPrefix/$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (usesNativeAddConnectionTarget()) {
      return SizedBox.square(
        dimension: 56,
        child: AndroidView(
          viewType: nativeAddConnectionViewType,
          layoutDirection: TextDirection.ltr,
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      );
    }

    return Semantics(
      identifier: HermesSemanticsId.addConnection,
      container: true,
      button: true,
      label: 'Add Connection',
      onTap: widget.onPressed,
      child: FloatingActionButton(
        tooltip: 'Add Connection',
        onPressed: widget.onPressed,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}
