import '../models/mobile_session_continuity.dart';
import '../models/connection.dart';
import '../models/session.dart';

abstract interface class HermesSessionContinuityPort {
  Future<Map<String, dynamic>> verifyExistingSession({
    required String canonicalProfileId,
    required String sessionId,
    required String requestId,
  });

  Future<ProfileScopedSession> loadVerifiedSession({
    required HermesSessionVerification verification,
  });
}

class ProfileScopedSession {
  final HermesSessionVerification verification;
  final SavedConnection connection;
  final Session session;

  ProfileScopedSession({
    required this.verification,
    required this.connection,
    required this.session,
  }) {
    if (connection.runtimeType != SavedConnection ||
        session.runtimeType != Session ||
        session.id != verification.sessionId) {
      throw const FormatException('Profile-scoped session is invalid.');
    }
  }
}

class SessionContinuityDenied implements Exception {
  const SessionContinuityDenied();

  @override
  String toString() => 'Shared session could not be opened.';
}

class SessionContinuityController {
  final HermesSessionContinuityPort _port;
  final DateTime Function() _now;

  SessionContinuityController(this._port, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  Future<ProfileScopedSession> authorizeOpen({
    required MobileSessionOpenRequest request,
    required String selectedProfileId,
  }) async {
    if (request.runtimeType != MobileSessionOpenRequest ||
        selectedProfileId != request.profileId) {
      throw const SessionContinuityDenied();
    }

    Map<String, dynamic> raw;
    try {
      raw = await _port.verifyExistingSession(
        canonicalProfileId: request.profileId,
        sessionId: request.sessionId,
        requestId: request.requestId,
      );
    } catch (_) {
      throw const SessionContinuityDenied();
    }

    HermesSessionVerification verification;
    try {
      verification = HermesSessionVerification.fromJson(raw);
    } catch (_) {
      throw const SessionContinuityDenied();
    }
    final now = _now().toUtc();
    if (verification.profileId != request.profileId ||
        verification.sessionId != request.sessionId ||
        verification.requestId != request.requestId ||
        now.isBefore(verification.verifiedAt) ||
        !now.isBefore(verification.expiresAt)) {
      throw const SessionContinuityDenied();
    }

    ProfileScopedSession scoped;
    try {
      scoped = await _port.loadVerifiedSession(verification: verification);
    } catch (_) {
      throw const SessionContinuityDenied();
    }
    if (scoped.runtimeType != ProfileScopedSession ||
        !identical(scoped.verification, verification) ||
        scoped.verification.profileId != request.profileId ||
        scoped.session.id != request.sessionId) {
      throw const SessionContinuityDenied();
    }
    return scoped;
  }
}
