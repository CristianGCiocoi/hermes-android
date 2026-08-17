import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('new generic connection has no implicit Desktop gateway', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add Connection'));
    await tester.pumpAndSettle();
    expect(find.text('Add Gateway Connection'), findsOneWidget);

    await tester.tap(find.text('Custom proxy and dashboard details'));
    await tester.pumpAndSettle();

    final desktopGateway = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Desktop Gateway URL (optional)',
      ),
    );
    expect(desktopGateway.controller?.text, isEmpty);
    expect(find.textContaining('192.168.1.193'), findsNothing);
  });

  test(
    'editing preserves an explicit empty Desktop gateway clear sentinel',
    () {
      // updateConnection distinguishes null (leave unchanged) from the empty
      // string (clear). Keep this contract pinned at the dialog boundary.
      expect(desktopGatewayUrlForConnectionSave('', isEditing: true), '');
      expect(desktopGatewayUrlForConnectionSave('', isEditing: false), isNull);
    },
  );
}
