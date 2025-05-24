import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart' as latlong;

class AppProvider with ChangeNotifier {
  bool _isInitialized = false;
  bool _isFirstLaunch = true;
  String _currentPage = 'map';
  List<Map<String, dynamic>> _recentRoutes = [];
  List<Map<String, dynamic>> _savedLocations = [];

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isFirstLaunch => _isFirstLaunch;
  String get currentPage => _currentPage;
  List<Map<String, dynamic>> get recentRoutes => _recentRoutes;
  List<Map<String, dynamic>> get savedLocations => _savedLocations;

  // Initialize app state
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if it's the first launch
    _isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;

    // Load recent routes
    String? recentRoutesJson = prefs.getString('recentRoutes');
    if (recentRoutesJson != null) {
      List<dynamic> decoded = jsonDecode(recentRoutesJson);
      _recentRoutes = List<Map<String, dynamic>>.from(decoded);
    }

    // Load saved locations
    String? savedLocationsJson = prefs.getString('savedLocations');
    if (savedLocationsJson != null) {
      List<dynamic> decoded = jsonDecode(savedLocationsJson);
      _savedLocations = List<Map<String, dynamic>>.from(decoded);
    }

    _isInitialized = true;
    notifyListeners();
  }

  // Set first launch flag
  Future<void> completeFirstLaunch() async {
    if (_isFirstLaunch) {
      _isFirstLaunch = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isFirstLaunch', false);
      notifyListeners();
    }
  }

  // Set current page
  void setCurrentPage(String page) {
    if (_currentPage != page) {
      _currentPage = page;
      notifyListeners();
    }
  }

  // Add a recent route
  Future<void> addRecentRoute(Map<String, dynamic> route) async {
    // Add a unique ID if not present
    if (!route.containsKey('id')) {
      route['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    }

    // Add timestamp if not present
    if (!route.containsKey('timestamp')) {
      route['timestamp'] = DateTime.now().toIso8601String();
    }

    // Remove duplicate routes (same start and end points)
    _recentRoutes.removeWhere((r) =>
        r['startLat'] == route['startLat'] &&
        r['startLng'] == route['startLng'] &&
        r['endLat'] == route['endLat'] &&
        r['endLng'] == route['endLng']);

    // Add the new route at the beginning
    _recentRoutes.insert(0, route);

    // Keep only the 10 most recent routes
    if (_recentRoutes.length > 10) {
      _recentRoutes = _recentRoutes.sublist(0, 10);
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recentRoutes', jsonEncode(_recentRoutes));

    notifyListeners();
  }

  // Clear recent routes
  Future<void> clearRecentRoutes() async {
    _recentRoutes = [];

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recentRoutes');

    notifyListeners();
  }

  // Add a saved location
  Future<void> addSavedLocation({
    required String name,
    required double latitude,
    required double longitude,
    String? address,
    String? notes,
    String? icon,
  }) async {
    // Create location object
    final location = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'notes': notes,
      'icon': icon,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Add to saved locations
    _savedLocations.add(location);

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savedLocations', jsonEncode(_savedLocations));

    notifyListeners();
  }

  // Remove a saved location
  Future<void> removeSavedLocation(String id) async {
    _savedLocations.removeWhere((location) => location['id'] == id);

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savedLocations', jsonEncode(_savedLocations));

    notifyListeners();
  }

  // Update a saved location
  Future<void> updateSavedLocation({
    required String id,
    String? name,
    double? latitude,
    double? longitude,
    String? address,
    String? notes,
    String? icon,
  }) async {
    final index =
        _savedLocations.indexWhere((location) => location['id'] == id);

    if (index != -1) {
      if (name != null) _savedLocations[index]['name'] = name;
      if (latitude != null) _savedLocations[index]['latitude'] = latitude;
      if (longitude != null) _savedLocations[index]['longitude'] = longitude;
      if (address != null) _savedLocations[index]['address'] = address;
      if (notes != null) _savedLocations[index]['notes'] = notes;
      if (icon != null) _savedLocations[index]['icon'] = icon;

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('savedLocations', jsonEncode(_savedLocations));

      notifyListeners();
    }
  }

  // Get a saved location by ID
  Map<String, dynamic>? getSavedLocationById(String id) {
    final location = _savedLocations.firstWhere(
      (location) => location['id'] == id,
      orElse: () => <String, dynamic>{},
    );

    return location.isNotEmpty ? location : null;
  }

  // Reset app state
  Future<void> resetAppState() async {
    _isFirstLaunch = true;
    _currentPage = 'map';
    _recentRoutes = [];
    _savedLocations = [];

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    notifyListeners();
  }
}
