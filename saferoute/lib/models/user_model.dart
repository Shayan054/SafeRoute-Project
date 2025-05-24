class UserModel {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoURL;
  final List<String> favoriteRoutes;
  final List<String> travelHistory;
  final Map<String, dynamic>? preferences;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoURL,
    this.favoriteRoutes = const [],
    this.travelHistory = const [],
    this.preferences,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String id) {
    return UserModel(
      uid: id,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      photoURL: data['photoURL'],
      favoriteRoutes: List<String>.from(data['favoriteRoutes'] ?? []),
      travelHistory: List<String>.from(data['travelHistory'] ?? []),
      preferences: data['preferences'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
      'favoriteRoutes': favoriteRoutes,
      'travelHistory': travelHistory,
      'preferences': preferences,
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoURL,
    List<String>? favoriteRoutes,
    List<String>? travelHistory,
    Map<String, dynamic>? preferences,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      favoriteRoutes: favoriteRoutes ?? this.favoriteRoutes,
      travelHistory: travelHistory ?? this.travelHistory,
      preferences: preferences ?? this.preferences,
    );
  }
}
