import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:math';
import '../../services/ml_service.dart';
import '../../services/firestore_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geocoding/geocoding.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MLService _mlService = MLService();
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String result = "Loading model...";
  bool isLoading = false;
  bool isModelLoaded = false;
  bool isEnvLoaded = false;
  final MapController _mapController = MapController();
  latlong.LatLng _center = latlong.LatLng(31.4900, 74.3000);
  List<latlong.LatLng> _routePoints = [];
  
  // New variables for location and path finding
  Position? _currentPosition;
  latlong.LatLng? _sourceLocation;
  latlong.LatLng? _destinationLocation;
  List<Map<String, dynamic>> _alternativeRoutes = [];
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _selectedDay = DateTime.now().weekday;
  List<Map<String, dynamic>> _crimeLocations = [];
  Map<String, int> _crimeStats = {};
  
  // Add new variables for crime visualization
  bool _showCrimeHotspots = true;
  List<CircleMarker> _crimeMarkers = [];
  List<CircleMarker> _hotspotMarkers = [];
  
  // Crime severity mapping
  final Map<String, double> _crimeSeverity = {
    'robbery': 4.0,
    'burglary': 3.0,
    'fraud': 2.0,
    'theft': 2.5,
  };

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await _loadEnv();
      await _loadModel();
      await _getCurrentLocation();
      await _loadCrimeData();
    } catch (e) {
      setState(() {
        result = "Initialization failed: ${e.toString()}";
      });
    }
  }

  Future<void> _loadCrimeData() async {
    try {
      // Load all crime locations, not just for Lahore
      _crimeLocations = await _firestoreService.getAllCrimeLocations();
      _crimeStats = {};
      _updateCrimeVisualization();
    } catch (e) {
      print("Error loading crime data: $e");
    }
  }

  void _updateCrimeVisualization() {
    if (!_showCrimeHotspots) {
      setState(() {
        _crimeMarkers = [];
        _hotspotMarkers = [];
      });
      return;
    }

    // Create markers for individual crimes
    List<CircleMarker> crimeMarkers = [];
    for (var crime in _crimeLocations) {
      crimeMarkers.add(
        CircleMarker(
          point: latlong.LatLng(crime['lat'], crime['lng']),
          radius: 8,
          color: Colors.red.withOpacity(0.7),
          borderColor: Colors.red,
          borderStrokeWidth: 2,
        ),
      );
    }

    // Create hotspot markers (areas with high crime density)
    List<CircleMarker> hotspotMarkers = [];
    Map<String, int> crimeDensity = {};

    // Calculate crime density in 100m x 100m grid cells
    const double gridSize = 0.001; // approximately 100m
    for (var crime in _crimeLocations) {
      double lat = crime['lat'];
      double lng = crime['lng'];
      
      // Round to nearest grid cell
      String cellKey = '${(lat / gridSize).round()},${(lng / gridSize).round()}';
      crimeDensity[cellKey] = (crimeDensity[cellKey] ?? 0) + 1;
    }

    // Create hotspot markers for cells with multiple crimes
    crimeDensity.forEach((cellKey, count) {
      if (count > 1) {
        List<String> coords = cellKey.split(',');
        double lat = double.parse(coords[0]) * gridSize;
        double lng = double.parse(coords[1]) * gridSize;

        // Calculate color intensity based on crime count
        double intensity = min(count / 5.0, 1.0); // Normalize to 0-1
        Color hotspotColor = Colors.red.withOpacity(0.3 * intensity);

        hotspotMarkers.add(
          CircleMarker(
            point: latlong.LatLng(lat, lng),
            radius: 50, // 50m radius
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

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _center = latlong.LatLng(position.latitude, position.longitude);
      });
      _mapController.move(latlong.LatLng(position.latitude, position.longitude), 15.0);
    } catch (e) {
      setState(() {
        result = "Error getting location: ${e.toString()}";
      });
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        Location location = locations.first;
        latlong.LatLng newLocation = latlong.LatLng(location.latitude, location.longitude);
        
        setState(() {
          if (_sourceLocation == null) {
            _sourceLocation = newLocation;
          } else {
            _destinationLocation = newLocation;
            _findRoutes();
          }
          _mapController.move(newLocation, 15.0);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location not found: $query')),
      );
    }
  }

  Future<Map<String, dynamic>> _calculateCrimeMetrics(List<latlong.LatLng> points) async {
    int crimeCount = 0;
    double totalSeverity = 0;
    int severityCount = 0;

    const double nearbyRadius = 500; // 500 meters

    for (var crime in _crimeLocations) {
      double crimeLat = crime['lat'];
      double crimeLng = crime['lng'];
      String crimeType = crime['crime_type']?.toString().toLowerCase() ?? 'theft';
      
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
          Map<String, dynamic> crimeMetrics = await _calculateCrimeMetrics(points);
          
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

        // Sort routes by safety score
        _alternativeRoutes.sort((a, b) => b['safetyScore'].compareTo(a['safetyScore']));
        
        setState(() {
          _routePoints = _alternativeRoutes[0]['points'];
          result = "Found ${_alternativeRoutes.length} routes. Safety scores calculated.";
        });
      }
    } catch (e) {
      setState(() {
        result = "Error finding routes: ${e.toString()}";
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
        ) / 1000; // Convert to kilometers
      }

      // Prepare input for the model
      List<double> input = [
        points.first.latitude,  // start_lat
        points.first.longitude, // start_lng
        points.last.latitude,   // end_lat
        points.last.longitude,  // end_lng
        _selectedTime.hour / 24.0, // time_of_day normalized
        _selectedDay / 7.0,     // day_of_week normalized
        0.0,                    // city (Lahore)
        crimeCount.toDouble(),  // crime_count_nearby
        avgSeverity,            // avg_crime_severity
        pathLength,             // path_length_km
        1.0                     // path_id
      ];

      return await _mlService.predictSafetyScore(input);
    } catch (e) {
      print("Error calculating safety score: $e");
      return 0.0;
    }
  }

  Future<void> _loadEnv() async {
    try {
      await dotenv.load();
      setState(() {
        isEnvLoaded = true;
      });
      print('Environment loaded successfully');
      final token = dotenv.env['MAPBOX_TOKEN'] ?? '';
      print('Mapbox Token length: ${token.length}');
      print('Mapbox Token first 10 chars: ${token.substring(0, min(10, token.length))}');
      print('Mapbox Token last 10 chars: ${token.substring(max(0, token.length - 10))}');
    } catch (e) {
      print('Error loading environment: $e');
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

  @override
  Widget build(BuildContext context) {
    if (!isEnvLoaded) {
      return Scaffold(
        appBar: AppBar(title: Text("SafeRoute Map")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Loading environment...", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final mapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';
    if (mapboxToken.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text("SafeRoute Map")),
        body: Center(
          child: Text("Mapbox token not found. Please check your .env file."),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("SafeRoute Map"),
        actions: [
          IconButton(
            icon: Icon(
              _showCrimeHotspots ? Icons.layers : Icons.layers_clear,
              color: _showCrimeHotspots ? Colors.red : Colors.grey,
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search location...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                ),
              ),
              onSubmitted: _searchLocation,
            ),
          ),
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 13.0,
                    onTap: (tapPosition, point) {
                      setState(() {
                        if (_sourceLocation == null) {
                          _sourceLocation = point;
                        } else if (_destinationLocation == null) {
                          _destinationLocation = point;
                          _findRoutes();
                        } else {
                          _sourceLocation = point;
                          _destinationLocation = null;
                          _routePoints = [];
                        }
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
                      additionalOptions: {
                        'accessToken': mapboxToken,
                      },
                    ),
                    CircleLayer(
                      circles: _hotspotMarkers,
                    ),
                    CircleLayer(
                      circles: _crimeMarkers,
                    ),
                    PolylineLayer(
                      polylines: [
                        if (_alternativeRoutes.isNotEmpty)
                          ..._alternativeRoutes.asMap().entries.map((entry) {
                            final index = entry.key;
                            final route = entry.value;
                            return Polyline(
                              points: route['points'],
                              color: index == 0 ? Colors.blue : Colors.black.withOpacity(0.3),
                              strokeWidth: index == 0 ? 4.0 : 2.0,
                            );
                          }).toList(),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        if (_currentPosition != null)
                          Marker(
                            point: latlong.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                            width: 40,
                            height: 40,
                            child: Icon(Icons.my_location, color: Colors.blue),
                          ),
                        if (_sourceLocation != null)
                          Marker(
                            point: _sourceLocation!,
                            width: 40,
                            height: 40,
                            child: Icon(Icons.location_on, color: Colors.green),
                          ),
                        if (_destinationLocation != null)
                          Marker(
                            point: _destinationLocation!,
                            width: 40,
                            height: 40,
                            child: Icon(Icons.location_on, color: Colors.red),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: FloatingActionButton(
                    onPressed: _getCurrentLocation,
                    child: Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading) 
                  Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text("Processing...", style: TextStyle(fontSize: 16)),
                    ],
                  ),

                if (!isLoading) 
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      result,
                      style: TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ),

                if (_alternativeRoutes.isNotEmpty)
                  Container(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _alternativeRoutes.length,
                      itemBuilder: (context, index) {
                        final route = _alternativeRoutes[index];
                        return Card(
                          margin: EdgeInsets.all(8),
                          child: Container(
                            width: 200,
                            padding: EdgeInsets.all(8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Route ${index + 1}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Safety: ${route['safetyScore'].toStringAsFixed(2)}",
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  "Distance: ${(route['distance'] / 1000).toStringAsFixed(1)} km",
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  "Crimes: ${route['crimeCount']}",
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  "Severity: ${route['avgSeverity'].toStringAsFixed(1)}",
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mlService.dispose();
    _mapController.dispose();
    super.dispose();
  }
}
