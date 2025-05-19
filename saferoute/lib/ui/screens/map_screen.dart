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
  final TextEditingController _searchController = TextEditingController(); // Keep for now, might refactor
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
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
  int _selectedRouteIndex = 0; // Index of the currently selected route

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
      await _getCurrentLocation(); // Get initial current location
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
        Color hotspotColor = Colors.purple.withOpacity(0.5 * intensity); // Changed to purple

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

   void _handleMapTap(tapPosition, latlong.LatLng tappedPoint) {
    setState(() {
      if (_sourceLocation == null) {
        _sourceLocation = tappedPoint;
        // Optionally update source text field with coordinates or reverse geocode
        _sourceController.text = "Tapped: ${tappedPoint.latitude.toStringAsFixed(4)}, ${tappedPoint.longitude.toStringAsFixed(4)}";
      } else if (_destinationLocation == null) {
        _destinationLocation = tappedPoint;
         // Optionally update destination text field
        _destinationController.text = "Tapped: ${tappedPoint.latitude.toStringAsFixed(4)}, ${tappedPoint.longitude.toStringAsFixed(4)}";
        _findRoutes(); // Find routes when both are set
      } else {
        // Reset if both are already set
        _sourceLocation = tappedPoint;
        _destinationLocation = null;
        _routePoints = [];
        _alternativeRoutes = [];
        _selectedRouteIndex = 0; // Reset selected route index
        _sourceController.text = "Tapped: ${tappedPoint.latitude.toStringAsFixed(4)}, ${tappedPoint.longitude.toStringAsFixed(4)}";
        _destinationController.clear();
      }
       _mapController.move(tappedPoint, _mapController.camera.zoom); // Move map to tapped location
    });
  }


  Future<void> _searchLocation(String query, {bool isSource = true}) async {
    if (query.isEmpty) return;

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        Location location = locations.first;
        latlong.LatLng newLocation = latlong.LatLng(location.latitude, location.longitude);

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

        // Sort routes by safety score (highest first)
        _alternativeRoutes.sort((a, b) => b['safetyScore'].compareTo(a['safetyScore']));

        setState(() {
          _routePoints = _alternativeRoutes[_selectedRouteIndex]['points'];
          result = "Found ${_alternativeRoutes.length} routes. Safety scores calculated.";
        });
      } else {
         setState(() {
           result = "Error finding routes: ${response.statusCode}";
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
        0.0,                    // city (Lahore) - Assuming 0.0 for Lahore based on potential model input
        crimeCount.toDouble(),  // crime_count_nearby
        avgSeverity,            // avg_crime_severity
        pathLength,             // path_length_km
        1.0                     // path_id - Assuming 1.0 as a placeholder for path ID if needed by the model
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

  void _selectRoute(int index) {
    setState(() {
      _selectedRouteIndex = index;
      _routePoints = _alternativeRoutes[index]['points'];
       // Optionally move the map to center the selected route
       if (_routePoints.isNotEmpty) {
         final bounds = LatLngBounds.fromPoints(_routePoints);
         _mapController.fitCamera(
           CameraFit.bounds(
             bounds: bounds,
             padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 100, // Adjust padding
                bottom: 306, // Adjust padding further to fix overflow
                left: 50,
                right: 50,
             ),
           ),
         );
       }
    });
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

    // Determine the currently selected route for details display
    final selectedRoute = _alternativeRoutes.isNotEmpty ? _alternativeRoutes[_selectedRouteIndex] : null;


    return Scaffold(
      // AppBar will be adjusted or removed based on final design
      appBar: AppBar(
        title: Text("SafeRoute Map"),
        backgroundColor: Colors.black87, // Dark theme AppBar
        foregroundColor: Colors.white, // White text for AppBar
        actions: [
          IconButton(
            icon: Icon(
              _showCrimeHotspots ? Icons.layers : Icons.layers_clear,
              color: _showCrimeHotspots ? Colors.purpleAccent : Colors.grey, // Purple accent
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
      extendBodyBehindAppBar: true, // Extend map behind AppBar
      body: Stack(
        children: [
          // Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13.0,
              onTap: _handleMapTap, // Re-enabled map tapping with corrected signature
            ),
            children: [
              TileLayer(
                // Using a dark map style URL if available or a general one
                urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/dark-v10/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
                additionalOptions: {
                  'accessToken': mapboxToken,
                },
              ),
              // Crime Hotspot Circles (color already changed to purple)
              CircleLayer(
                circles: _hotspotMarkers,
              ),
              CircleLayer(
                circles: _crimeMarkers,
              ),
              // Route Polylines (Display all alternative routes)
              PolylineLayer(
                polylines: [
                  if (_alternativeRoutes.isNotEmpty)
                    ..._alternativeRoutes.asMap().entries.map((entry) {
                      final index = entry.key;
                      final route = entry.value;
                      // Highlight the selected route, others are less prominent
                      return Polyline(
                        points: route['points'],
                        color: index == _selectedRouteIndex ? Colors.purpleAccent : Colors.blueGrey.withOpacity(0.6), // Purple for selected route, different color for others
                        strokeWidth: index == _selectedRouteIndex ? 5.0 : 3.0, // Thicker for selected route
                      );
                    }).toList(),
                ],
              ),
              // Location Markers (Current, Source, Destination)
              MarkerLayer(
                markers: [
                  if (_currentPosition != null) // Display current location marker
                    Marker(
                      point: latlong.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      width: 40,
                      height: 40,
                      child: Icon(Icons.directions_car, color: Colors.white, size: 30), // Car icon, white
                    ),
                  if (_sourceLocation != null)
                    Marker(
                      point: _sourceLocation!,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.my_location, color: Colors.greenAccent, size: 30), // Source marker icon changed
                    ),
                  if (_destinationLocation != null)
                    Marker(
                      point: _destinationLocation!,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.location_on, color: Colors.purpleAccent, size: 30), // Destination marker (purple)
                    ),
                ],
              ),
            ],
          ),

          // Current Location Button
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 16, // Position below AppBar
            right: 16,
            child: FloatingActionButton(
              onPressed: _getCurrentLocation, // Button calls the function to get and move to current location
              child: Icon(Icons.my_location, color: Colors.purple), // Purple icon
              backgroundColor: Colors.white, // White background
            ),
          ),

          // Bottom Panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87, // Dark background
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_alternativeRoutes.isEmpty) // Pre-navigation state: Search bars
                    Column(
                      children: [
                         TextField(
                          controller: _sourceController,
                          style: TextStyle(color: Colors.white), // White text
                          decoration: InputDecoration(
                            hintText: 'Enter Starting Point',
                            hintStyle: TextStyle(color: Colors.white70), // Lighter hint text
                            prefixIcon: Icon(Icons.my_location, color: Colors.greenAccent), // Source icon
                            filled: true,
                            fillColor: Colors.white12, // Subtle fill color
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (query) => _searchLocation(query, isSource: true),
                        ),
                        SizedBox(height: 16),
                        TextField(
                          controller: _destinationController,
                          style: TextStyle(color: Colors.white), // White text
                          decoration: InputDecoration(
                            hintText: 'Enter Destination',
                            hintStyle: TextStyle(color: Colors.white70), // Lighter hint text
                            prefixIcon: Icon(Icons.location_on, color: Colors.purpleAccent), // Destination icon
                            filled: true,
                            fillColor: Colors.white12, // Subtle fill color
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (query) => _searchLocation(query, isSource: false),
                        ),
                        SizedBox(height: 16),
                         if (isLoading) CircularProgressIndicator(color: Colors.purpleAccent),
                         if (!isLoading && (_sourceLocation != null || _destinationLocation != null) && !result.contains("Model loaded successfully")) // Show message if locations selected but no route yet and not the model success message
                           Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              result, // Displays status messages
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                      ],
                    )
                  else // Post-navigation state: Route details and alternatives
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Selected Route Details
                        if (selectedRoute != null) // Show details of the selected route
                           Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Text(
                                 "${(selectedRoute['duration'] / 60).round()} min (${(selectedRoute['distance'] / 1000).toStringAsFixed(1)} km)",
                                 style: TextStyle(
                                   fontSize: 24,
                                   fontWeight: FontWeight.bold,
                                   color: Colors.white,
                                 ),
                               ),
                               SizedBox(height: 4),
                               Text(
                                 "Route ${_selectedRouteIndex + 1} - Safety Score: ${selectedRoute['safetyScore'].toStringAsFixed(2)}",
                                 style: TextStyle(
                                   fontSize: 16,
                                   color: Colors.purpleAccent, // Highlight safety score
                                 ),
                               ),
                               SizedBox(height: 16),
                                // Safety Score Indicator (Pill shape)
                                Align(
                                  alignment: Alignment.center,
                                  child: Container(
                                     padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                     decoration: BoxDecoration(
                                       color: Colors.purpleAccent,
                                       borderRadius: BorderRadius.circular(20),
                                     ),
                                     child: Text(
                                       "Safety: ${selectedRoute['safetyScore'].toStringAsFixed(2)}", // Display calculated safety score
                                       style: TextStyle(
                                         color: Colors.white,
                                         fontWeight: FontWeight.bold,
                                         fontSize: 18,
                                       ),
                                     ),
                                   ),
                                ),
                                SizedBox(height: 16),
                                // Start and Destination display
                                Row(
                                  children: [
                                    Column(
                                      children: [
                                        Icon(Icons.my_location, color: Colors.greenAccent, size: 20),
                                        SizedBox(height: 4),
                                        Icon(Icons.more_vert, color: Colors.white70, size: 20),
                                        SizedBox(height: 4),
                                        Icon(Icons.location_on, color: Colors.purpleAccent, size: 20),
                                      ],
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                           Text(
                                            _sourceController.text.isNotEmpty ? _sourceController.text : "Starting Point",
                                            style: TextStyle(color: Colors.white, fontSize: 16),
                                            overflow: TextOverflow.ellipsis,
                                           ),
                                           SizedBox(height: 12),
                                           Text(
                                            _destinationController.text.isNotEmpty ? _destinationController.text : "Destination",
                                            style: TextStyle(color: Colors.white, fontSize: 16),
                                            overflow: TextOverflow.ellipsis,
                                           ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                             ],
                           ),
                         SizedBox(height: 16),
                         // Horizontal List of Alternative Routes
                         Container(
                           height: 100, // Give a fixed height for the horizontal list
                           child: ListView.builder(
                             scrollDirection: Axis.horizontal,
                             itemCount: _alternativeRoutes.length,
                             itemBuilder: (context, index) {
                               final route = _alternativeRoutes[index];
                               // Highlight the selected route card
                               final isSelected = index == _selectedRouteIndex;
                               return GestureDetector(
                                 onTap: () => _selectRoute(index), // Select route on tap
                                 child: Card(
                                   color: isSelected ? Colors.purple.withOpacity(0.8) : Colors.black54, // Highlight selected card
                                   shape: RoundedRectangleBorder(
                                     borderRadius: BorderRadius.circular(10),
                                     side: isSelected ? BorderSide(color: Colors.purpleAccent, width: 2) : BorderSide.none, // Add border to selected
                                   ),
                                   child: Container(
                                     width: 180, // Fixed width for each route option card
                                     padding: EdgeInsets.all(12),
                                     child: Column(
                                       mainAxisSize: MainAxisSize.min,
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                         Text(
                                           "Route ${index + 1}",
                                           style: TextStyle(
                                             fontWeight: FontWeight.bold,
                                             fontSize: 16,
                                             color: isSelected ? Colors.white : Colors.white70,
                                           ),
                                         ),
                                         SizedBox(height: 4),
                                         Text(
                                           "${(route['duration'] / 60).round()} min | ${(route['distance'] / 1000).toStringAsFixed(1)} km",
                                           style: TextStyle(
                                             fontSize: 14,
                                             color: isSelected ? Colors.white70 : Colors.white54,
                                           ),
                                         ),
                                         SizedBox(height: 4),
                                          Text(
                                            "Safety: ${route['safetyScore'].toStringAsFixed(2)}",
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.greenAccent, // Safety score color
                                               fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

  @override
  void dispose() {
    _mlService.dispose();
    _mapController.dispose();
    _sourceController.dispose();
    _destinationController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}