/// A profile row from `public.users`. `username == null` is onboarding
/// incomplete — that is the whole definition (SPEC §7.4).
class Profile {
  const Profile({
    required this.id,
    this.username,
    this.name,
    this.avatarPath,
    this.emailPublic = false,
    this.social = const {},
  });

  final String id;
  final String? username;
  final String? name;
  final String? avatarPath;
  final bool emailPublic;
  final Map<String, dynamic> social;

  bool get isOnboarded => (username ?? '').isNotEmpty;

  String get handle => username == null ? '' : '@$username';

  String get displayName {
    final n = name?.trim();
    return (n == null || n.isEmpty) ? (username ?? '') : n;
  }

  /// A single link, if any — the profile card shows one at a time in v0.1.
  MapEntry<String, String>? get firstSocial {
    for (final entry in social.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty) {
        return MapEntry(entry.key, value);
      }
    }
    return null;
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    final social = json['social'];
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String?,
      name: json['name'] as String?,
      avatarPath: json['avatar_path'] as String?,
      emailPublic: json['email_public'] as bool? ?? false,
      social: social is Map<String, dynamic> ? social : const {},
    );
  }
}
