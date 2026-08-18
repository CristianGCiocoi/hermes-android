enum GatewayInteractionMode { standard, interview, grill }

extension GatewayInteractionModeWire on GatewayInteractionMode {
  String get wireValue => name;

  String get label => switch (this) {
    GatewayInteractionMode.standard => 'Standard',
    GatewayInteractionMode.interview => 'Interview',
    GatewayInteractionMode.grill => 'Grill',
  };

  String get description => switch (this) {
    GatewayInteractionMode.standard =>
      'Normal Hermes conversation. Works with every Gateway.',
    GatewayInteractionMode.interview =>
      'Hermes asks one focused question at a time before continuing.',
    GatewayInteractionMode.grill =>
      'Hermes challenges assumptions and evidence one question at a time.',
  };
}

GatewayInteractionMode? gatewayInteractionModeFromWire(Object? value) {
  if (value is! String) return null;
  for (final mode in GatewayInteractionMode.values) {
    if (mode.wireValue == value) return mode;
  }
  return null;
}

/// Strict, versioned negotiation for the optional Hermes interaction modes.
///
/// Absence and malformed capability declarations intentionally have the same
/// safe result: Standard remains available locally and no interaction-mode RPC
/// may be sent to that Gateway.
class GatewayInteractionModeCapability {
  final bool supported;

  const GatewayInteractionModeCapability._(this.supported);
  const GatewayInteractionModeCapability.unsupported() : this._(false);

  factory GatewayInteractionModeCapability.fromGatewayReady(
    Map<String, dynamic> frame,
  ) {
    final params = frame['params'];
    final payload = params is Map<String, dynamic> ? params['payload'] : null;
    final capabilities = payload is Map<String, dynamic>
        ? payload['capabilities']
        : null;
    final raw = capabilities is Map<String, dynamic>
        ? capabilities['interaction_modes']
        : null;
    const exactKeys = <String>{
      'version',
      'methods',
      'modes',
      'scope',
      'default_mode',
      'readback',
      'clarify_transport',
    };
    if (raw is! Map<String, dynamic> ||
        raw.length != exactKeys.length ||
        !exactKeys.containsAll(raw.keys) ||
        raw['version'] is! int ||
        raw['version'] is bool ||
        raw['version'] != 1 ||
        !_isExactStringList(raw['methods'], const [
          'interaction_mode.get',
          'interaction_mode.set',
        ]) ||
        !_isExactStringList(raw['modes'], const [
          'standard',
          'interview',
          'grill',
        ]) ||
        raw['scope'] != 'session' ||
        raw['default_mode'] != 'standard' ||
        raw['readback'] != 'session.info' ||
        raw['clarify_transport'] != 'clarify.request/respond') {
      return const GatewayInteractionModeCapability.unsupported();
    }
    return const GatewayInteractionModeCapability._(true);
  }

  static bool _isExactStringList(Object? value, List<String> expected) {
    if (value is! List || value.length != expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (value[index] is! String || value[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }
}

class GatewayInteractionModeState {
  final bool supported;
  final GatewayInteractionMode mode;
  final int revision;

  const GatewayInteractionModeState({
    required this.supported,
    required this.mode,
    required this.revision,
  });

  const GatewayInteractionModeState.standardOnly()
    : supported = false,
      mode = GatewayInteractionMode.standard,
      revision = 0;

  static GatewayInteractionModeState? fromSessionInfo(
    Map<String, dynamic> data,
  ) {
    final mode = gatewayInteractionModeFromWire(data['interaction_mode']);
    final revision = data['interaction_mode_revision'];
    if (mode == null || revision is! int || revision is bool || revision < 0) {
      return null;
    }
    return GatewayInteractionModeState(
      supported: true,
      mode: mode,
      revision: revision,
    );
  }
}

class GatewayInteractionModeReceipt {
  final String sessionId;
  final String storedSessionId;
  final GatewayInteractionMode requestedMode;
  final GatewayInteractionMode effectiveMode;
  final int revision;

  const GatewayInteractionModeReceipt({
    required this.sessionId,
    required this.storedSessionId,
    required this.requestedMode,
    required this.effectiveMode,
    required this.revision,
  });

  static GatewayInteractionModeReceipt? fromResult(
    Object? value, {
    required String expectedSessionId,
    required GatewayInteractionMode expectedRequestedMode,
  }) {
    if (value is! Map<String, dynamic> || value.length != 5) return null;
    const exactKeys = <String>{
      'session_id',
      'stored_session_id',
      'requested_mode',
      'effective_mode',
      'revision',
    };
    if (!exactKeys.containsAll(value.keys)) return null;
    final storedSessionId = value['stored_session_id'];
    final requested = gatewayInteractionModeFromWire(value['requested_mode']);
    final effective = gatewayInteractionModeFromWire(value['effective_mode']);
    final revision = value['revision'];
    if (value['session_id'] != expectedSessionId ||
        storedSessionId is! String ||
        storedSessionId.isEmpty ||
        storedSessionId.trim() != storedSessionId ||
        requested != expectedRequestedMode ||
        effective != expectedRequestedMode ||
        revision is! int ||
        revision is bool ||
        revision < 0) {
      return null;
    }
    return GatewayInteractionModeReceipt(
      sessionId: expectedSessionId,
      storedSessionId: storedSessionId,
      requestedMode: requested!,
      effectiveMode: effective!,
      revision: revision,
    );
  }
}
