import '../models/mobile_session_continuity.dart';
import '../models/session.dart';

abstract interface class HermesSessionContinuityPort {
  Future<Map<String, dynamic>> verifyExistingSession({
    required String canonicalProfileId,
    required String sessionId,
    required String requestId,
  });
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

  Future<Session> authorizeOpen({
    required MobileSessionOpenRequest request,
    required String selectedProfileId,
    required List<Session> visibleSessions,
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

    final matches = visibleSessions
        .where((session) => session.id == request.sessionId)
        .toList(growable: false);
    if (matches.length != 1) throw const SessionContinuityDenied();
    return matches.single;
  }
}
