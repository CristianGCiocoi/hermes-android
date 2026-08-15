import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/atlas_project_context.dart';
import 'package:hermes_android/core/services/atlas_project_port.dart';

const projectId = '11111111-1111-4111-8111-111111111111';
const otherProjectId = '33333333-3333-4333-8333-333333333333';

Map<String, dynamic> context({
  String profileId = 'pro',
  String id = projectId,
  String? hermesProjectId = 'p_1234abcd',
}) => {
  'contract': 'atlas.mobile-project-context.v1',
  'project_identity_authority': 'document-service',
  'profile_identity_authority': 'profile-service',
  'coordination_authority': 'coordination-core',
  'project_id': id,
  'profile_id': profileId,
  'name': 'ATLAS',
  'slug': 'atlas',
  'project_core': {
    'project_id': id,
    'objective': 'Ship M2',
    'current_state': 'Development',
    'current_focus': 'Mobile',
    'open_questions': <String>[],
    'revision': 1,
    'updated_at': '2026-08-14T12:00:00Z',
    'updated_by': 'profile:$profileId',
    'provenance': <String, dynamic>{},
  },
  'project_projection': {
    'project_id': id,
    'profile_id': profileId,
    'continuity_status': 'ACTIVE',
    'hermes_project_ref': hermesProjectId == null
        ? null
        : 'hermes-project://runtime/$hermesProjectId',
    'last_active_at': null,
    'revision': 1,
    'updated_at': '2026-08-14T12:00:00Z',
    'provenance': <String, dynamic>{},
  },
};

class FakeAtlasPort implements AtlasProjectEnrichmentPort {
  List<Map<String, dynamic>> projects;
  int bindingCalls = 0;
  String? lastIdempotencyKey;

  FakeAtlasPort(this.projects);

  @override
  Future<List<Map<String, dynamic>>> listProjectContexts({
    required String canonicalProfileId,
  }) async => projects;

  @override
  Future<Map<String, dynamic>> requestConversationBinding({
    required String canonicalProfileId,
    required String conversationId,
    required String projectId,
    required String idempotencyKey,
  }) async {
    bindingCalls++;
    lastIdempotencyKey = idempotencyKey;
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
      'provenance': {'changeset_id': 'CS-050'},
      'transition_provenance': {'correlation_id': idempotencyKey},
    };
  }
}

class FakeHermesPort implements HermesProjectsPort {
  final List<Map<String, dynamic>> projects;
  String? activeId;

  FakeHermesPort({List<Map<String, dynamic>>? projects})
    : projects = projects ?? [nativeProject()];

  @override
  Future<Map<String, dynamic>> listProjects() async => {
    'projects': projects,
    'active_id': activeId,
  };

  @override
  Future<Map<String, dynamic>> setActiveProject(String hermesProjectId) async {
    activeId = hermesProjectId;
    return {'active_id': hermesProjectId};
  }
}

Map<String, dynamic> nativeProject({String id = 'p_1234abcd'}) => {
  'id': id,
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
};

void main() {
  test('accepts only registered authorities and canonical Project UUID', () {
    final item = MobileProjectContext.fromJson(context());
    expect(item.projectId, projectId);
    expect(item.profileId, 'pro');

    expect(
      () => MobileProjectContext.fromJson({
        ...context(),
        'project_identity_authority': 'mobile',
      }),
      throwsFormatException,
    );
    expect(
      () =>
          MobileProjectContext.fromJson({...context(), 'project_id': 'local'}),
      throwsFormatException,
    );
  });

  test('rejects forbidden state, device authority and secret material', () {
    for (final key in [
      'tasks',
      'decisions',
      'documents',
      'transcript',
      'device_id',
    ]) {
      expect(
        () => MobileProjectContext.fromJson({...context(), key: 'forbidden'}),
        throwsFormatException,
      );
    }
    final raw = context();
    raw['project_core'] = {
      ...(raw['project_core'] as Map<String, dynamic>),
      'objective': 'authorization=hidden',
    };
    expect(() => MobileProjectContext.fromJson(raw), throwsFormatException);
  });

  test('rejects mixed-owner Project Core and ProjectProjection records', () {
    final mixedCore = context();
    mixedCore['project_core'] = {
      ...(mixedCore['project_core'] as Map<String, dynamic>),
      'project_id': otherProjectId,
    };
    expect(
      () => MobileProjectContext.fromJson(mixedCore),
      throwsFormatException,
    );

    final mixedProjection = context();
    mixedProjection['project_projection'] = {
      ...(mixedProjection['project_projection'] as Map<String, dynamic>),
      'profile_id': 'personal',
    };
    expect(
      () => MobileProjectContext.fromJson(mixedProjection),
      throwsFormatException,
    );
  });

  test('rejects URI userinfo credentials in text and provenance', () {
    for (final leak in [
      'https://user:password@example.test/project',
      'https://user%3Apassword@example.test/project',
      'https://opaque-token@example.test/project',
    ]) {
      final textLeak = context();
      textLeak['name'] = leak;
      expect(
        () => MobileProjectContext.fromJson(textLeak),
        throwsFormatException,
      );
    }
    final provenanceLeak = context();
    provenanceLeak['project_projection'] = {
      ...(provenanceLeak['project_projection'] as Map<String, dynamic>),
      'provenance': {'source_ref': 'https://user:pass@example.test/project'},
    };
    expect(
      () => MobileProjectContext.fromJson(provenanceLeak),
      throwsFormatException,
    );
  });

  test(
    'Project Core field and timestamp constraints match mobile contract',
    () {
      for (final mutation in [
        {'objective': ''},
        {'updated_by': 'x'},
        {'updated_at': '0000-01-01T00:00:00Z'},
        {'updated_at': '2025-02-29T00:00:00Z'},
        {'updated_at': '2026-04-31T00:00:00Z'},
        {'updated_at': '2026-08-14T12:00:00+99:99'},
      ]) {
        final raw = context();
        raw['project_core'] = {
          ...(raw['project_core'] as Map<String, dynamic>),
          ...mutation,
        };
        expect(
          () => MobileProjectContext.fromJson(raw),
          throwsFormatException,
          reason: '$mutation',
        );
      }
      final valid = context();
      valid['project_core'] = {
        ...(valid['project_core'] as Map<String, dynamic>),
        'updated_at': '0001-01-01T00:00:00Z',
      };
      expect(MobileProjectContext.fromJson(valid).core?.revision, 1);
    },
  );

  test('default Hermes Projects work without any ATLAS extension', () async {
    final native = FakeHermesPort();
    final controller = ProjectCatalogController(native);
    final project = (await controller.list()).single;

    expect(project.hermesProjectId, 'p_1234abcd');
    expect(project.canonicalProjectId, isNull);
    expect(project.atlasContext, isNull);
    expect(
      await controller.select(
        project: project,
        canonicalProfileId: null,
        conversationId: null,
      ),
      isNull,
    );
    expect(native.activeId, 'p_1234abcd');
  });

  test('native active Project is preserved and validated', () async {
    final native = FakeHermesPort()..activeId = 'p_1234abcd';
    final project = (await ProjectCatalogController(native).list()).single;
    expect(project.isActive, isTrue);

    native.activeId = 'p_deadbeef';
    await expectLater(
      ProjectCatalogController(native).list(),
      throwsFormatException,
    );
  });

  test('native workspace metadata is strictly bounded and secret-free', () {
    for (final mutation in [
      {'icon': 1},
      {'color': 'x' * 65},
      {'board_slug': 'not valid'},
      {'primary_path': 'x' * 2049},
      {'primary_path': 'credential=hidden'},
      {
        'folders': [1],
      },
      {'folders': List.filled(129, 'workspace')},
      {
        'folders': ['authorization=hidden'],
      },
      {'created_at': -1},
    ]) {
      expect(
        () => HermesProject.fromNativeJson({...nativeProject(), ...mutation}),
        throwsFormatException,
        reason: '$mutation',
      );
    }
  });

  test(
    'ATLAS-enriched native selection needs binding only for a conversation',
    () async {
      final atlas = FakeAtlasPort([context()]);
      final native = FakeHermesPort();
      final controller = ProjectCatalogController(native, atlas: atlas);
      final project = (await controller.list(canonicalProfileId: 'pro')).single;

      expect(
        await controller.select(
          project: project,
          canonicalProfileId: 'pro',
          conversationId: null,
        ),
        isNull,
      );
      expect(atlas.bindingCalls, 0);
      expect(native.activeId, 'p_1234abcd');
    },
  );

  test(
    'ATLAS enrichment joins through ProjectProjection native binding only',
    () async {
      final controller = ProjectCatalogController(
        FakeHermesPort(),
        atlas: FakeAtlasPort([context()]),
      );
      final project = (await controller.list(canonicalProfileId: 'pro')).single;
      expect(project.hermesProjectId, 'p_1234abcd');
      expect(project.canonicalProjectId, projectId);
      expect(
        project.atlasContext?.projection?.hermesProjectRef,
        'hermes-project://runtime/p_1234abcd',
      );

      await expectLater(
        ProjectCatalogController(
          FakeHermesPort(),
          atlas: FakeAtlasPort([context(hermesProjectId: 'p_deadbeef')]),
        ).list(canonicalProfileId: 'pro'),
        throwsFormatException,
      );
    },
  );

  test(
    'controller rejects cross-profile and duplicate Project results',
    () async {
      await expectLater(
        ProjectCatalogController(
          FakeHermesPort(),
          atlas: FakeAtlasPort([context(profileId: 'personal')]),
        ).list(canonicalProfileId: 'pro'),
        throwsFormatException,
      );
      await expectLater(
        ProjectCatalogController(
          FakeHermesPort(),
          atlas: FakeAtlasPort([context(), context()]),
        ).list(canonicalProfileId: 'pro'),
        throwsFormatException,
      );
    },
  );

  test(
    'malformed profile, query and binding inputs fail before provider use',
    () async {
      final port = FakeAtlasPort([context()]);
      final controller = ProjectCatalogController(
        FakeHermesPort(),
        atlas: port,
      );
      await expectLater(
        controller.list(canonicalProfileId: 'Local Phone'),
        throwsFormatException,
      );
      await expectLater(
        controller.list(canonicalProfileId: 'pro', query: ' token=hidden'),
        throwsFormatException,
      );
      final project = (await controller.list(canonicalProfileId: 'pro')).single;
      await expectLater(
        controller.select(
          project: project,
          canonicalProfileId: 'pro',
          conversationId: 'bad session',
        ),
        throwsFormatException,
      );
      expect(port.bindingCalls, 0);
    },
  );

  test('binding request reuses existing endpoint identities', () async {
    final port = FakeAtlasPort([context()]);
    final native = FakeHermesPort();
    final controller = ProjectCatalogController(native, atlas: port);
    final project = (await controller.list(canonicalProfileId: 'pro')).single;
    final receipt = await controller.select(
      project: project,
      canonicalProfileId: 'pro',
      conversationId: 'mob-existing-session',
    );
    expect(receipt?.projectId, projectId);
    expect(receipt?.profileId, 'pro');
    expect(native.activeId, 'p_1234abcd');
    expect(port.bindingCalls, 1);
    final firstKey = port.lastIdempotencyKey;
    await controller.select(
      project: project,
      canonicalProfileId: 'pro',
      conversationId: 'mob-existing-session',
    );
    expect(port.lastIdempotencyKey, firstKey);
  });

  test(
    'binding response must be the registered active relationship shape',
    () async {
      final port = FakeAtlasPort([context()]);
      final controller = ProjectCatalogController(
        FakeHermesPort(),
        atlas: port,
      );
      final project = (await controller.list(canonicalProfileId: 'pro')).single;
      port.projects = [context()];
      final rawBinding = await port.requestConversationBinding(
        canonicalProfileId: 'pro',
        conversationId: 'mob-existing-session',
        projectId: projectId,
        idempotencyKey: 'binding-request-1',
      );
      expect(
        () => MobileConversationProjectBinding.fromJson({
          ...rawBinding,
          'transcript': 'forbidden',
        }),
        throwsFormatException,
      );
      expect(
        () => MobileConversationProjectBinding.fromJson({
          ...rawBinding,
          'transition_provenance': {'correlation_id': '"api_key":"raw"'},
        }),
        throwsFormatException,
      );
      expect(
        () => MobileConversationProjectBinding.fromJson({
          ...rawBinding,
          'created_at': '2026-08-14T12:00:01Z',
          'updated_at': '2026-08-14T12:00:00Z',
        }),
        throwsFormatException,
      );
      expect(
        MobileConversationProjectBinding.fromJson({
          ...rawBinding,
          'supersedes_binding_id': '44444444-4444-4444-8444-444444444444',
        }).status,
        'ACTIVE',
      );
      await expectLater(
        controller.select(
          project: project,
          canonicalProfileId: 'pro',
          conversationId: 'mob-existing-session',
        ),
        completes,
      );
    },
  );
}
