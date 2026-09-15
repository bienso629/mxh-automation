class ApiConstants {
  static const String defaultGatewayUrl = 'http://127.0.0.1:8888';
  
  // REST Endpoints
  static const String epConfig = '/api/config';
  static const String epServers = '/api/servers';
  static const String epServersUpdate = '/api/servers/update';
  static const String epServersDelete = '/api/servers/delete';
  static const String epServersSelect = '/api/servers/select';
  
  static const String epChatSessions = '/api/chat/sessions';
  static const String epChatHistory = '/api/chat/history';
  static const String epChatClear = '/api/chat/clear';
  static const String epChat = '/api/chat';
  
  static const String epSshTest = '/api/ssh/test';
  static const String epServerHealth = '/api/server/health';
  static const String epSystemInfo = '/api/server/system-info';
  static const String epMetrics = '/api/server/metrics';
  static const String epServiceAction = '/api/server/service-action';
  static const String epServerLogs = '/api/server/logs';
  static const String epServerDeploy = '/api/server/deploy';
  
  static const String epFsListDirs = '/api/fs/list_dirs';
  static const String epFsDownload = '/api/fs/download';
  static const String epFsUpload = '/api/fs/upload';
  
  // WebSocket Endpoints
  static const String wsTerminal = '/ws/terminal';
}
