import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/atlas_project_context.dart';
import 'package:hermes_android/core/screens/projects_screen.dart';
import 'package:hermes_android/core/services/atlas_project_port.dart';

class ScreenPort implements AtlasProjectPort {
  final bool fail;
  final bool failBinding;
  static int bindingCalls = 0;
  const ScreenPort({this.fail = false, this.failBinding = false});

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
        'project_core': {
          'project_id': '11111111-1111-4111-8111-111111111111',
          'objective': 'Ship M2',
          'current_state': 'Development',
          'current_focus': 'Mobile',
          'open_questions': <String>[],
          'revision': 1,
          'updated_at': '2026-08-14T12:00:00Z',
          'updated_by': 'profile:$canonicalProfileId',
          'provenance': <String, dynamic>{},
        },
        'project_projection': {
          'project_id': '11111111-1111-4111-8111-111111111111',
          'profile_id': canonicalProfileId,
          'continuity_status': 'ACTIVE',
          'hermes_project_ref': null,
          'last_active_at': null,
          'revision': 1,
          'updated_at': '2026-08-14T12:00:00Z',
          'provenance': <String, dynamic>{},
        },
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> requestConversationBinding({
    required String canonicalProfileId,
    required String conversationId,
    required String projectId,
    required String idempotencyKey,
  }) async {
    bindingCalls++;
    if (failBinding) throw StateError('binding unavailable');
    return {
      'binding_id': '22222222-2222-4222-8222-222222222222',
      'conversation_id': conversationId,
      'profile_id': canonicalProfileId,
      'project_id': projectId,
      'binding_status': 'ACTIVE',
      'supersedes_binding_id': null,
      'revision': 1,
      'created_at': '2026-08-14T12:00:00Z',
      'updated_at': '2026-08-14T12:00:00Z',
      'ended_at': null,
      'provenance': <String, dynamic>{},
      'transition_provenance': {'correlation_id': idempotencyKey},
    };
  }
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

  testWidgets('conversation selection requests and verifies active binding', (
    tester,
  ) async {
    ScreenPort.bindingCalls = 0;
    MobileProjectContext? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          controller: ProjectCatalogController(const ScreenPort()),
          canonicalProfileId: 'pro',
          conversationId: 'existing-hermes-session',
          onProjectSelected: (project) => selected = project,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ATLAS'));
    await tester.pumpAndSettle();
    expect(ScreenPort.bindingCalls, 1);
    expect(selected?.projectId, '11111111-1111-4111-8111-111111111111');
    expect(find.byKey(const Key('project-selected')), findsOneWidget);
  });

  testWidgets('binding failure does not create a local Project selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          controller: ProjectCatalogController(
            const ScreenPort(failBinding: true),
          ),
          canonicalProfileId: 'pro',
          conversationId: 'existing-hermes-session',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ATLAS'));
    await tester.pumpAndSettle();
    expect(find.text('Project binding was not accepted.'), findsOneWidget);
    expect(find.byKey(const Key('project-selected')), findsNothing);
  });
}
