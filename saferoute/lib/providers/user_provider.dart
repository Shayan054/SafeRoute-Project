import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class UserProvider with ChangeNotifier {
  UserModel? _user;
  bool _isLoading = false;
  String? _error;
  final AuthService _authService = AuthService();

  // Getters
  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;

  // Initialize user on app start
  Future<bool> initializeUser() async {
    try {
      _setLoading(true);
      final isUserLoggedIn = await _authService.isLoggedIn();

      if (isUserLoggedIn) {
        await refreshUserData();
        _setLoading(false);
        return true;
      }

      _setLoading(false);
      return false;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Refresh user data from Firestore
  Future<void> refreshUserData() async {
    try {
      final userData = await _authService.getUserData();
      if (userData != null) {
        _user = userData;
        notifyListeners();
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Register new user
  Future<bool> registerUser(String email, String password,
      {String? displayName, String? photoURL}) async {
    try {
      _setLoading(true);
      _clearError();

      // Register the user with Firebase Auth
      final result =
          await _authService.registerWithEmailAndPassword(email, password);

      // Create user document in Firestore with additional fields
      await FirebaseFirestore.instance
          .collection('users')
          .doc(result.user!.uid)
          .set({
        'uid': result.user!.uid,
        'email': email,
        'displayName': displayName ?? ''
      });

      // Refresh user data
      await refreshUserData();

      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Sign in user
  Future<bool> signIn(String email, String password) async {
    try {
      _setLoading(true);
      _clearError();

      // Try to sign in with Firebase Auth
      try {
        await _authService.signInWithEmailAndPassword(email, password);
      } catch (e) {
        String errorMessage = e.toString();

        // Handle specific Firebase Auth errors
        if (errorMessage.contains('wrong-password') ||
            errorMessage.contains('user-not-found') ||
            errorMessage.contains('invalid-credential')) {
          _setError('Invalid email or password. Please try again.');
        } else if (errorMessage.contains('too-many-requests')) {
          _setError('Too many failed login attempts. Please try again later.');
        } else if (errorMessage.contains('network-request-failed')) {
          _setError(
              'Network error. Please check your connection and try again.');
        } else if (errorMessage.contains('recaptcha') ||
            errorMessage.contains('captcha') ||
            errorMessage.contains('credential is incorrect')) {
          // Handle reCAPTCHA verification errors
          _setError(
              'Authentication failed. Please restart the app and try again.');
        } else {
          _setError(errorMessage);
        }

        _setLoading(false);
        return false;
      }

      await refreshUserData();

      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Sign out user
  Future<void> signOut() async {
    try {
      _setLoading(true);
      await _authService.signOut();
      _user = null;
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
    }
  }

  // Update user profile
  Future<bool> updateProfile({String? displayName, String? photoURL}) async {
    try {
      _setLoading(true);

      await _authService.updateUserProfile(
        displayName: displayName,
        photoURL: photoURL,
      );

      await refreshUserData();

      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Add route to favorites
  Future<void> addRouteToFavorites(String routeId) async {
    try {
      await _authService.addToFavorites(routeId);
      await refreshUserData();
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Remove route from favorites
  Future<void> removeRouteFromFavorites(String routeId) async {
    try {
      await _authService.removeFromFavorites(routeId);
      await refreshUserData();
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Add route to history
  Future<void> addRouteToHistory(String routeId) async {
    try {
      await _authService.addToTravelHistory(routeId);
      await refreshUserData();
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Send password reset email
  Future<bool> sendPasswordReset(String email) async {
    try {
      _setLoading(true);
      await _authService.sendPasswordResetEmail(email);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }
}
