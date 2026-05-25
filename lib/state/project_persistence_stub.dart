/// Stub persistence for web — no file system available.
Future<void> saveProject(String filePath, String jsonContent) async {}

Future<String?> loadProject(String filePath) async => null;

Future<void> saveRecentProjects(String jsonContent) async {}

Future<String?> loadRecentProjects() async => null;
