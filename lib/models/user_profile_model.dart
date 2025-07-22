class UserProfile {
  final int userId;
  final String name;
  final String email;

  UserProfile({required this.userId, required this.name, required this.email});

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id'],
      name: json['name'],
      email: json['email'],
    );
  }
}