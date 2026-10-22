enum CloseBehavior {
  hideToTray('隐藏到托盘'),
  exit('直接退出'),
  ask('每次询问');

  const CloseBehavior(this.label);
  final String label;

  static CloseBehavior fromJson(Object? value) => values.firstWhere(
        (item) => item.name == value,
        orElse: () => hideToTray,
      );
}
