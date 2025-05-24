import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  bool _darkMode = false;
  String _mapStyle = 'streets'; // streets, dark, satellite, outdoors
  bool _showCrimeHotspots = true;
  bool _routeNotifications = true;
  String _distanceUnit = 'km'; // km, miles
  String _temperatureUnit = 'celsius'; // celsius, fahrenheit

  // Getters
  bool get darkMode => _darkMode;
  String get mapStyle => _mapStyle;
  bool get showCrimeHotspots => _showCrimeHotspots;
  bool get routeNotifications => _routeNotifications;
  String get distanceUnit => _distanceUnit;
  String get temperatureUnit => _temperatureUnit;

  // Initialize settings from shared preferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _darkMode = prefs.getBool('darkMode') ?? false;
    _mapStyle = prefs.getString('mapStyle') ?? 'streets';
    _showCrimeHotspots = prefs.getBool('showCrimeHotspots') ?? true;
    _routeNotifications = prefs.getBool('routeNotifications') ?? true;
    _distanceUnit = prefs.getString('distanceUnit') ?? 'km';
    _temperatureUnit = prefs.getString('temperatureUnit') ?? 'celsius';

    notifyListeners();
  }

  // Toggle dark mode
  Future<void> toggleDarkMode() async {
    _darkMode = !_darkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', _darkMode);
    notifyListeners();
  }

  // Set map style
  Future<void> setMapStyle(String style) async {
    if (_mapStyle != style) {
      _mapStyle = style;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mapStyle', style);
      notifyListeners();
    }
  }

  // Toggle crime hotspots
  Future<void> toggleCrimeHotspots() async {
    _showCrimeHotspots = !_showCrimeHotspots;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showCrimeHotspots', _showCrimeHotspots);
    notifyListeners();
  }

  // Toggle route notifications
  Future<void> toggleRouteNotifications() async {
    _routeNotifications = !_routeNotifications;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('routeNotifications', _routeNotifications);
    notifyListeners();
  }

  // Set distance unit
  Future<void> setDistanceUnit(String unit) async {
    if (_distanceUnit != unit) {
      _distanceUnit = unit;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('distanceUnit', unit);
      notifyListeners();
    }
  }

  // Set temperature unit
  Future<void> setTemperatureUnit(String unit) async {
    if (_temperatureUnit != unit) {
      _temperatureUnit = unit;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('temperatureUnit', unit);
      notifyListeners();
    }
  }

  // Save all settings at once
  Future<void> saveAllSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();

    if (settings.containsKey('darkMode')) {
      _darkMode = settings['darkMode'];
      await prefs.setBool('darkMode', _darkMode);
    }

    if (settings.containsKey('mapStyle')) {
      _mapStyle = settings['mapStyle'];
      await prefs.setString('mapStyle', _mapStyle);
    }

    if (settings.containsKey('showCrimeHotspots')) {
      _showCrimeHotspots = settings['showCrimeHotspots'];
      await prefs.setBool('showCrimeHotspots', _showCrimeHotspots);
    }

    if (settings.containsKey('routeNotifications')) {
      _routeNotifications = settings['routeNotifications'];
      await prefs.setBool('routeNotifications', _routeNotifications);
    }

    if (settings.containsKey('distanceUnit')) {
      _distanceUnit = settings['distanceUnit'];
      await prefs.setString('distanceUnit', _distanceUnit);
    }

    if (settings.containsKey('temperatureUnit')) {
      _temperatureUnit = settings['temperatureUnit'];
      await prefs.setString('temperatureUnit', _temperatureUnit);
    }

    notifyListeners();
  }

  // Reset settings to defaults
  Future<void> resetToDefaults() async {
    _darkMode = false;
    _mapStyle = 'streets';
    _showCrimeHotspots = true;
    _routeNotifications = true;
    _distanceUnit = 'km';
    _temperatureUnit = 'celsius';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', _darkMode);
    await prefs.setString('mapStyle', _mapStyle);
    await prefs.setBool('showCrimeHotspots', _showCrimeHotspots);
    await prefs.setBool('routeNotifications', _routeNotifications);
    await prefs.setString('distanceUnit', _distanceUnit);
    await prefs.setString('temperatureUnit', _temperatureUnit);

    notifyListeners();
  }
}
