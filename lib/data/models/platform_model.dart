class PlatformModel {
  final String name;
  final String url;
  final String icon;
  final String category;
  final String subtitle;
  final dynamic color;

  const PlatformModel({
    required this.name,
    required this.url,
    required this.icon,
    required this.category,
    this.subtitle = '',
    this.color,
  });
}
