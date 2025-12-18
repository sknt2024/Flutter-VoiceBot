class Defect {
  final String id;
  final String name;

  Defect({
    required this.id,
    required this.name,
  });

  factory Defect.fromJson(Map<String, dynamic> json) {
    return Defect(
      id: json['_id']['\$oid'] as String,
      name: (json['name'] as String).trim(),
    );
  }
}
