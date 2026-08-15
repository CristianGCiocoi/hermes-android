import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/atlas_project_context.dart';
import 'desktop_gateway_client.dart';

/// Native, per-profile Hermes Projects surface.
///
/// The identifier is owned by Hermes and is runtime/projection metadata. It is
/// never a canonical ATLAS Project identifier.
abstract interface class HermesProjectsPort {
  Future<Map<String, dynamic>> listProjects();

  Future<Map<String, dynamic>> setActiveProject(String hermesProjectId);
}

/// Optional ATLAS enrichment around the native Hermes Project abstraction.
///
/// This port owns no identity. Document Service remains canonical Project
/// authority and Coordination Core remains ProjectProjection/binding authority.
abstract interface class AtlasProjectEnrichmentPort {
  Future<List<Map<String, dynamic>>> listProjectContexts({
    required String canonicalProfileId,
  });

  Future<Map<String, dynamic>> requestConversationBinding({
    required String canonicalProfileId,
    required String conversationId,
    required String projectId,
    required String idempotencyKey,
  });
}

class HermesProject {
  final String hermesProjectId;
  final String slug;
  final String name;
  final String? description;
  final bool archived;
  final bool isActive;
  final MobileProjectContext? atlasContext;

  const HermesProject._({
    required this.hermesProjectId,
    required this.slug,
    required this.name,
    required this.description,
    required this.archived,
    required this.isActive,
    required this.atlasContext,
  });

  String? get canonicalProjectId => atlasContext?.projectId;

  factory HermesProject.fromNativeJson(Map<String, dynamic> value) {
    const allowed = {
      'id',
      'slug',
      'name',
      'description',
      'icon',
      'color',
      'board_slug',
      'primary_path',
      'archived',
      'created_at',
      'folders',
    };
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('native Hermes Project shape drifted');
    }
    final id = _nativeString(value['id'], 'native Hermes Project id', 96);
    final slug = _nativeString(value['slug'], 'native Hermes Project slug', 64);
    final name = _nativeString(
      value['name'],
      'native Hermes Project name',
      240,
    );
    if (!RegExp(r'^p_[a-f0-9]{8}$').hasMatch(id) ||
        !RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(slug)) {
      throw const FormatException('native Hermes Project identity is invalid');
    }
    final description = value['description'];
    if (description != null &&
        (description is! String ||
            description.length > 2000 ||
            !isSecretFreeProjectValue(description))) {
      throw const FormatException(
        'native Hermes Project description is invalid',
      );
    }
    _optionalNativeString(value['icon'], 'native Hermes Project icon', 64);
    _optionalNativeString(value['color'], 'native Hermes Project color', 64);
    final boardSlug = _optionalNativeString(
      value['board_slug'],
      'native Hermes Project board slug',
      64,
    );
    _optionalNativeString(
      value['primary_path'],
      'native Hermes Project primary path',
      2048,
    );
    if (boardSlug != null &&
        !RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(boardSlug)) {
      throw const FormatException('native Hermes Project board is invalid');
    }
    if (value['archived'] is! bool ||
        value['created_at'] is! int ||
        (value['created_at'] as int) < 0) {
      throw const FormatException('native Hermes Project state is invalid');
    }
    final folders = value['folders'];
    if (folders is! List || folders.length > 128) {
      throw const FormatException(
        'native Hermes Project workspace shape drifted',
      );
    }
    for (final folder in folders) {
      _nativeString(folder, 'native Hermes Project folder', 2048);
    }
    return HermesProject._(
      hermesProjectId: id,
      slug: slug,
      name: name,
      description: description as String?,
      archived: value['archived'] as bool,
      isActive: false,
      atlasContext: null,
    );
  }

  HermesProject withAtlasContext(MobileProjectContext context) =>
      HermesProject._(
        hermesProjectId: hermesProjectId,
        slug: slug,
        name: name,
        description: description,
        archived: archived,
        isActive: isActive,
        atlasContext: context,
      );

  HermesProject withActive(bool value) => HermesProject._(
    hermesProjectId: hermesProjectId,
    slug: slug,
    name: name,
    description: description,
    archived: archived,
    isActive: value,
    atlasContext: atlasContext,
  );
}

class HermesDesktopProjectsPort implements HermesProjectsPort {
  final DesktopGatewayClient _client;

  const HermesDesktopProjectsPort(this._client);

  @override
  Future<Map<String, dynamic>> listProjects() => _client.listProjects();

  @override
  Future<Map<String, dynamic>> setActiveProject(String hermesProjectId) =>
      _client.setActiveProject(hermesProjectId);
}

class ProjectCatalogController {
  final HermesProjectsPort _hermes;
  final AtlasProjectEnrichmentPort? atlas;

  const ProjectCatalogController(this._hermes, {this.atlas});

  bool get atlasEnrichmentEnabled => atlas != null;

  Future<List<HermesProject>> list({
    String? canonicalProfileId,
    String? query,
  }) async {
    final atlas = this.atlas;
    if (atlas != null &&
        (canonicalProfileId == null ||
            !isCanonicalProfileId(canonicalProfileId))) {
      throw const FormatException('canonical profile is invalid');
    }
    final normalizedQuery = query?.trim();
    if (normalizedQuery != null &&
        normalizedQuery.isNotEmpty &&
        !isSafeProjectQuery(query!)) {
      throw const FormatException('project query is invalid');
    }

    final payload = await _hermes.listProjects();
    if (payload.keys.any((key) => key != 'projects' && key != 'active_id') ||
        payload['projects'] is! List) {
      throw const FormatException('native Hermes Projects response drifted');
    }
    final activeId = payload['active_id'];
    if (activeId != null &&
        (activeId is! String ||
            !RegExp(r'^p_[a-f0-9]{8}$').hasMatch(activeId))) {
      throw const FormatException('native Hermes active Project is invalid');
    }
    final rawProjects = payload['projects'] as List;
    if (rawProjects.length > 500) {
      throw const FormatException('too many native Hermes Projects');
    }
    final native = rawProjects.map((value) {
      if (value is! Map) {
        throw const FormatException('native Hermes Project is not an object');
      }
      return HermesProject.fromNativeJson(Map<String, dynamic>.from(value));
    }).toList();
    final nativeIds = <String>{};
    if (native.any((project) => !nativeIds.add(project.hermesProjectId))) {
      throw const FormatException('native Hermes Project identity collision');
    }
    if (activeId != null && !nativeIds.contains(activeId)) {
      throw const FormatException('native Hermes active Project is unknown');
    }
    final nativeWithActive = native
        .map(
          (project) => project.withActive(project.hermesProjectId == activeId),
        )
        .toList();

    var joined = nativeWithActive;
    if (atlas != null) {
      final rawContexts = await atlas.listProjectContexts(
        canonicalProfileId: canonicalProfileId!,
      );
      if (rawContexts.length > 500) {
        throw const FormatException('too many ATLAS Project enrichments');
      }
      final byHermesId = <String, MobileProjectContext>{};
      for (final raw in rawContexts) {
        final context = MobileProjectContext.fromJson(raw);
        if (context.profileId != canonicalProfileId ||
            context.projection == null) {
          throw const FormatException(
            'ATLAS ProjectProjection scope is invalid',
          );
        }
        final reference = context.projection!.hermesProjectRef;
        const prefix = 'hermes-project://runtime/';
        if (reference == null || !reference.startsWith(prefix)) {
          throw const FormatException(
            'ATLAS ProjectProjection is not materialized',
          );
        }
        final nativeId = reference.substring(prefix.length);
        if (!nativeIds.contains(nativeId) ||
            byHermesId.putIfAbsent(nativeId, () => context) != context) {
          throw const FormatException(
            'ATLAS/native Hermes Project binding is invalid',
          );
        }
      }
      joined = native
          .map(
            (project) => byHermesId[project.hermesProjectId] == null
                ? project
                : project.withAtlasContext(
                    byHermesId[project.hermesProjectId]!,
                  ),
          )
          .toList();
    }

    if (normalizedQuery == null || normalizedQuery.isEmpty) {
      return List.unmodifiable(joined.where((project) => !project.archived));
    }
    final needle = normalizedQuery.toLowerCase();
    return List.unmodifiable(
      joined.where(
        (project) =>
            !project.archived &&
            (project.name.toLowerCase().contains(needle) ||
                project.slug.toLowerCase().contains(needle) ||
                (project.description?.toLowerCase().contains(needle) ?? false)),
      ),
    );
  }

  Future<MobileConversationProjectBinding?> select({
    required HermesProject project,
    required String? canonicalProfileId,
    required String? conversationId,
  }) async {
    final atlas = this.atlas;
    MobileConversationProjectBinding? binding;
    if (atlas != null) {
      final context = project.atlasContext;
      if (context == null ||
          canonicalProfileId != context.profileId ||
          (conversationId != null &&
              !isCanonicalConversationId(conversationId))) {
        throw const FormatException(
          'ATLAS Project selection identity is invalid',
        );
      }
      if (conversationId != null) {
        final digest = sha256.convert(
          utf8.encode(
            '${context.profileId}\n$conversationId\n${context.projectId}',
          ),
        );
        final idempotencyKey = 'mobile-project-bind:$digest';
        final raw = await atlas.requestConversationBinding(
          canonicalProfileId: context.profileId,
          conversationId: conversationId,
          projectId: context.projectId,
          idempotencyKey: idempotencyKey,
        );
        binding = MobileConversationProjectBinding.fromJson(raw);
        if (binding.projectId != context.projectId ||
            binding.profileId != context.profileId ||
            binding.conversationId != conversationId ||
            binding.status != 'ACTIVE') {
          throw const FormatException('binding receipt does not match request');
        }
      }
    }

    final active = await _hermes.setActiveProject(project.hermesProjectId);
    if (active.keys.length != 1 ||
        active['active_id'] != project.hermesProjectId) {
      throw const FormatException(
        'native Hermes active Project was not accepted',
      );
    }
    return binding;
  }
}

String _nativeString(Object? value, String label, int maxLength) {
  if (value is! String ||
      value.isEmpty ||
      value.trim() != value ||
      value.length > maxLength ||
      !isSecretFreeProjectValue(value)) {
    throw FormatException('$label is invalid');
  }
  return value;
}

String? _optionalNativeString(Object? value, String label, int maxLength) {
  if (value == null) return null;
  return _nativeString(value, label, maxLength);
}
