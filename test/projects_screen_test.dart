import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/atlas_project_context.dart';
import 'package:hermes_android/core/screens/projects_screen.dart';
import 'package:hermes_android/core/services/atlas_project_port.dart';

class ScreenPort implements AtlasProjectPort {
  final bool fail;
  const ScreenPort({this.fail = false});

  @override
  Future<List<Map<String, dynamic>>> listProjectContexts({
    required String canonicalProfileId,
    String? query,
  }) async {
    if (fail) throw StateError('provider unavailable');
    return [
      {
        'contract': 'atlas.mobile-project-context.v1',
        'project_identity_authority': 'document-service',
        'profile_identity_authority': 'profile-service',
        'coordination_authority': 'coordination-core',
        'project_id': '11111111-1111-4111-8111-111111111111',
        'profile_id': canonicalProfileId,
        'name': 'ATLAS',
        'slug': 'atlas',
        'core': {
          'objective': 'Ship M2',
          'current_state': 'Development',
          'current_focus': 'Mobile',
          'open_questions': <String>[],
        },
        'continuity_status': 'ACTIVE',
        'conversation_id': null,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> requestConversationBinding({
    required String canonicalProfileId,
    required String conversationId,
    required String projectId,
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

void main() {
  testWidgets('renders registered Project context without duplicate state', (
    tester,
  ) async {
    MobileProjectContext? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          controller: ProjectCatalogController(const ScreenPort()),
          canonicalProfileId: 'pro',
          onProjectSelected: (project) => selected = project,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ATLAS'), findsOneWidget);
    expect(find.text('Mobile'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    await tester.tap(find.text('ATLAS'));
    await tester.pump();
    expect(selected?.projectId, '11111111-1111-4111-8111-111111111111');
    expect(find.byKey(const Key('project-selected')), findsOneWidget);
  });

  testWidgets('provider failure degrades without creating local substitute', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          controller: ProjectCatalogController(const ScreenPort(fail: true)),
          canonicalProfileId: 'pro',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects-error')), findsOneWidget);
    expect(find.text('ATLAS'), findsNothing);
  });
}
