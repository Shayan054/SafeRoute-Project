import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

class NavigationService {
  bool isNavigating = false;
  List<latlong.LatLng> currentRoutePoints = [];
  Map<String, dynamic>? currentRoute;
  int selectedRouteIndex = 0;
  List<Map<String, dynamic>> alternativeRoutes = [];

  void startNavigation(Map<String, dynamic> route, int routeIndex, MapController mapController, BuildContext context) {
    print('NavigationService: Starting navigation');
    print('NavigationService: Route index: $routeIndex');
    print('NavigationService: Route data: $route');

    if (route == null) {
      print('NavigationService: Route is null');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid route data')),
      );
      return;
    }

    isNavigating = true;
    currentRoute = route;
    selectedRouteIndex = routeIndex;
    currentRoutePoints = List<latlong.LatLng>.from(route['points']);

    print('NavigationService: Navigation started');
    print('NavigationService: Points count: ${currentRoutePoints.length}');

    // Center the map on the selected route
    if (currentRoutePoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(currentRoutePoints);
      mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 100,
            bottom: 306,
            left: 50,
            right: 50,
          ),
        ),
      );
    }
  }

  void stopNavigation() {
    print('NavigationService: Stopping navigation');
    isNavigating = false;
    currentRoute = null;
    currentRoutePoints = [];
    selectedRouteIndex = 0;
  }

  void updateRouteProgress(Position currentPosition) {
    if (!isNavigating || currentRoutePoints.isEmpty) return;

    // Find the closest point on the route to the current position
    double minDistance = double.infinity;
    int closestPointIndex = 0;

    for (int i = 0; i < currentRoutePoints.length; i++) {
      double distance = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        currentRoutePoints[i].latitude,
        currentRoutePoints[i].longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestPointIndex = i;
      }
    }

    // Update the route points to show only the remaining path
    if (closestPointIndex > 0) {
      currentRoutePoints = currentRoutePoints.sublist(closestPointIndex);
    }
  }

  Map<String, dynamic> getNavigationInfo() {
    if (currentRoute == null) {
      print('NavigationService: No current route for navigation info');
      return {
        'duration': 0,
        'distance': 0,
        'safetyScore': 0.0,
      };
    }

    print('NavigationService: Getting navigation info for route');
    return {
      'duration': currentRoute!['duration'],
      'distance': currentRoute!['distance'],
      'safetyScore': currentRoute!['safetyScore'],
    };
  }
} 