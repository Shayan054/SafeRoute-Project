import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../utils/firebase_auth_helper.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Get current user
  User? get currentUser => FirebaseAuthHelper.currentUser;

  // Get current user ID
  String? get currentUserId => FirebaseAuthHelper.currentUser?.uid;

  // Register with email and password
  Future<UserCredential> registerWithEmailAndPassword(
      String email, String password) async {
    try {
      UserCredential result =
          await FirebaseAuthHelper.createUserWithEmailAndPassword(
              email, password);

      // Create a new user document in Firestore
      await _createUserDocument(result.user!);

      return result;
    } catch (e) {
      print("Registration error: $e");
      rethrow;
    }
  }

  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      UserCredential result =
          await FirebaseAuthHelper.signInWithEmailAndPassword(email, password);

      // Save login state to shared preferences
      await _saveLoginState(true);

      return result;
    } catch (e) {
      print("Login error: $e");
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _saveLoginState(false);
      return await FirebaseAuthHelper.signOut();
    } catch (e) {
      print("Signout error: $e");
      rethrow;
    }
  }

  // Password reset
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      return await FirebaseAuthHelper.sendPasswordResetEmail(email);
    } catch (e) {
      print("Password reset error: $e");
      rethrow;
    }
  }

  // Create user document in Firestore
  Future<void> _createUserDocument(User user) async {
    // Create a new UserModel
    UserModel newUser = UserModel(
      uid: user.uid,
      email: user.email!,
      displayName: user.displayName,
    );

    // Add to Firestore
    await _firestore.collection('users').doc(user.uid).set(newUser.toMap());
  }

  // Get user data from Firestore
  Future<UserModel?> getUserData() async {
    try {
      if (currentUserId == null) return null;

      DocumentSnapshot doc =
          await _firestore.collection('users').doc(currentUserId).get();

      if (!doc.exists) return null;

      return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  // Update user profile
  Future<void> updateUserProfile({
    String? displayName,
    String? photoURL,
    Map<String, dynamic>? preferences,
  }) async {
    try {
      if (currentUserId == null) return;

      Map<String, dynamic> data = {};

      if (displayName != null) {
        data['displayName'] = displayName;
        await currentUser!.updateDisplayName(displayName);
      }

      if (photoURL != null) {
        data['photoURL'] = photoURL;
        await currentUser!.updatePhotoURL(photoURL);
      }

      if (preferences != null) {
        data['preferences'] = preferences;
      }

      if (data.isNotEmpty) {
        await _firestore.collection('users').doc(currentUserId).update(data);
      }
    } catch (e) {
      print("Profile update error: $e");
      rethrow;
    }
  }

  // Add a route to user's travel history
  Future<void> addToTravelHistory(String routeId) async {
    try {
      if (currentUserId == null) return;

      await _firestore.collection('users').doc(currentUserId).update({
        'travelHistory': FieldValue.arrayUnion([routeId])
      });
    } catch (e) {
      print("Add to travel history error: $e");
      rethrow;
    }
  }

  // Add a route to user's favorites
  Future<void> addToFavorites(String routeId) async {
    try {
      if (currentUserId == null) return;

      await _firestore.collection('users').doc(currentUserId).update({
        'favoriteRoutes': FieldValue.arrayUnion([routeId])
      });
    } catch (e) {
      print("Add to favorites error: $e");
      rethrow;
    }
  }

  // Remove a route from user's favorites
  Future<void> removeFromFavorites(String routeId) async {
    try {
      if (currentUserId == null) return;

      await _firestore.collection('users').doc(currentUserId).update({
        'favoriteRoutes': FieldValue.arrayRemove([routeId])
      });
    } catch (e) {
      print("Remove from favorites error: $e");
      rethrow;
    }
  }

  // Save login state to shared preferences
  Future<void> _saveLoginState(bool isLoggedIn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', isLoggedIn);
  }

  // Check if user is logged in from shared preferences
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }
}
