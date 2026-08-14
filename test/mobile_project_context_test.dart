import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/atlas_project_context.dart';
import 'package:hermes_android/core/services/atlas_project_port.dart';

const projectId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> context({
  String profileId = 'pro',
  String id = projectId,
}) => {
  'contract': 'atlas.mobile-project-context.v1',
  'project_identity_authority': 'document-service',
  'profile_identity_authority': 'profile-service',
  'coordination_authority': 'coordination-core',
  'project_id': id,
  'profile_id': profileId,
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
};

class FakeProjectPort implements AtlasProjectPort {
  List<Map<String, dynamic>> projects;
  int bindingCalls = 0;

  FakeProjectPort(this.projects);

  @override
  Future<List<Map<String, dynamic>>> listProjectContexts({
    required String canonicalProfileId,
    String? query,
  }) async => projects;

  @override
  Future<Map<String, dynamic>> requestConversationBinding({
    required String canonicalProfileId,
    required String conversationId,
    required String projectId,
    required String idempotencyKey,
  }) async {
    bindingCalls++;
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
    raw['core'] = {
      ...(raw['core'] as Map<String, dynamic>),
      'objective': 'authorization=hidden',
    };
    expect(() => MobileProjectContext.fromJson(raw), throwsFormatException);
  });

  test(
    'controller rejects cross-profile and duplicate Project results',
    () async {
      await expectLater(
        ProjectCatalogController(
          FakeProjectPort([context(profileId: 'personal')]),
        ).list(canonicalProfileId: 'pro'),
        throwsFormatException,
      );
      await expectLater(
        ProjectCatalogController(
          FakeProjectPort([context(), context()]),
        ).list(canonicalProfileId: 'pro'),
        throwsFormatException,
      );
    },
  );

  test(
    'malformed profile, query and binding inputs fail before provider use',
    () async {
      final port = FakeProjectPort([context()]);
      final controller = ProjectCatalogController(port);
      await expectLater(
        controller.list(canonicalProfileId: 'Local Phone'),
        throwsFormatException,
      );
      await expectLater(
        controller.list(canonicalProfileId: 'pro', query: ' token=hidden'),
        throwsFormatException,
      );
      final project = MobileProjectContext.fromJson(context());
      await expectLater(
        controller.bind(
          project: project,
          conversationId: 'bad session',
          idempotencyKey: 'binding-request-1',
        ),
        throwsFormatException,
      );
      expect(port.bindingCalls, 0);
    },
  );

  test('binding request reuses existing endpoint identities', () async {
    final port = FakeProjectPort([context()]);
    final controller = ProjectCatalogController(port);
    final project = (await controller.list(canonicalProfileId: 'pro')).single;
    final receipt = await controller.bind(
      project: project,
      conversationId: 'mob-existing-session',
      idempotencyKey: 'binding-request-1',
    );
    expect(receipt.projectId, projectId);
    expect(receipt.profileId, 'pro');
    expect(port.bindingCalls, 1);
  });

  test(
    'binding response must be the registered active relationship shape',
    () async {
      final port = FakeProjectPort([context()]);
      final controller = ProjectCatalogController(port);
      final project = MobileProjectContext.fromJson(context());
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
      await expectLater(
        controller.bind(
          project: project,
          conversationId: 'mob-existing-session',
          idempotencyKey: 'binding-request-1',
        ),
        completes,
      );
    },
  );
}
