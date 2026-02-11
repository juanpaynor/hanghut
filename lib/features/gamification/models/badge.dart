class Badge {
  final String id;
  final String slug;
  final String name;
  final String description;
  final String tier;
  final String category;
  final String iconKey;
  final Map<String, dynamic> requirements;
  final DateTime createdAt;

  Badge({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.tier,
    required this.category,
    required this.iconKey,
    required this.requirements,
    required this.createdAt,
  });

  factory Badge.fromJson(Map<String, dynamic> json) {
    return Badge(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      tier: json['tier'] as String,
      category: json['category'] as String,
      iconKey: json['icon_key'] as String,
      requirements: json['requirements'] is Map
          ? Map<String, dynamic>.from(json['requirements'] as Map)
          : {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
