import 'dart:collection';

final RegExp _canonicalUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _profileId = RegExp(r'^[a-z][a-z0-9_-]{1,63}$');
final RegExp _reference = RegExp(r'^[a-z][a-z0-9+.-]*://[^\s]+$');
final RegExp _secret = RegExp(
  r'(?:(?:api[._ /-]?key|authorization|credential|password|private[._ /-]?key|secret(?:[._ /-]?key)?|token)\s*["\x27]?\s*[=:]|bearer\s+[A-Za-z0-9])',
  caseSensitive: false,
);

Never _invalid(String message) => throw FormatException(message);

String _string(
  Map<String, dynamic> value,
  String key, {
  int maxLength = 4000,
  bool allowEmpty = false,
}) {
  final candidate = value[key];
  if (candidate is! String || candidate != candidate.trim()) {
    _invalid('$key must be a trimmed string');
  }
  if ((!allowEmpty && candidate.isEmpty) || candidate.length > maxLength) {
    _invalid('$key has an invalid length');
  }
  if (_secret.hasMatch(candidate)) _invalid('$key contains secret material');
  return candidate;
}

void _exactKeys(Map<String, dynamic> value, Set<String> allowed) {
  if (value.length != allowed.length || !allowed.containsAll(value.keys)) {
    _invalid('missing or unexpected project field');
  }
}

bool isCanonicalProfileId(String value) => _profileId.hasMatch(value);

bool isCanonicalConversationId(String value) =>
    value == value.trim() &&
    value.length <= 255 &&
    !_secret.hasMatch(value) &&
    _reference.hasMatch('hermes-session://$value');

bool isSafeProjectQuery(String value) =>
    value == value.trim() && value.length <= 120 && !_secret.hasMatch(value);

bool isSafeIdempotencyKey(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value) &&
    !_secret.hasMatch(value);

class MobileProjectCore {
  final String? objective;
  final String? currentState;
  final String? currentFocus;
  final List<String> openQuestions;

  MobileProjectCore._({
    required this.objective,
    required this.currentState,
    required this.currentFocus,
    required List<String> openQuestions,
  }) : openQuestions = List.unmodifiable(openQuestions);

  factory MobileProjectCore.fromJson(Map<String, dynamic> value) {
    _exactKeys(value, const {
      'objective',
      'current_state',
      'current_focus',
      'open_questions',
    });
    String? optional(String key) =>
        value[key] == null ? null : _string(value, key, maxLength: 4000);
    final rawQuestions = value['open_questions'];
    if (rawQuestions is! List || rawQuestions.length > 50) {
      _invalid('open_questions must be a bounded list');
    }
    final questions = <String>[];
    for (final item in rawQuestions) {
      if (item is! String ||
          item != item.trim() ||
          item.isEmpty ||
          item.length > 1000) {
        _invalid('open question is invalid');
      }
      if (_secret.hasMatch(item)) {
        _invalid('open question contains secret material');
      }
      if (!questions.addIfAbsent(item)) {
        _invalid('open questions must be unique');
      }
    }
    return MobileProjectCore._(
      objective: optional('objective'),
      currentState: optional('current_state'),
      currentFocus: optional('current_focus'),
      openQuestions: questions,
    );
  }
}

extension on List<String> {
  bool addIfAbsent(String value) {
    if (contains(value)) return false;
    add(value);
    return true;
  }
}

class MobileProjectContext {
  static const contract = 'atlas.mobile-project-context.v1';
  static const projectAuthority = 'document-service';
  static const profileAuthority = 'profile-service';
  static const coordinationAuthority = 'coordination-core';

  final String projectId;
  final String profileId;
  final String name;
  final String slug;
  final MobileProjectCore? core;
  final String? continuityStatus;
  final String? conversationId;

  const MobileProjectContext._({
    required this.projectId,
    required this.profileId,
    required this.name,
    required this.slug,
    required this.core,
    required this.continuityStatus,
    required this.conversationId,
  });

  factory MobileProjectContext.fromJson(Map<String, dynamic> value) {
    _exactKeys(value, const {
      'contract',
      'project_identity_authority',
      'profile_identity_authority',
      'coordination_authority',
      'project_id',
      'profile_id',
      'name',
      'slug',
      'core',
      'continuity_status',
      'conversation_id',
    });
    if (value['contract'] != contract ||
        value['project_identity_authority'] != projectAuthority ||
        value['profile_identity_authority'] != profileAuthority ||
        value['coordination_authority'] != coordinationAuthority) {
      _invalid('project authorities or contract are invalid');
    }
    final projectId = _string(value, 'project_id', maxLength: 36);
    final profileId = _string(value, 'profile_id', maxLength: 64);
    if (!_canonicalUuid.hasMatch(projectId)) {
      _invalid('project_id is not canonical');
    }
    if (!_profileId.hasMatch(profileId)) {
      _invalid('profile_id is not canonical');
    }
    final slug = _string(value, 'slug', maxLength: 120);
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,119}$').hasMatch(slug)) {
      _invalid('slug is invalid');
    }
    final rawCore = value['core'];
    if (rawCore != null && rawCore is! Map<String, dynamic>) {
      _invalid('core must be an object or null');
    }
    final status = value['continuity_status'];
    if (status != null && !const {'ACTIVE', 'PAUSED'}.contains(status)) {
      _invalid('continuity_status is invalid');
    }
    final conversationId = value['conversation_id'];
    if (conversationId != null &&
        (conversationId is! String ||
            !isCanonicalConversationId(conversationId))) {
      _invalid('conversation_id is invalid');
    }
    return MobileProjectContext._(
      projectId: projectId,
      profileId: profileId,
      name: _string(value, 'name', maxLength: 240),
      slug: slug,
      core: rawCore == null ? null : MobileProjectCore.fromJson(rawCore),
      continuityStatus: status as String?,
      conversationId: conversationId as String?,
    );
  }
}

class MobileConversationProjectBinding {
  final String bindingId;
  final String projectId;
  final String profileId;
  final String conversationId;
  final String status;
  final int revision;

  const MobileConversationProjectBinding._({
    required this.bindingId,
    required this.projectId,
    required this.profileId,
    required this.conversationId,
    required this.status,
    required this.revision,
  });

  factory MobileConversationProjectBinding.fromJson(
    Map<String, dynamic> value,
  ) {
    _exactKeys(value, const {
      'binding_id',
      'conversation_id',
      'profile_id',
      'project_id',
      'binding_status',
      'supersedes_binding_id',
      'revision',
      'created_at',
      'updated_at',
      'ended_at',
      'provenance',
      'transition_provenance',
    });
    final bindingId = _string(value, 'binding_id', maxLength: 36);
    final projectId = _string(value, 'project_id', maxLength: 36);
    final profileId = _string(value, 'profile_id', maxLength: 64);
    final conversationId = _string(value, 'conversation_id', maxLength: 255);
    if (!_canonicalUuid.hasMatch(bindingId) ||
        !_canonicalUuid.hasMatch(projectId) ||
        bindingId == projectId ||
        !_profileId.hasMatch(profileId) ||
        !isCanonicalConversationId(conversationId)) {
      _invalid('binding endpoint identity is invalid');
    }
    final status = value['binding_status'];
    final revision = value['revision'];
    if (status != 'ACTIVE' ||
        value['supersedes_binding_id'] != null ||
        value['ended_at'] != null ||
        revision is! int ||
        revision < 1) {
      _invalid('binding is not an active primary relationship');
    }
    _timestamp(value, 'created_at');
    _timestamp(value, 'updated_at');
    _referenceProvenance(value['provenance'], 'provenance');
    _referenceProvenance(
      value['transition_provenance'],
      'transition_provenance',
    );
    return MobileConversationProjectBinding._(
      bindingId: bindingId,
      projectId: projectId,
      profileId: profileId,
      conversationId: conversationId,
      status: status as String,
      revision: revision,
    );
  }
}

void _timestamp(Map<String, dynamic> value, String key) {
  final raw = _string(value, key, maxLength: 40);
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
  ).hasMatch(raw)) {
    _invalid('$key is not a canonical timestamp');
  }
  try {
    DateTime.parse(raw);
  } on FormatException {
    _invalid('$key is not a real timestamp');
  }
}

void _referenceProvenance(dynamic raw, String field) {
  if (raw is! Map<String, dynamic>) _invalid('$field must be an object');
  const allowed = {
    'changeset_id',
    'source_ref',
    'source_digest',
    'actor_profile_id',
    'conversation_ref',
    'evidence_ref',
    'correlation_id',
  };
  if (!allowed.containsAll(raw.keys)) _invalid('$field has an unexpected key');
  for (final entry in raw.entries) {
    if (entry.value is! String || _secret.hasMatch(entry.value as String)) {
      _invalid('$field contains invalid material');
    }
    final text = entry.value as String;
    if (entry.key == 'source_digest') {
      if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(text)) {
        _invalid('$field digest is invalid');
      }
    } else if (const {
      'source_ref',
      'conversation_ref',
      'evidence_ref',
    }.contains(entry.key)) {
      if (text.length > 512 || !_reference.hasMatch(text)) {
        _invalid('$field reference is invalid');
      }
    } else if (entry.key == 'actor_profile_id') {
      if (!_profileId.hasMatch(text)) _invalid('$field profile is invalid');
    } else if (entry.key == 'changeset_id') {
      if (!RegExp(r'^[A-Z0-9][A-Z0-9-]{1,63}$').hasMatch(text)) {
        _invalid('$field changeset is invalid');
      }
    } else if (text.isEmpty ||
        text.length > 128 ||
        RegExp(r'\s').hasMatch(text)) {
      _invalid('$field correlation is invalid');
    }
  }
}

UnmodifiableListView<MobileProjectContext> immutableProjects(
  Iterable<MobileProjectContext> projects,
) => UnmodifiableListView(projects);
