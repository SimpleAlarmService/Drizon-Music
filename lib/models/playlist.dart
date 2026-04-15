class Playlist {
  final String id;
  final String name;
  final List<String> trackIds;
  final int createdAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
  });

  factory Playlist.fromMap(Map<dynamic, dynamic> m) => Playlist(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        trackIds: List<String>.from((m['trackIds'] as List?) ?? []),
        createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt,
      };

  Playlist copyWith({String? name, List<String>? trackIds}) => Playlist(
        id: id,
        name: name ?? this.name,
        trackIds: trackIds ?? this.trackIds,
        createdAt: createdAt,
      );
}
