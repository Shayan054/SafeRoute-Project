import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:math';
import 'dart:async';  // Add this import for StreamSubscription
import '../../services/ml_service.dart';
import '../../services/firestore_service.dart';
import '../../services/navigation_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MLService _mlService = MLService();
  final FirestoreService _firestoreService = FirestoreService();
  final NavigationService _navigationService = NavigationService();
  final TextEditingController _searchController =
      TextEditingController(); // Keep for now, might refactor
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  String result = "Loading model...";
  bool isLoading = false;
  bool isModelLoaded = false;
  bool isEnvLoaded = false;
  bool isNavigating = false;
  final MapController _mapController = MapController();
  latlong.LatLng _center = latlong.LatLng(31.4900, 74.3000);
  List<latlong.LatLng> _routePoints = [];
  String? _selectedCity;

  // New variables for location and path finding
  Position? _currentPosition;
  latlong.LatLng? _sourceLocation;
  latlong.LatLng? _destinationLocation;
  List<Map<String, dynamic>> _alternativeRoutes = [];
  int _selectedRouteIndex = 0; // Index of the currently selected route

  TimeOfDay _selectedTime = TimeOfDay.now();
  int _selectedDay = DateTime.now().weekday;
  List<Map<String, dynamic>> _crimeLocations = [];
  Map<String, int> _crimeStats = {};

  // Add new variables for crime visualization
  bool _showCrimeHotspots = true;
  List<CircleMarker> _crimeMarkers = [];
  List<CircleMarker> _hotspotMarkers = [];

  // New variables for search suggestions
  List<Map<String, dynamic>> _sourceSuggestions = [];
  List<Map<String, dynamic>> _destinationSuggestions = [];
  bool _isSearchingSource = false;
  bool _isSearchingDestination = false;
  bool _showSourceSuggestions = false;
  bool _showDestinationSuggestions = false;

  // Crime severity mapping
  final Map<String, double> _crimeSeverity = {
    'robbery': 4.0,
    'burglary': 3.0,
    'fraud': 2.0,
    'theft': 2.5,
  };

  // New color scheme
  final Color _primaryColor = Color(0xFF4A6FE3); // Blue primary color
  final Color _accentColor = Color(0xFF6C63FF); // Purple accent color
  final Color _backgroundColor = Color(0xFFF5F7FB); // Light background
  final Color _cardColor = Colors.white;
  final Color _textColor = Color(0xFF2D3748); // Dark text color
  final Color _secondaryTextColor = Color(0xFF718096); // Secondary text color
  final Color _dangerColor =
      Color(0xFFE53E3E); // Red for danger/crime indicators

  // Add new variables for real-time monitoring
  StreamSubscription? _crimeStreamSubscription;
  DateTime? _navigationStartTime;
  bool _isMonitoringCrimes = false;
  List<Map<String, dynamic>> _recentCrimes = [];

  @override
  void initState() {
    super.initState();
    _initializeApp();

    // Add listeners for text controllers to show/hide suggestions
    _sourceController.addListener(() {
      if (_sourceController.text.isNotEmpty) {
        _getSearchSuggestions(_sourceController.text, isSource: true);
      } else {
        setState(() {
          _sourceSuggestions = [];
          _showSourceSuggestions = false;
        });
      }
    });

    _destinationController.addListener(() {
      if (_destinationController.text.isNotEmpty) {
        _getSearchSuggestions(_destinationController.text, isSource: false);
      } else {
        setState(() {
          _destinationSuggestions = [];
          _showDestinationSuggestions = false;
        });
      }
    });
  }

  Future<void> _initializeApp() async {
    try {
      await _loadEnv();
      await _loadModel();
      await _loadInitialLocation(); // Changed from _getCurrentLocation to a new method
      await _loadCrimeData();
    } catch (e) {
      setState(() {
        result = "Initialization failed: ${e.toString()}";
      });
    }
  }

  Future<void> _loadCrimeData() async {
    try {
      _crimeLocations = await _firestoreService.getAllCrimeLocations();
      _crimeStats = {};
      _updateCrimeVisualization();
    } catch (e) {
      setState(() {
        result = "Failed to load crime data";
      });
    }
  }

  void _updateCrimeVisualization() {
    //agr user off krdy ga to crime circle erase ho jay gy
    if (!_showCrimeHotspots) {
      setState(() {
        _crimeMarkers = [];
        _hotspotMarkers = [];
      });
      return;
    }

    // Create markers for individual crimes
    final crimeMarkers = <CircleMarker>[];
    final hotspotMarkers = <CircleMarker>[];
    final crimeDensity = <String, int>{};

    // Calculate crime density in 100m x 100m grid cells
    const double gridSize = 0.001; // approximately 100m

    // Process all crimes in a single pass
    for (var crime in _crimeLocations) {
      // Add individual crime marker
      crimeMarkers.add(
        CircleMarker(
          point: latlong.LatLng(crime['lat'], crime['lng']),
          radius: 8,
          color: Colors.red.withOpacity(0.7),
          borderColor: Colors.red,
          borderStrokeWidth: 2,
        ),
      );

      // Update crime density
      double lat = crime['lat'];
      double lng = crime['lng'];
      String cellKey =
          '${(lat / gridSize).round()},${(lng / gridSize).round()}';
      crimeDensity[cellKey] = (crimeDensity[cellKey] ?? 0) + 1;
    }

    // Create hotspot markers for cells with multiple crimes
    crimeDensity.forEach((cellKey, count) {
      if (count > 1) {
        List<String> coords = cellKey.split(',');
        double lat = double.parse(coords[0]) * gridSize;
        double lng = double.parse(coords[1]) * gridSize;

        double intensity = min(count / 5.0, 1.0);
        Color hotspotColor = Colors.purple.withOpacity(0.5 * intensity);

        hotspotMarkers.add(
          CircleMarker(
            point: latlong.LatLng(lat, lng),
            radius: 50,
            color: hotspotColor,
            borderColor: Colors.transparent,
          ),
        );
      }
    });

    setState(() {
      _crimeMarkers = crimeMarkers;
      _hotspotMarkers = hotspotMarkers;
    });
  }

  Future<void> _loadInitialLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          result = "Location services are disabled.";
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            result = "Location permissions are denied";
          });
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition();
      final newCenter = latlong.LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = position;
        _center = newCenter;
      });

      _mapController.move(newCenter, 15.0);
    } catch (e) {
      setState(() {
        result = "Error getting location";
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          result = "Location services are disabled.";
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            result = "Location permissions are denied";
          });
          return;
        }
      }

      setState(() {
        isLoading = true;
      });

      Position position = await Geolocator.getCurrentPosition();
      final newCenter = latlong.LatLng(position.latitude, position.longitude);

      // Get address from coordinates
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          String address = '';

          if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) {
            address += place.thoroughfare!;
          }

          if (place.subLocality != null && place.subLocality!.isNotEmpty) {
            if (address.isNotEmpty) address += ', ';
            address += place.subLocality!;
          }

          if (place.locality != null && place.locality!.isNotEmpty) {
            if (address.isNotEmpty) address += ', ';
            address += place.locality!;
          }

          if (address.isEmpty) {
            address =
                "Current Location (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})";
          }

          // Update source field and location
          _sourceController.text = address;
          _sourceLocation = newCenter;
        }
      } catch (e) {
        // If geocoding fails, use coordinates
        _sourceController.text =
            "Current Location (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})";
        _sourceLocation = newCenter;
      }

      setState(() {
        _currentPosition = position;
        _center = newCenter;
        isLoading = false;
      });

      _mapController.move(newCenter, 15.0);

      // If destination is already set, find routes
      if (_destinationLocation != null) {
        _findRoutes();
      }
    } catch (e) {
      setState(() {
        result = "Error getting location";
        isLoading = false;
      });
    }
  }

  void _handleMapTap(tapPosition, latlong.LatLng tappedPoint) async {
    if (_sourceLocation == null) {
      setState(() {
        _sourceLocation = tappedPoint;
        _sourceController.text =
            "Tapped: ${tappedPoint.latitude.toStringAsFixed(4)}, ${tappedPoint.longitude.toStringAsFixed(4)}";
      });
      
      // Detect city from source location
      String? detectedCity = await _detectCityFromCoordinates(tappedPoint);
      if (detectedCity != null) {
        setState(() {
          _selectedCity = detectedCity;
        });
      }
    } else if (_destinationLocation == null) {
      setState(() {
        _destinationLocation = tappedPoint;
        _destinationController.text =
            "Tapped: ${tappedPoint.latitude.toStringAsFixed(4)}, ${tappedPoint.longitude.toStringAsFixed(4)}";
      });
      
      // Detect city from destination location
      String? detectedCity = await _detectCityFromCoordinates(tappedPoint);
      if (detectedCity != null) {
        setState(() {
          _selectedCity = detectedCity;
        });
      }
      
      _findRoutes(); // Find routes when both are set
    } else {
      setState(() {
        _sourceLocation = tappedPoint;
        _destinationLocation = null;
        _routePoints = [];
        _alternativeRoutes = [];
        _selectedRouteIndex = 0;
        _sourceController.text =
            "Tapped: ${tappedPoint.latitude.toStringAsFixed(4)}, ${tappedPoint.longitude.toStringAsFixed(4)}";
        _destinationController.clear();
      });
      
      // Detect city from new source location
      String? detectedCity = await _detectCityFromCoordinates(tappedPoint);
      if (detectedCity != null) {
        setState(() {
          _selectedCity = detectedCity;
        });
      }
    }
    _mapController.move(tappedPoint, _mapController.camera.zoom);
  }

  Future<void> _searchLocation(String query, {bool isSource = true}) async {
    if (query.isEmpty) return;

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        Location location = locations.first;
        latlong.LatLng newLocation =
            latlong.LatLng(location.latitude, location.longitude);

        setState(() {
          if (isSource) {
            _sourceLocation = newLocation;
            _sourceController.text = query; // Update text field
          } else {
            _destinationLocation = newLocation;
            _destinationController.text = query; // Update text field
          }
          _mapController.move(newLocation, _mapController.camera.zoom);
        });

        // If both source and destination are set, find routes
        if (_sourceLocation != null && _destinationLocation != null) {
          _findRoutes();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location not found: $query')),
      );
    }
  }

  Future<Map<String, dynamic>> _calculateCrimeMetrics(
      List<latlong.LatLng> points) async {
    int crimeCount = 0;
    double totalSeverity = 0;
    int severityCount = 0;

    const double nearbyRadius = 500; // 500 meters

    for (var crime in _crimeLocations) {
      double crimeLat = crime['lat'];
      double crimeLng = crime['lng'];
      String crimeType =
          crime['crime_type']?.toString().toLowerCase() ?? 'theft';

      for (var point in points) {
        double distance = Geolocator.distanceBetween(
          point.latitude,
          point.longitude,
          crimeLat,
          crimeLng,
        );

        if (distance <= nearbyRadius) {
          crimeCount++;
          double severity = _crimeSeverity[crimeType] ?? 2.0;
          totalSeverity += severity;
          severityCount++;
          break;
        }
      }
    }

    return {
      'crimeCount': crimeCount,
      'avgSeverity': severityCount > 0 ? totalSeverity / severityCount : 0.0,
    };
  }

  Future<void> _findRoutes() async {
    if (_sourceLocation == null || _destinationLocation == null) {
      setState(() {
        result = "Please select both source and destination";
      });
      return;
    }

    setState(() {
      isLoading = true;
      result = "Finding routes...";
      _selectedRouteIndex = -1; // Reset selection while loading
    });

    try {
      final mapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';
      final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/'
          '${_sourceLocation!.longitude},${_sourceLocation!.latitude};'
          '${_destinationLocation!.longitude},${_destinationLocation!.latitude}'
          '?alternatives=true&geometries=geojson&access_token=$mapboxToken';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _alternativeRoutes = [];

        for (var route in data['routes']) {
          List<latlong.LatLng> points = [];
          for (var point in route['geometry']['coordinates']) {
            points.add(latlong.LatLng(point[1], point[0]));
          }

          // Calculate crime metrics for this route
          Map<String, dynamic> crimeMetrics =
              await _calculateCrimeMetrics(points);

          // Calculate safety score for this route
          double safetyScore = await _calculateRouteSafetyScore(
            points,
            crimeMetrics['crimeCount'],
            crimeMetrics['avgSeverity'],
          );

          _alternativeRoutes.add({
            'points': points,
            'distance': route['distance'],
            'duration': route['duration'],
            'safetyScore': safetyScore,
            'crimeCount': crimeMetrics['crimeCount'],
            'avgSeverity': crimeMetrics['avgSeverity'],
          });
        }

        // Sort routes by safety score (highest first)
        _alternativeRoutes
            .sort((a, b) => b['safetyScore'].compareTo(a['safetyScore']));

        setState(() {
          if (_alternativeRoutes.isNotEmpty) {
            _selectedRouteIndex = 0; // Initialize to the first (safest) route
            _routePoints = _alternativeRoutes[0]['points'];
            print(
                'Routes found. Initial route index set to: $_selectedRouteIndex');
          } else {
            _selectedRouteIndex = -1;
            _routePoints = [];
            print(
                'No routes found. Route index reset to: $_selectedRouteIndex');
          }
          result =
              "Found ${_alternativeRoutes.length} routes. Safety scores calculated.";
        });
      } else {
        setState(() {
          result = "Error finding routes: ${response.statusCode}";
          _selectedRouteIndex = -1;
          _routePoints = [];
        });
      }
    } catch (e) {
      setState(() {
        result = "Error finding routes: ${e.toString()}";
        _selectedRouteIndex = -1;
        _routePoints = [];
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<double> _calculateRouteSafetyScore(
    List<latlong.LatLng> points,
    int crimeCount,
    double avgSeverity,
  ) async {
    try {
      // Calculate path length in kilometers
      double pathLength = 0;
      for (int i = 0; i < points.length - 1; i++) {
        pathLength += Geolocator.distanceBetween(
              points[i].latitude,
              points[i].longitude,
              points[i + 1].latitude,
              points[i + 1].longitude,
            ) /
            1000; // Convert to kilometers
      }

      // Convert time to required encoding
      int timeEncoding;
      int hour = _selectedTime.hour;
      if (hour >= 12 && hour < 18) {
        timeEncoding = 0; // Afternoon
      } else if (hour >= 18 && hour < 24) {
        timeEncoding = 1; // Evening
      } else if (hour >= 6 && hour < 12) {
        timeEncoding = 2; // Morning
      } else {
        timeEncoding = 3; // Night
      }

      // Convert city to required encoding
      int cityEncoding;
      switch (_selectedCity?.toLowerCase()) {
        case 'islamabad':
          cityEncoding = 1;
          break;
        case 'karachi':
          cityEncoding = 2;
          break;
        case 'lahore':
          cityEncoding = 3;
          break;
        default:
          cityEncoding = 3; // Default to Lahore if city not found
      }

      // Prepare input for the model
      List<double> input = [
        points.first.latitude, // start_lat
        points.first.longitude, // start_lng
        points.last.latitude, // end_lat
        points.last.longitude, // end_lng
        timeEncoding.toDouble(), // time encoding (0-3)
        _selectedDay / 7.0, // day_of_week normalized
        cityEncoding.toDouble(), // city encoding (1-3)
        crimeCount.toDouble(), // crime_count_nearby
        avgSeverity, // avg_crime_severity
        pathLength, // path_length_km
        0.0 // path_id (always 0)
      ];

      return await _mlService.predictSafetyScore(input);
    } catch (e) {
      print("Error calculating safety score: $e");
      return 0.0; // Return 0.0 or a default safety score in case of error
    }
  }

  Future<void> _loadEnv() async {
    try {
      await dotenv.load();
      setState(() {
        isEnvLoaded = true;
      });
    } catch (e) {
      setState(() {
        result = "Failed to load environment variables: ${e.toString()}";
      });
    }
  }

  Future<void> _loadModel() async {
    try {
      await _mlService.loadModel();
      setState(() {
        isModelLoaded = true;
        result = "Model loaded successfully. Ready for prediction.";
      });
    } catch (e) {
      setState(() {
        result = "Failed to load model: ${e.toString()}";
      });
    }
  }

  void _selectRoute(int index) {
    print('Selecting route at index: $index');
    print('Number of alternative routes: ${_alternativeRoutes.length}');

    setState(() {
      _selectedRouteIndex = index;
      _routePoints = _alternativeRoutes[index]['points'];
      print('Selected route index set to: $_selectedRouteIndex');
      print('Route points length: ${_routePoints.length}');

      // Optionally move the map to center the selected route
      if (_routePoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(_routePoints);
        _mapController.fitCamera(
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
    });
  }

  // Add new method to start crime monitoring
  void _startCrimeMonitoring() {
    if (_isMonitoringCrimes) return;

    setState(() {
      _isMonitoringCrimes = true;
      _navigationStartTime = DateTime.now();
      _recentCrimes = [];
    });

    // Listen to new crimes in Firestore
    _crimeStreamSubscription = FirebaseFirestore.instance
        .collection('firestore_crime')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final newCrime = change.doc.data() as Map<String, dynamic>;
          _checkNewCrime(newCrime);
        }
      }
    });
  }

  // Add method to stop crime monitoring
  void _stopCrimeMonitoring() {
    _crimeStreamSubscription?.cancel();
    setState(() {
      _isMonitoringCrimes = false;
      _navigationStartTime = null;
      _recentCrimes = [];
    });
  }

  // Add method to check new crimes
  void _checkNewCrime(Map<String, dynamic> newCrime) {
    if (!_isMonitoringCrimes || _selectedRouteIndex < 0) return;

    try {
        // Get crime location
        final crimeLat = newCrime['latitude'] as double;
        final crimeLng = newCrime['longitude'] as double;
        final crimeTime = DateTime.parse(newCrime['date'] + ' ' + newCrime['time']);
        
        // Check if crime is recent (within last 5 minutes)
        if (DateTime.now().difference(crimeTime).inMinutes > 5) return;

        // Check if crime is near the selected route
        if (_alternativeRoutes.isEmpty || _selectedRouteIndex >= _alternativeRoutes.length) {
            print('Error: Invalid route index or empty routes');
            return;
        }

        final selectedRoute = _alternativeRoutes[_selectedRouteIndex];
        if (selectedRoute == null || !selectedRoute.containsKey('points')) {
            print('Error: Invalid route data');
            return;
        }

        final routePoints = selectedRoute['points'] as List<latlong.LatLng>;
        if (routePoints.isEmpty) {
            print('Error: No route points available');
            return;
        }
        
        bool isNearRoute = false;
        for (var point in routePoints) {
            double distance = Geolocator.distanceBetween(
                point.latitude,
                point.longitude,
                crimeLat,
                crimeLng,
            );
            
            if (distance <= 500) { // Using 500m radius
                isNearRoute = true;
                break;
            }
        }

        if (isNearRoute) {
            setState(() {
                _recentCrimes.add(newCrime);
            });
            _showCrimeAlert(newCrime);
        }
    } catch (e) {
        print('Error processing new crime: $e');
        // Optionally show a user-friendly error message
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error processing crime alert. Please try again.'),
                backgroundColor: Colors.red,
            ),
        );
    }
  }

  // Add method to show crime alert
  void _showCrimeAlert(Map<String, dynamic> crime) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ Crime Alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A new crime has been reported near your route:'),
            SizedBox(height: 10),
            Text('Type: ${crime['crime_type']}'),
            Text('Time: ${crime['time']}'),
            Text('Location: ${crime['city']}'),
            SizedBox(height: 10),
            Text('Please stay alert and consider taking an alternative route.',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _findRoutes(); // Find alternative routes
            },
            child: Text('Find Alternative Route'),
          ),
        ],
      ),
    );
  }

  // Update _startNavigation method
  void _startNavigation() {
    print('Starting navigation...');
    print('Alternative routes length: ${_alternativeRoutes.length}');
    print('Selected route index: $_selectedRouteIndex');

    if (_alternativeRoutes.isEmpty) {
      print('No routes available');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No routes available')),
      );
      return;
    }

    if (_selectedRouteIndex < 0 ||
        _selectedRouteIndex >= _alternativeRoutes.length) {
      print('Invalid route index: $_selectedRouteIndex');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a route first')),
      );
      return;
    }

    print('Starting navigation with route at index: $_selectedRouteIndex');
    final selectedRoute = _alternativeRoutes[_selectedRouteIndex];
    print('Selected route data: $selectedRoute');

    _navigationService.startNavigation(
      selectedRoute,
      _selectedRouteIndex,
      _mapController,
      context,
    );

    // Start monitoring for new crimes
    _startCrimeMonitoring();

    setState(() {
      isNavigating = _navigationService.isNavigating;
    });
  }

  // Update _stopNavigation method
  void _stopNavigation() {
    _navigationService.stopNavigation();
    _stopCrimeMonitoring(); // Stop monitoring crimes
    setState(() {});
  }

  // Add new method for getting search suggestions
  Future<void> _getSearchSuggestions(String query,
      {required bool isSource}) async {
    if (query.isEmpty) {
      setState(() {
        if (isSource) {
          _sourceSuggestions = [];
          _isSearchingSource = false;
          _showSourceSuggestions = false;
        } else {
          _destinationSuggestions = [];
          _isSearchingDestination = false;
          _showDestinationSuggestions = false;
        }
      });
      return;
    }

    setState(() {
      if (isSource) {
        _isSearchingSource = true;
        _showSourceSuggestions = true;
      } else {
        _isSearchingDestination = true;
        _showDestinationSuggestions = true;
      }
    });

    try {
      final mapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';
      if (mapboxToken.isEmpty) {
        setState(() {
          if (isSource)
            _isSearchingSource = false;
          else
            _isSearchingDestination = false;
        });
        return;
      }

      // Mapbox Geocoding API endpoint for place suggestions
      final url = Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json?access_token=$mapboxToken&autocomplete=true&limit=5');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        List<Map<String, dynamic>> suggestions = [];

        for (var feature in features) {
          suggestions.add({
            'name': feature['place_name'] as String,
            'coordinates': latlong.LatLng(
              feature['center'][1] as double,
              feature['center'][0] as double,
            ),
          });
        }

        setState(() {
          if (isSource) {
            _sourceSuggestions = suggestions;
            _isSearchingSource = false;
          } else {
            _destinationSuggestions = suggestions;
            _isSearchingDestination = false;
          }
        });
      }
    } catch (e) {
      print('Error getting search suggestions: $e');
      setState(() {
        if (isSource)
          _isSearchingSource = false;
        else
          _isSearchingDestination = false;
      });
    }
  }

  void _selectSuggestion(Map<String, dynamic> suggestion,
      {required bool isSource}) async {
    if (isSource) {
      _sourceController.text = suggestion['name'];
      _sourceLocation = suggestion['coordinates'];
      setState(() {
        _showSourceSuggestions = false;
        _sourceSuggestions = [];
      });
      
      // Detect city from source location
      String? detectedCity = await _detectCityFromCoordinates(_sourceLocation!);
      if (detectedCity != null) {
        setState(() {
          _selectedCity = detectedCity;
        });
      }
    } else {
      _destinationController.text = suggestion['name'];
      _destinationLocation = suggestion['coordinates'];
      setState(() {
        _showDestinationSuggestions = false;
        _destinationSuggestions = [];
      });
      
      // Detect city from destination location
      String? detectedCity = await _detectCityFromCoordinates(_destinationLocation!);
      if (detectedCity != null) {
        setState(() {
          _selectedCity = detectedCity;
        });
      }
    }

    _mapController.move(suggestion['coordinates'], 15.0);

    // If both source and destination are set, find routes
    if (_sourceLocation != null && _destinationLocation != null) {
      _findRoutes();
    }
  }

  // Add this new method to detect city from coordinates
  Future<String?> _detectCityFromCoordinates(latlong.LatLng location) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String? city = place.locality;
        
        // Check if the detected city is one of our supported cities
        if (city != null) {
          String cityLower = city.toLowerCase();
          if (cityLower.contains('islamabad') || 
              cityLower.contains('karachi') || 
              cityLower.contains('lahore')) {
            return city;
          }
        }
      }
      return null;
    } catch (e) {
      print("Error detecting city: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isEnvLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: Text("SafeRoute Map", style: TextStyle(color: _textColor)),
          backgroundColor: _cardColor,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: _primaryColor),
              SizedBox(height: 16),
              Text("Loading environment...",
                  style: TextStyle(fontSize: 16, color: _textColor)),
            ],
          ),
        ),
      );
    }

    final mapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';
    if (mapboxToken.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text("SafeRoute Map", style: TextStyle(color: _textColor)),
          backgroundColor: _cardColor,
        ),
        body: Center(
          child: Text("Mapbox token not found. Please check your .env file.",
              style: TextStyle(color: _textColor)),
        ),
      );
    }

    // Determine the currently selected route for details display
    final selectedRoute = _alternativeRoutes.isNotEmpty
        ? _alternativeRoutes[_selectedRouteIndex]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text("SafeRoute Map",
            style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
        backgroundColor: _cardColor,
        elevation: 2,
        actions: [
          if (_navigationService.isNavigating)
            IconButton(
              icon: Icon(Icons.close, color: _dangerColor),
              onPressed: _stopNavigation,
              tooltip: 'Stop Navigation',
            ),
          IconButton(
            icon: Icon(
              _showCrimeHotspots ? Icons.layers : Icons.layers_clear,
              color: _showCrimeHotspots ? _accentColor : Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _showCrimeHotspots = !_showCrimeHotspots;
                _updateCrimeVisualization();
              });
            },
            tooltip: 'Toggle Crime Hotspots',
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13.0,
              onTap: _handleMapTap,
              keepAlive: true,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
                additionalOptions: {
                  'accessToken': mapboxToken,
                },
                tileProvider: NetworkTileProvider(),
                tileBuilder: (context, tileWidget, tile) {
                  return tileWidget;
                },
              ),
              CircleLayer(circles: _hotspotMarkers),
              CircleLayer(circles: _crimeMarkers),
              PolylineLayer(
                polylines: [
                  if (_alternativeRoutes.isNotEmpty)
                    ..._alternativeRoutes.asMap().entries.map((entry) {
                      final index = entry.key;
                      final route = entry.value;
                      return Polyline(
                        points: route['points'],
                        color: index == _selectedRouteIndex
                            ? _accentColor
                            : Colors.blueGrey.withOpacity(0.6),
                        strokeWidth: index == _selectedRouteIndex ? 5.0 : 3.0,
                      );
                    }).toList(),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (_currentPosition != null)
                    Marker(
                      point: latlong.LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      width: 40,
                      height: 40,
                      child: Icon(Icons.directions_car,
                          color: _primaryColor, size: 30),
                    ),
                  if (_sourceLocation != null)
                    Marker(
                      point: _sourceLocation!,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.my_location,
                          color: Colors.green, size: 30),
                    ),
                  if (_destinationLocation != null)
                    Marker(
                      point: _destinationLocation!,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.location_on,
                          color: _accentColor, size: 30),
                    ),
                ],
              ),
            ],
          ),

          // Current Location Button
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _getCurrentLocation,
              child: Icon(Icons.my_location, color: Colors.white),
              backgroundColor: _primaryColor,
            ),
          ),

          // Bottom Panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 0,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: ClampingScrollPhysics(),
                  padding: EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_alternativeRoutes.isEmpty)
                          Column(
                            children: [
                              // Source input with suggestions
                              Container(
                                margin: EdgeInsets.only(
                                    bottom: _showSourceSuggestions ? 0 : 16),
                                child: TextField(
                                  controller: _sourceController,
                                  style: TextStyle(color: _textColor),
                                  decoration: InputDecoration(
                                    hintText: 'Enter Starting Point',
                                    hintStyle:
                                        TextStyle(color: _secondaryTextColor),
                                    prefixIcon: Icon(Icons.my_location,
                                        color: Colors.green),
                                    filled: true,
                                    fillColor: _backgroundColor,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: _primaryColor, width: 1.5),
                                    ),
                                  ),
                                  onSubmitted: (query) =>
                                      _searchLocation(query, isSource: true),
                                  onTap: () {
                                    if (_sourceController.text.isNotEmpty) {
                                      setState(() {
                                        _showSourceSuggestions = true;
                                      });
                                    }
                                  },
                                ),
                              ),

                              // Source suggestions
                              if (_showSourceSuggestions)
                                Container(
                                  margin: EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: _cardColor,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 4,
                                        spreadRadius: 0,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  constraints: BoxConstraints(maxHeight: 200),
                                  child: _isSearchingSource
                                      ? Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: CircularProgressIndicator(
                                                color: _primaryColor),
                                          ),
                                        )
                                      : _sourceSuggestions.isEmpty
                                          ? Padding(
                                              padding:
                                                  const EdgeInsets.all(12.0),
                                              child: Text(
                                                "No suggestions found",
                                                style: TextStyle(
                                                    color: _secondaryTextColor),
                                              ),
                                            )
                                          : ListView.builder(
                                              shrinkWrap: true,
                                              padding: EdgeInsets.zero,
                                              itemCount:
                                                  _sourceSuggestions.length,
                                              itemBuilder: (context, index) {
                                                final suggestion =
                                                    _sourceSuggestions[index];
                                                return ListTile(
                                                  title: Text(
                                                    suggestion['name'],
                                                    style: TextStyle(
                                                        color: _textColor),
                                                  ),
                                                  leading: Icon(
                                                      Icons.location_on,
                                                      color: _primaryColor),
                                                  onTap: () =>
                                                      _selectSuggestion(
                                                          suggestion,
                                                          isSource: true),
                                                );
                                              },
                                            ),
                                ),

                              // Destination input with suggestions
                              Container(
                                margin: EdgeInsets.only(
                                    bottom:
                                        _showDestinationSuggestions ? 0 : 16),
                                child: TextField(
                                  controller: _destinationController,
                                  style: TextStyle(color: _textColor),
                                  decoration: InputDecoration(
                                    hintText: 'Enter Destination',
                                    hintStyle:
                                        TextStyle(color: _secondaryTextColor),
                                    prefixIcon: Icon(Icons.location_on,
                                        color: _accentColor),
                                    filled: true,
                                    fillColor: _backgroundColor,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: _accentColor, width: 1.5),
                                    ),
                                  ),
                                  onSubmitted: (query) =>
                                      _searchLocation(query, isSource: false),
                                  onTap: () {
                                    if (_destinationController
                                        .text.isNotEmpty) {
                                      setState(() {
                                        _showDestinationSuggestions = true;
                                      });
                                    }
                                  },
                                ),
                              ),

                              // Destination suggestions
                              if (_showDestinationSuggestions)
                                Container(
                                  margin: EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: _cardColor,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 4,
                                        spreadRadius: 0,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  constraints: BoxConstraints(maxHeight: 200),
                                  child: _isSearchingDestination
                                      ? Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: CircularProgressIndicator(
                                                color: _accentColor),
                                          ),
                                        )
                                      : _destinationSuggestions.isEmpty
                                          ? Padding(
                                              padding:
                                                  const EdgeInsets.all(12.0),
                                              child: Text(
                                                "No suggestions found",
                                                style: TextStyle(
                                                    color: _secondaryTextColor),
                                              ),
                                            )
                                          : ListView.builder(
                                              shrinkWrap: true,
                                              padding: EdgeInsets.zero,
                                              itemCount: _destinationSuggestions
                                                  .length,
                                              itemBuilder: (context, index) {
                                                final suggestion =
                                                    _destinationSuggestions[
                                                        index];
                                                return ListTile(
                                                  title: Text(
                                                    suggestion['name'],
                                                    style: TextStyle(
                                                        color: _textColor),
                                                  ),
                                                  leading: Icon(
                                                      Icons.location_on,
                                                      color: _accentColor),
                                                  onTap: () =>
                                                      _selectSuggestion(
                                                          suggestion,
                                                          isSource: false),
                                                );
                                              },
                                            ),
                                ),

                              if (isLoading)
                                Center(
                                    child: CircularProgressIndicator(
                                        color: _accentColor)),
                              if (!isLoading &&
                                  (_sourceLocation != null ||
                                      _destinationLocation != null) &&
                                  !result.contains("Model loaded successfully"))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    result,
                                    style:
                                        TextStyle(color: _secondaryTextColor),
                                  ),
                                ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (selectedRoute != null)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "${(selectedRoute['duration'] / 60).round()} min (${(selectedRoute['distance'] / 1000).toStringAsFixed(1)} km)",
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: _textColor,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      "Route ${_selectedRouteIndex + 1} - Safety Score: ${selectedRoute['safetyScore'].toStringAsFixed(2)}",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: _accentColor,
                                      ),
                                    ),
                                    SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _primaryColor,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            "Safety: ${selectedRoute['safetyScore'].toStringAsFixed(2)}",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _dangerColor,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            "Crimes: ${selectedRoute['crimeCount']}",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 10),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Column(
                                          children: [
                                            Icon(Icons.my_location,
                                                color: Colors.green, size: 18),
                                            SizedBox(height: 3),
                                            Icon(Icons.more_vert,
                                                color: _secondaryTextColor,
                                                size: 18),
                                            SizedBox(height: 3),
                                            Icon(Icons.location_on,
                                                color: _accentColor, size: 18),
                                          ],
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _sourceController
                                                        .text.isNotEmpty
                                                    ? _sourceController.text
                                                    : "Starting Point",
                                                style: TextStyle(
                                                    color: _textColor,
                                                    fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              SizedBox(height: 10),
                                              Text(
                                                _destinationController
                                                        .text.isNotEmpty
                                                    ? _destinationController
                                                        .text
                                                    : "Destination",
                                                style: TextStyle(
                                                    color: _textColor,
                                                    fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              SizedBox(height: 10),
                              Text(
                                "Available Routes:",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _textColor,
                                ),
                              ),
                              SizedBox(height: 4),
                              SizedBox(
                                height: 85,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _alternativeRoutes.length,
                                  itemBuilder: (context, index) {
                                    final route = _alternativeRoutes[index];
                                    final isSelected =
                                        index == _selectedRouteIndex;
                                    return GestureDetector(
                                      onTap: () => _selectRoute(index),
                                      child: Card(
                                        color: isSelected
                                            ? _primaryColor
                                            : _backgroundColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          side: isSelected
                                              ? BorderSide(
                                                  color: _accentColor,
                                                  width: 1.5)
                                              : BorderSide.none,
                                        ),
                                        elevation: isSelected ? 3 : 1,
                                        margin: EdgeInsets.only(
                                            right: 8, bottom: 2),
                                        child: Container(
                                          width: 150,
                                          padding: EdgeInsets.all(8),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Route ${index + 1}",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : _textColor,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                "${(route['duration'] / 60).round()} min | ${(route['distance'] / 1000).toStringAsFixed(1)} km",
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isSelected
                                                      ? Colors.white70
                                                      : _secondaryTextColor,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                "Safety: ${route['safetyScore'].toStringAsFixed(2)}",
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : _accentColor,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // Add Start Navigation button inside the bottom panel
                              if (!_navigationService.isNavigating)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10.0),
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 40,
                                    child: ElevatedButton(
                                      onPressed: _startNavigation,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _accentColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        elevation: 1,
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: Text(
                                        'Start Navigation',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Navigation Info Panel
          if (_navigationService.isNavigating)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Navigation Active',
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Following the safest route to your destination',
                      style: TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNavigationInfo(
                          Icons.timer,
                          '${(_navigationService.getNavigationInfo()['duration'] / 60).round()} min',
                        ),
                        _buildNavigationInfo(
                          Icons.straighten,
                          '${(_navigationService.getNavigationInfo()['distance'] / 1000).toStringAsFixed(1)} km',
                        ),
                        _buildNavigationInfo(
                          Icons.security,
                          'Safety: ${_navigationService.getNavigationInfo()['safetyScore'].toStringAsFixed(2)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavigationInfo(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: _accentColor, size: 24),
        SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            color: _textColor,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _stopCrimeMonitoring(); // Clean up crime monitoring
    _mlService.dispose();
    _mapController.dispose();
    _sourceController.dispose();
    _destinationController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
