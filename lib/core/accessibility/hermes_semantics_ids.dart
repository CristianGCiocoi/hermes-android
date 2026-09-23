/// Stable, value-free identifiers exported to Android's accessibility tree.
///
/// Keep these identifiers independent of user-entered values so UI automation
/// can locate controls without exposing connection metadata or credentials.
abstract final class HermesSemanticsId {
  static const addConnection = 'hermes.connection.add';
  static const addConnectionDialog = 'hermes.connection.dialog.add';
  static const editConnectionDialog = 'hermes.connection.dialog.edit';
  static const connectionLabel = 'hermes.connection.field.label';
  static const connectionHost = 'hermes.connection.field.host';
  static const connectionPort = 'hermes.connection.field.port';
  static const connectionApiKey = 'hermes.connection.field.api_key';
  static const connectionAdvanced = 'hermes.connection.advanced.toggle';
  static const connectionGatewayPrefix =
      'hermes.connection.field.gateway_prefix';
  static const connectionAtlasOwner =
      'hermes.connection.field.atlas_owner_enabled';
  static const connectionDashboardPrefix =
      'hermes.connection.field.dashboard_prefix';
  static const connectionDashboardProxied =
      'hermes.connection.field.dashboard_proxied';
  static const connectionDashboardPort =
      'hermes.connection.field.dashboard_port';
  static const connectionDashboardUsername =
      'hermes.connection.field.dashboard_username';
  static const connectionDashboardPassword =
      'hermes.connection.field.dashboard_password';
  static const connectionDesktopGatewayUrl =
      'hermes.connection.field.desktop_gateway_url';
  static const connectionCancel = 'hermes.connection.action.cancel';
  static const connectionConnect = 'hermes.connection.action.connect';
  static const newChat = 'hermes.chat.new';
  static const composer = 'hermes.chat.composer';

  static String savedConnection(String connectionId) =>
      'hermes.connection.saved.$connectionId';
}
