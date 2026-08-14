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
final RegExp _uriUserInfo = RegExp(
  r'[a-z][a-z0-9+.-]*://[^/\s:@]+:[^@\s/]+@',
  caseSensitive: false,
);

Never _invalid(String message) => throw FormatException(message);

bool _containsSecret(String value) =>
    _secret.hasMatch(value) || _uriUserInfo.hasMatch(value);

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
  if (_containsSecret(candidate)) _invalid('$key contains secret material');
  return candidate;
}

void _exactKeys(Map<String, dynamic> value, Set<String> allowed) {
  if (value.length != allowed.length || !allowed.containsAll(value.keys)) {
    _invalid('missing or unexpected contract field');
  }
}

bool isCanonicalProfileId(String value) => _profileId.hasMatch(value);

bool isCanonicalConversationId(String value) =>
    value == value.trim() &&
    value.length <= 255 &&
    !_containsSecret(value) &&
    _reference.hasMatch('hermes-session://$value');

bool isSafeProjectQuery(String value) =>
    value == value.trim() && value.length <= 120 && !_containsSecret(value);

bool isSafeIdempotencyKey(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value) &&
    !_containsSecret(value);

class MobileProjectCore {
  final String projectId;
  final String? objective;
  final String? currentState;
  final String? currentFocus;
  final List<String> openQuestions;
  final int revision;

  MobileProjectCore._({
    required this.projectId,
    required this.objective,
    required this.currentState,
    required this.currentFocus,
    required List<String> openQuestions,
    required this.revision,
  }) : openQuestions = List.unmodifiable(openQuestions);

  factory MobileProjectCore.fromJson(
    Map<String, dynamic> value, {
    required String expectedProjectId,
  }) {
    _exactKeys(value, const {
      'project_id',
      'objective',
      'current_state',
      'current_focus',
      'open_questions',
      'revision',
      'updated_at',
      'updated_by',
      'provenance',
    });
    final projectId = _string(value, 'project_id', maxLength: 36);
    final revision = value['revision'];
    if (projectId != expectedProjectId ||
        !_canonicalUuid.hasMatch(projectId) ||
        revision is! int ||
        revision < 1) {
      _invalid('Project Core owner binding is invalid');
    }
    String? optional(String key, int maxLength) =>
        value[key] == null ? null : _string(value, key, maxLength: maxLength);
    final rawQuestions = value['open_questions'];
    if (rawQuestions is! List || rawQuestions.length > 100) {
      _invalid('open_questions must be a bounded list');
    }
    final questions = <String>[];
    for (final item in rawQuestions) {
      if (item is! String ||
          item != item.trim() ||
          item.isEmpty ||
          item.length > 2000 ||
          _containsSecret(item) ||
          !questions.addIfAbsent(item)) {
        _invalid('open question is invalid');
      }
    }
    _timestamp(value, 'updated_at');
    _string(value, 'updated_by', maxLength: 128);
    _boundedJsonNoSecrets(value['provenance'], 'Project Core provenance');
    return MobileProjectCore._(
      projectId: projectId,
      objective: optional('objective', 8000),
      currentState: optional('current_state', 8000),
      currentFocus: optional('current_focus', 4000),
      openQuestions: questions,
      revision: revision,
    );
  }
}

class MobileProjectProjection {
  final String projectId;
  final String profileId;
  final String continuityStatus;
  final int revision;

  const MobileProjectProjection._({
    required this.projectId,
    required this.profileId,
    required this.continuityStatus,
    required this.revision,
  });

  factory MobileProjectProjection.fromJson(
    Map<String, dynamic> value, {
    required String expectedProjectId,
    required String expectedProfileId,
  }) {
    _exactKeys(value, const {
      'project_id',
      'profile_id',
      'continuity_status',
      'hermes_project_ref',
      'last_active_at',
      'revision',
      'updated_at',
      'provenance',
    });
    final projectId = _string(value, 'project_id', maxLength: 36);
    final profileId = _string(value, 'profile_id', maxLength: 64);
    final status = value['continuity_status'];
    final revision = value['revision'];
    if (projectId != expectedProjectId ||
        profileId != expectedProfileId ||
        !_canonicalUuid.hasMatch(projectId) ||
        !_profileId.hasMatch(profileId) ||
        !const {'ACTIVE', 'PAUSED'}.contains(status) ||
        revision is! int ||
        revision < 1) {
      _invalid('ProjectProjection owner binding is invalid');
    }
    final hermesRef = value['hermes_project_ref'];
    if (hermesRef != null &&
        (hermesRef is! String ||
            !RegExp(r'^hermes-project://[^\s]{1,240}$').hasMatch(hermesRef) ||
            _containsSecret(hermesRef))) {
      _invalid('Hermes Project runtime reference is invalid');
    }
    if (value['last_active_at'] != null) {
      _timestamp(value, 'last_active_at');
    }
    _timestamp(value, 'updated_at');
    _projectionProvenance(value['provenance']);
    return MobileProjectProjection._(
      projectId: projectId,
      profileId: profileId,
      continuityStatus: status as String,
      revision: revision,
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
  final MobileProjectProjection? projection;

  const MobileProjectContext._({
    required this.projectId,
    required this.profileId,
    required this.name,
    required this.slug,
    required this.core,
    required this.projection,
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
      'project_core',
      'project_projection',
    });
    if (value['contract'] != contract ||
        value['project_identity_authority'] != projectAuthority ||
        value['profile_identity_authority'] != profileAuthority ||
        value['coordination_authority'] != coordinationAuthority) {
      _invalid('project authorities or contract are invalid');
    }
    final projectId = _string(value, 'project_id', maxLength: 36);
    final profileId = _string(value, 'profile_id', maxLength: 64);
    if (!_canonicalUuid.hasMatch(projectId) ||
        !_profileId.hasMatch(profileId)) {
      _invalid('Project or Profile identity is not canonical');
    }
    final slug = _string(value, 'slug', maxLength: 120);
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,119}$').hasMatch(slug)) {
      _invalid('slug is invalid');
    }
    final rawCore = value['project_core'];
    final rawProjection = value['project_projection'];
    if (rawCore != null && rawCore is! Map<String, dynamic>) {
      _invalid('project_core must be an object or null');
    }
    if (rawProjection != null && rawProjection is! Map<String, dynamic>) {
      _invalid('project_projection must be an object or null');
    }
    return MobileProjectContext._(
      projectId: projectId,
      profileId: profileId,
      name: _string(value, 'name', maxLength: 240),
      slug: slug,
      core: rawCore == null
          ? null
          : MobileProjectCore.fromJson(rawCore, expectedProjectId: projectId),
      projection: rawProjection == null
          ? null
          : MobileProjectProjection.fromJson(
              rawProjection,
              expectedProjectId: projectId,
              expectedProfileId: profileId,
            ),
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
    final supersedes = value['supersedes_binding_id'];
    if (!_canonicalUuid.hasMatch(bindingId) ||
        !_canonicalUuid.hasMatch(projectId) ||
        bindingId == projectId ||
        !_profileId.hasMatch(profileId) ||
        !isCanonicalConversationId(conversationId) ||
        (supersedes != null &&
            (supersedes is! String ||
                !_canonicalUuid.hasMatch(supersedes) ||
                supersedes == bindingId))) {
      _invalid('binding endpoint or relationship identity is invalid');
    }
    final status = value['binding_status'];
    final revision = value['revision'];
    if (status != 'ACTIVE' ||
        value['ended_at'] != null ||
        revision is! int ||
        revision < 1) {
      _invalid('binding is not an active primary relationship');
    }
    final createdAt = _timestamp(value, 'created_at');
    final updatedAt = _timestamp(value, 'updated_at');
    if (updatedAt.isBefore(createdAt)) {
      _invalid('binding updated_at precedes created_at');
    }
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

DateTime _timestamp(Map<String, dynamic> value, String key) {
  final raw = _string(value, key, maxLength: 40);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(raw);
  if (match == null) _invalid('$key is not a canonical timestamp');
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  if (year == 0 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > _daysInMonth(year, month) ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    _invalid('$key is not a real timestamp');
  }
  return DateTime.parse(raw);
}

int _daysInMonth(int year, int month) {
  if (month == 2) {
    final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    return leap ? 29 : 28;
  }
  return const {4, 6, 9, 11}.contains(month) ? 30 : 31;
}

void _projectionProvenance(dynamic raw) {
  if (raw is! Map<String, dynamic>) {
    _invalid('ProjectProjection provenance must be an object');
  }
  const allowed = {
    'changeset_id',
    'source_ref',
    'source_digest',
    'actor_profile_id',
    'correlation_id',
  };
  _referenceProvenance(raw, 'ProjectProjection provenance', allowed: allowed);
}

void _referenceProvenance(
  dynamic raw,
  String field, {
  Set<String> allowed = const {
    'changeset_id',
    'source_ref',
    'source_digest',
    'actor_profile_id',
    'conversation_ref',
    'evidence_ref',
    'correlation_id',
  },
}) {
  if (raw is! Map<String, dynamic>) _invalid('$field must be an object');
  if (!allowed.containsAll(raw.keys)) _invalid('$field has an unexpected key');
  for (final entry in raw.entries) {
    if (entry.value is! String || _containsSecret(entry.value as String)) {
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

void _boundedJsonNoSecrets(dynamic value, String field) {
  var nodes = 0;
  void visit(dynamic current, int depth, String? key) {
    nodes++;
    if (nodes > 300 || depth > 6) _invalid('$field is too complex');
    final normalizedKey = key?.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (normalizedKey != null &&
        const {
          'transcript',
          'rawcontent',
          'hindsightmemory',
          'deviceid',
          'authorization',
          'credential',
          'password',
          'token',
          'secret',
          'apikey',
          'privatekey',
        }.any(normalizedKey.contains)) {
      _invalid('$field contains a forbidden key');
    }
    if (current == null || current is bool || current is num) return;
    if (current is String) {
      if (current.length > 4096 || _containsSecret(current)) {
        _invalid('$field contains invalid text');
      }
      return;
    }
    if (current is List) {
      if (current.length > 100) _invalid('$field is too large');
      for (final item in current) {
        visit(item, depth + 1, null);
      }
      return;
    }
    if (current is Map<String, dynamic>) {
      if (current.length > 100) _invalid('$field is too large');
      for (final entry in current.entries) {
        visit(entry.value, depth + 1, entry.key);
      }
      return;
    }
    _invalid('$field must contain bounded JSON values');
  }

  visit(value, 0, null);
}

UnmodifiableListView<MobileProjectContext> immutableProjects(
  Iterable<MobileProjectContext> projects,
) => UnmodifiableListView(projects);
