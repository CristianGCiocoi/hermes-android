import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/native_add_connection_button.dart';

void main() {
  test('Android uses the native Add Connection accessibility target', () {
    expect(usesNativeAddConnectionTarget(isAndroid: true), isTrue);
    expect(usesNativeAddConnectionTarget(isAndroid: false), isFalse);
    expect(nativeAddConnectionViewType, 'hermes/native_add_connection');
    expect(nativeAddConnectionChannelPrefix, 'hermes/native_add_connection');
  });

  test('native target has stable id, description, and one click bridge', () {
    final source = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'NativeAddConnectionView.kt',
    ).readAsStringSync();
    final ids = File(
      'android/app/src/main/res/values/ids.xml',
    ).readAsStringSync();
    final strings = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'MainActivity.kt',
    ).readAsStringSync();

    expect(ids, contains('name="hermes_connection_add"'));
    expect(
      strings,
      contains('name="hermes_connection_add_content_description"'),
    );
    expect(strings, contains('>Add Connection</string>'));
    expect(source, contains('id = R.id.hermes_connection_add'));
    expect(source, contains('importantForAccessibility'));
    expect(source, contains('setOnClickListener'));
    expect(source, contains('channel.invokeMethod("pressed", null)'));
    expect(source, contains('pendingPress = true'));
    expect(source, contains('call.method != "ready"'));
    expect(source, contains('if (pendingPress)'));
    final dartSource = File(
      'lib/core/widgets/native_add_connection_button.dart',
    ).readAsStringSync();
    expect(dartSource, contains("invokeMethod<void>('ready')"));
    expect(activity, contains('registerViewFactory('));
    expect(activity, contains('NATIVE_ADD_CONNECTION_VIEW_TYPE'));
  });
}
