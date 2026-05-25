import 'page_data.dart';

class Project {
  final String id;
  final String filePath;
  final String fileName;
  final int pageCount;
  final Map<int, PageData> pages;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Project({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.pageCount,
    this.pages = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  PageData getPageData(int pageIndex) {
    return pages[pageIndex] ?? PageData(pageIndex: pageIndex);
  }

  Project updatePageData(int pageIndex, PageData data) {
    final updatedPages = Map<int, PageData>.from(pages);
    updatedPages[pageIndex] = data;
    return Project(
      id: id,
      filePath: filePath,
      fileName: fileName,
      pageCount: pageCount,
      pages: updatedPages,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
