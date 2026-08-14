import 'atlas_project_context.dart' show isCanonicalProfileId;

const mobileSessionContinuityContract = 'atlas.mobile-session-continuity.v1';
const hermesSessionVerificationContract =
    'atlas.hermes-session-verification.v1';
const hermesSessionAuthority = 'hermes-per-profile';
const profileIdentityAuthority = 'profile-service';

final RegExp _requestId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _sessionId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,239}$');
final RegExp _timestamp = RegExp(
  r'^(?!0000)([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]{1,6})?(?:Z|[+-](?:0[0-9]|1[0-3]):[0-5][0-9]|[+-]14:00)$',
);
final RegExp _secret = RegExp(
  r'''(?:api[._ -]?key|authorization|bearer|credential|password|private[._ -]?key|secret[._ -]?key|token)(?:\s|["'._-])*(?:=|:)''',
  caseSensitive: false,
);

Never _invalid([String message = 'session continuity contract is invalid']) {
  throw FormatException(message);
}

String _exactString(
  Map<String, dynamic> value,
  String key, {
  required int maxLength,
}) {
  final raw = value[key];
  if (raw is! String ||
      raw.isEmpty ||
      raw.length > maxLength ||
      raw.trim() != raw ||
      _secret.hasMatch(raw)) {
    _invalid();
  }
  return raw;
}

void _exactKeys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    _invalid();
  }
}

DateTime _strictTime(String raw) {
  final match = _timestamp.firstMatch(raw);
  if (match == null) _invalid();
  final parsed = DateTime.tryParse(raw);
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final calendar = DateTime.utc(year, month, day);
  if (parsed == null ||
      calendar.year != year ||
      calendar.month != month ||
      calendar.day != day) {
    _invalid();
  }
  return parsed.toUtc();
}

class MobileSessionOpenRequest {
  final String profileId;
  final String sessionId;
  final String requestId;

  const MobileSessionOpenRequest._({
    required this.profileId,
    required this.sessionId,
    required this.requestId,
  });

  factory MobileSessionOpenRequest.fromJson(Map<String, dynamic> value) {
    _exactKeys(value, const {
      'contract',
      'profile_identity_authority',
      'session_authority',
      'profile_id',
      'session_id',
      'request_id',
    });
    if (value['contract'] != mobileSessionContinuityContract ||
        value['profile_identity_authority'] != profileIdentityAuthority ||
        value['session_authority'] != hermesSessionAuthority) {
      _invalid();
    }
    final profileId = _exactString(value, 'profile_id', maxLength: 64);
    final sessionId = _exactString(value, 'session_id', maxLength: 240);
    final requestId = _exactString(value, 'request_id', maxLength: 36);
    if (!isCanonicalProfileId(profileId) ||
        !_sessionId.hasMatch(sessionId) ||
        !_requestId.hasMatch(requestId)) {
      _invalid();
    }
    return MobileSessionOpenRequest._(
      profileId: profileId,
      sessionId: sessionId,
      requestId: requestId,
    );
  }

  factory MobileSessionOpenRequest.fromUri(Uri uri) {
    if (uri.scheme != 'hermes' ||
        uri.host != 'session' ||
        uri.path != '/open' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isNotEmpty ||
        uri.query.contains('%') ||
        uri.query.contains('+') ||
        uri.queryParametersAll.length != 3 ||
        uri.queryParametersAll.keys.toSet().difference(const {
          'profile_id',
          'session_id',
          'request_id',
        }).isNotEmpty ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      _invalid('session continuity link is invalid');
    }
    return MobileSessionOpenRequest.fromJson({
      'contract': mobileSessionContinuityContract,
      'profile_identity_authority': profileIdentityAuthority,
      'session_authority': hermesSessionAuthority,
      'profile_id': uri.queryParametersAll['profile_id']!.single,
      'session_id': uri.queryParametersAll['session_id']!.single,
      'request_id': uri.queryParametersAll['request_id']!.single,
    });
  }

  Map<String, dynamic> toJson() => {
    'contract': mobileSessionContinuityContract,
    'profile_identity_authority': profileIdentityAuthority,
    'session_authority': hermesSessionAuthority,
    'profile_id': profileId,
    'session_id': sessionId,
    'request_id': requestId,
  };
}

class HermesSessionVerification {
  final String profileId;
  final String sessionId;
  final String requestId;
  final DateTime verifiedAt;
  final DateTime expiresAt;

  const HermesSessionVerification._({
    required this.profileId,
    required this.sessionId,
    required this.requestId,
    required this.verifiedAt,
    required this.expiresAt,
  });

  factory HermesSessionVerification.fromJson(Map<String, dynamic> value) {
    _exactKeys(value, const {
      'contract',
      'profile_identity_authority',
      'session_authority',
      'profile_id',
      'session_id',
      'request_id',
      'verification_status',
      'verified_at',
      'expires_at',
    });
    if (value['contract'] != hermesSessionVerificationContract ||
        value['profile_identity_authority'] != profileIdentityAuthority ||
        value['session_authority'] != hermesSessionAuthority ||
        value['verification_status'] != 'VERIFIED') {
      _invalid();
    }
    final profileId = _exactString(value, 'profile_id', maxLength: 64);
    final sessionId = _exactString(value, 'session_id', maxLength: 240);
    final requestId = _exactString(value, 'request_id', maxLength: 36);
    final verifiedRaw = _exactString(value, 'verified_at', maxLength: 40);
    final expiresRaw = _exactString(value, 'expires_at', maxLength: 40);
    if (!isCanonicalProfileId(profileId) ||
        !_sessionId.hasMatch(sessionId) ||
        !_requestId.hasMatch(requestId)) {
      _invalid();
    }
    final verifiedAt = _strictTime(verifiedRaw);
    final expiresAt = _strictTime(expiresRaw);
    if (!expiresAt.isAfter(verifiedAt) ||
        expiresAt.difference(verifiedAt) > const Duration(minutes: 5)) {
      _invalid();
    }
    return HermesSessionVerification._(
      profileId: profileId,
      sessionId: sessionId,
      requestId: requestId,
      verifiedAt: verifiedAt,
      expiresAt: expiresAt,
    );
  }
}
