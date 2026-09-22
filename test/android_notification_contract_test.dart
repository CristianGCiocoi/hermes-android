import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android notification bridge is generic and permission-aware', () {
    final source = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(source, contains('hermes.notification/local'));
    expect(source, contains('hermes_gateway_notifications'));
    expect(source, contains('requestNotificationPermission'));
    expect(source, contains('PERMISSION_DENIED'));
    expect(source, contains('DELIVERY_FAILED'));
    expect(source, contains('urn:hermes:android-delivery:'));
    expect(source.toLowerCase(), isNot(contains('atlas')));
    expect(source, isNot(contains('apiKey')));
    expect(source, isNot(contains('desktopGatewayUrl')));
  });
}
