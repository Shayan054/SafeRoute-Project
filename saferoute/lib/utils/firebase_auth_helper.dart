import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class FirebaseAuthHelper {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static bool _isRecaptchaVerified = false;

  /// Initialize Firebase Auth with proper settings
  static Future<void> initialize() async {
    try {
      // Set persistence to LOCAL
      await _auth.setPersistence(Persistence.LOCAL);

      // Configure Firebase Auth settings
      await _auth.setSettings(
        appVerificationDisabledForTesting: kDebugMode && !kIsWeb,
        phoneNumber: null,
        smsCode: null,
        forceRecaptchaFlow: false,
      );

      print("Firebase Auth Helper initialized successfully");
    } catch (e) {
      print("Error initializing Firebase Auth Helper: $e");
    }
  }

  /// Sign in with email and password with improved error handling
  static Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      // Try to sign in
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _isRecaptchaVerified = true;
      return result;
    } on FirebaseAuthException catch (e) {
      print("Firebase Auth Exception: ${e.code} - ${e.message}");

      // Handle reCAPTCHA errors
      if (e.code == 'unknown' &&
          (e.message?.contains('recaptcha') == true ||
              e.message?.contains('credential is incorrect') == true)) {
        throw FirebaseAuthException(
          code: 'recaptcha-verification-failed',
          message:
              'Authentication failed. Please restart the app and try again.',
        );
      }

      rethrow;
    } catch (e) {
      print("Generic Auth Error: $e");
      rethrow;
    }
  }

  /// Create user with email and password with improved error handling
  static Future<UserCredential> createUserWithEmailAndPassword(
      String email, String password) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      _isRecaptchaVerified = true;
      return result;
    } on FirebaseAuthException catch (e) {
      print("Firebase Auth Exception: ${e.code} - ${e.message}");

      // Handle reCAPTCHA errors
      if (e.code == 'unknown' &&
          (e.message?.contains('recaptcha') == true ||
              e.message?.contains('credential is incorrect') == true)) {
        throw FirebaseAuthException(
          code: 'recaptcha-verification-failed',
          message: 'Registration failed. Please restart the app and try again.',
        );
      }

      rethrow;
    } catch (e) {
      print("Generic Auth Error: $e");
      rethrow;
    }
  }

  /// Send password reset email with improved error handling
  static Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      print("Firebase Auth Exception: ${e.code} - ${e.message}");
      rethrow;
    } catch (e) {
      print("Generic Auth Error: $e");
      rethrow;
    }
  }

  /// Sign out user
  static Future<void> signOut() async {
    await _auth.signOut();
    _isRecaptchaVerified = false;
  }

  /// Get current user
  static User? get currentUser => _auth.currentUser;

  /// Check if user is verified with reCAPTCHA
  static bool get isRecaptchaVerified => _isRecaptchaVerified;
}
