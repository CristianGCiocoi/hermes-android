import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/projects_screen.dart';
import 'package:hermes_android/core/services/atlas_project_port.dart';

class ScreenHermesPort implements HermesProjectsPort {
  final bool fail;
  static int selectionCalls = 0;

  const ScreenHermesPort({this.fail = false});

  @override
  Future<Map<String, dynamic>> listProjects() async {
    if (fail) throw StateError('native Projects unavailable');
    return {
      'active_id': null,
      'projects': [
        {
          'id': 'p_1234abcd',
          'slug': 'atlas',
          'name': 'ATLAS',
          'description': 'Native Hermes workspace',
          'icon': null,
          'color': null,
          'board_slug': null,
          'primary_path': null,
          'archived': false,
          'created_at': 1,
          'folders': <Object>[],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> setActiveProject(String hermesProjectId) async {
    selectionCalls++;
    return {'active_id': hermesProjectId};
  }
}

class ScreenAtlasPort implements AtlasProjectEnrichmentPort {
  final bool failBinding;
  static int bindingCalls = 0;

  const ScreenAtlasPort({this.failBinding = false});

  @override
  Future<List<Map<String, dynamic>>> listProjectContexts({
    required String canonicalProfileId,
  }) async => [
    {
      'contract': 'atlas.mobile-project-context.v1',
      'project_identity_authority': 'document-service',
      'profile_identity_authority': 'profile-service',
      'coordination_authority': 'coordination-core',
      'project_id': '11111111-1111-4111-8111-111111111111',
      'profile_id': canonicalProfileId,
      'name': 'ATLAS canonical enrichment',
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
        'hermes_project_ref': 'hermes-project://runtime/p_1234abcd',
        'last_active_at': null,
        'revision': 1,
        'updated_at': '2026-08-14T12:00:00Z',
        'provenance': <String, dynamic>{},
      },
    },
  ];

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
  testWidgets('default Hermes mode uses native Projects without ATLAS', (
    tester,
  ) async {
    ScreenHermesPort.selectionCalls = 0;
    HermesProject? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          controller: ProjectCatalogController(const ScreenHermesPort()),
          onProjectSelected: (project) => selected = project,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ATLAS'), findsOneWidget);
    expect(find.text('Native Hermes workspace'), findsOneWidget);
    expect(find.text('ACTIVE'), findsNothing);
    await tester.tap(find.text('ATLAS'));
    await tester.pumpAndSettle();
    expect(selected?.hermesProjectId, 'p_1234abcd');
    expect(selected?.canonicalProjectId, isNull);
    expect(ScreenHermesPort.selectionCalls, 1);
  });

  testWidgets('ATLAS mode enriches the same native Project row', (
    tester,
  ) async {
    ScreenAtlasPort.bindingCalls = 0;
    HermesProject? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          controller: ProjectCatalogController(
            const ScreenHermesPort(),
            atlas: const ScreenAtlasPort(),
          ),
          canonicalProfileId: 'pro',
          conversationId: 'existing-hermes-session',
          onProjectSelected: (project) => selected = project,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ATLAS'), findsOneWidget);
    expect(find.text('Mobile'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    await tester.tap(find.text('ATLAS'));
    await tester.pumpAndSettle();
    expect(ScreenAtlasPort.bindingCalls, 1);
    expect(selected?.hermesProjectId, 'p_1234abcd');
    expect(
      selected?.canonicalProjectId,
      '11111111-1111-4111-8111-111111111111',
    );
    expect(find.byKey(const Key('project-selected')), findsOneWidget);
  });

  testWidgets('native provider failure creates no local substitute', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          controller: ProjectCatalogController(
            const ScreenHermesPort(fail: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('projects-error')), findsOneWidget);
    expect(find.text('ATLAS'), findsNothing);
  });

  testWidgets('ATLAS binding failure leaves native selection unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          controller: ProjectCatalogController(
            const ScreenHermesPort(),
            atlas: const ScreenAtlasPort(failBinding: true),
          ),
          canonicalProfileId: 'pro',
          conversationId: 'existing-hermes-session',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ATLAS'));
    await tester.pumpAndSettle();
    expect(find.text('Project selection was not accepted.'), findsOneWidget);
    expect(find.byKey(const Key('project-selected')), findsNothing);
  });
}
