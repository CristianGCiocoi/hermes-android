import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/atlas_project_context.dart';

abstract interface class AtlasProjectPort {
  Future<List<Map<String, dynamic>>> listProjectContexts({
    required String canonicalProfileId,
    String? query,
  });

  Future<Map<String, dynamic>> requestConversationBinding({
    required String canonicalProfileId,
    required String conversationId,
    required String projectId,
    required String idempotencyKey,
  });
}

class ProjectCatalogController {
  final AtlasProjectPort _port;

  const ProjectCatalogController(this._port);

  Future<List<MobileProjectContext>> list({
    required String canonicalProfileId,
    String? query,
  }) async {
    if (!isCanonicalProfileId(canonicalProfileId)) {
      throw const FormatException('canonical profile is invalid');
    }
    final normalizedQuery = query?.trim();
    if (normalizedQuery != null &&
        normalizedQuery.isNotEmpty &&
        !isSafeProjectQuery(query!)) {
      throw const FormatException('project query is invalid');
    }
    final raw = await _port.listProjectContexts(
      canonicalProfileId: canonicalProfileId,
      query: normalizedQuery == null || normalizedQuery.isEmpty
          ? null
          : normalizedQuery,
    );
    if (raw.length > 500) throw const FormatException('too many projects');
    final projects = raw.map(MobileProjectContext.fromJson).toList();
    final ids = <String>{};
    for (final project in projects) {
      if (project.profileId != canonicalProfileId ||
          !ids.add(project.projectId)) {
        throw const FormatException('project scope or identity collision');
      }
    }
    return immutableProjects(projects);
  }

  Future<MobileConversationProjectBinding> bind({
    required MobileProjectContext project,
    required String conversationId,
  }) async {
    if (!isCanonicalConversationId(conversationId)) {
      throw const FormatException('binding request identity is invalid');
    }
    final digest = sha256.convert(
      utf8.encode(
        '${project.profileId}\n$conversationId\n${project.projectId}',
      ),
    );
    final idempotencyKey = 'mobile-project-bind:$digest';
    if (!isSafeIdempotencyKey(idempotencyKey)) {
      throw const FormatException('binding idempotency identity is invalid');
    }
    final raw = await _port.requestConversationBinding(
      canonicalProfileId: project.profileId,
      conversationId: conversationId,
      projectId: project.projectId,
      idempotencyKey: idempotencyKey,
    );
    final binding = MobileConversationProjectBinding.fromJson(raw);
    if (binding.projectId != project.projectId ||
        binding.profileId != project.profileId ||
        binding.conversationId != conversationId ||
        binding.status != 'ACTIVE') {
      throw const FormatException('binding receipt does not match request');
    }
    return binding;
  }
}
