import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/projects_screen.dart';
import 'package:hermes_android/core/services/atlas_project_port.dart';

class ScreenHermesPort implements HermesProjectsPort {
  final bool fail;
  final String? initialActiveId;
  static int selectionCalls = 0;

  const ScreenHermesPort({this.fail = false, this.initialActiveId});

  @override
  Future<Map<String, dynamic>> listProjects() async {
    if (fail) throw StateError('native Projects unavailable');
    return {
      'active_id': initialActiveId,
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
  Future<Map<String, dynamic>> createProject({
    required String name,
    String? description,
    String? primaryPath,
    required bool use,
  }) => throw UnsupportedError('creation is not used by this fixture');

  @override
  Future<Map<String, dynamic>> setActiveProject(String hermesProjectId) async {
    selectionCalls++;
    return {'active_id': hermesProjectId};
  }
}

class CreatingScreenHermesPort implements HermesProjectsPort {
  final List<Map<String, dynamic>> projects = [];
  String? activeId;
  int createCalls = 0;
  bool malformedCreateResponse = false;

  @override
  Future<Map<String, dynamic>> listProjects() async => {
    'active_id': activeId,
    'projects': projects,
  };

  @override
  Future<Map<String, dynamic>> createProject({
    required String name,
    String? description,
    String? primaryPath,
    required bool use,
  }) async {
    createCalls++;
    if (malformedCreateResponse) return {'project': 'wrong-type'};
    final project = <String, dynamic>{
      'id': 'p_deadbeef',
      'slug': 'mobile-project',
      'name': name,
      'description': description,
      'icon': null,
      'color': null,
      'board_slug': null,
      'primary_path': primaryPath,
      'archived': false,
      'created_at': 2,
      'folders': [
        {'path': primaryPath, 'label': null, 'is_primary': true, 'added_at': 2},
      ],
    };
    projects.add(project);
    if (use) activeId = project['id'] as String;
    return {'project': project};
  }

  @override
  Future<Map<String, dynamic>> setActiveProject(String hermesProjectId) async {
    activeId = hermesProjectId;
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

  testWidgets(
    'ATLAS drawer can activate native Project without a conversation',
    (tester) async {
      ScreenAtlasPort.bindingCalls = 0;
      ScreenHermesPort.selectionCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectsScreen(
            controller: ProjectCatalogController(
              const ScreenHermesPort(),
              atlas: const ScreenAtlasPort(),
            ),
            canonicalProfileId: 'pro',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ATLAS'));
      await tester.pumpAndSettle();
      expect(ScreenAtlasPort.bindingCalls, 0);
      expect(ScreenHermesPort.selectionCalls, 1);
      expect(find.byKey(const Key('project-selected')), findsOneWidget);
    },
  );

  testWidgets('native active Project is represented on first render', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          controller: ProjectCatalogController(
            const ScreenHermesPort(initialActiveId: 'p_1234abcd'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
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

  testWidgets('creates a native Hermes Project and confirms active state', (
    tester,
  ) async {
    final port = CreatingScreenHermesPort();
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(controller: ProjectCatalogController(port)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New Hermes Project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-name-field')),
      'Mobile Project',
    );
    await tester.enterText(
      find.byKey(const Key('project-description-field')),
      'Created through the native Hermes contract',
    );
    await tester.enterText(
      find.byKey(const Key('project-main-folder-field')),
      '/workspace/mobile-project',
    );
    await tester.tap(find.byKey(const Key('create-hermes-project-submit')));
    await tester.pumpAndSettle();

    expect(port.createCalls, 1);
    expect(port.activeId, 'p_deadbeef');
    expect(find.text('Mobile Project'), findsOneWidget);
    expect(find.byKey(const Key('project-selected')), findsOneWidget);
    expect(find.text('Mobile Project created and set active.'), findsOneWidget);
  });

  testWidgets('rejects a relative main folder before calling the Gateway', (
    tester,
  ) async {
    final port = CreatingScreenHermesPort();
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(controller: ProjectCatalogController(port)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New Hermes Project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-name-field')),
      'Invalid Folder',
    );
    await tester.enterText(
      find.byKey(const Key('project-main-folder-field')),
      'relative/folder',
    );
    await tester.tap(find.byKey(const Key('create-hermes-project-submit')));
    await tester.pump();

    expect(port.createCalls, 0);
    expect(find.text('Use an absolute Gateway folder path.'), findsOneWidget);
  });

  testWidgets('duplicate name is fail-closed without a create RPC', (
    tester,
  ) async {
    final port = CreatingScreenHermesPort();
    port.projects.add({
      'id': 'p_1234abcd',
      'slug': 'existing',
      'name': 'Existing Project',
      'description': null,
      'icon': null,
      'color': null,
      'board_slug': null,
      'primary_path': null,
      'archived': false,
      'created_at': 1,
      'folders': <Object>[],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(controller: ProjectCatalogController(port)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New Hermes Project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-name-field')),
      ' existing project ',
    );
    await tester.enterText(
      find.byKey(const Key('project-main-folder-field')),
      '/workspace/existing',
    );
    await tester.tap(find.byKey(const Key('create-hermes-project-submit')));
    await tester.pumpAndSettle();

    expect(port.createCalls, 0);
    expect(
      find.text('A Hermes Project with this name already exists.'),
      findsOneWidget,
    );
  });
}
