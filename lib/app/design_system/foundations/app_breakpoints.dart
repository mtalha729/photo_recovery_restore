enum AppWindowClass { compact, medium, expanded }

abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 840;

  static AppWindowClass windowClassFor(double width) {
    if (width < medium) return AppWindowClass.compact;
    if (width < expanded) return AppWindowClass.medium;
    return AppWindowClass.expanded;
  }
}

abstract final class AppPhotoGrid {
  static const double minimumTileWidth = 144;
  static const double spacing = 12;
  static const int maximumColumns = 8;

  static int columnsFor(
    double availableWidth, {
    double minimumWidth = minimumTileWidth,
    double gap = spacing,
  }) {
    if (availableWidth <= 0 || minimumWidth <= 0) return 1;
    final columns = ((availableWidth + gap) / (minimumWidth + gap)).floor();
    return columns.clamp(1, maximumColumns);
  }
}
