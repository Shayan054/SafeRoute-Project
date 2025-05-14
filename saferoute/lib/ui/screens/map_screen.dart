import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:math';
import '../../services/ml_service.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MLService _mlService = MLService();
  String result = "Loading model...";
  bool isLoading = false;
  bool isModelLoaded = false;
  bool isEnvLoaded = false;
  final MapController _mapController = MapController();
  LatLng _center = LatLng(31.4900, 74.3000); // Default to Lahore coordinates
  List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await _loadEnv();
      await _loadModel();
    } catch (e) {
      setState(() {
        result = "Initialization failed: ${e.toString()}";
      });
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

  Future<void> _testPrediction() async {
    if (!isModelLoaded || !isEnvLoaded) {
      setState(() {
        result = "System is still initializing. Please wait.";
      });
      return;
    }

    setState(() {
      isLoading = true;
      result = "Predicting...";
    });

    try {
      List<double> input = [
        31.4900, // start_lat
        74.3000, // start_lng
        31.5000, // end_lat
        74.3200, // end_lng
        0.0,     // time_of_day = Morning
        1.0,     // day_of_week = Tuesday
        0.0,     // city = Lahore
        25.0,     // crime_count_nearby
        2.0,     // avg_crime_severity
        4.0,     // path_length_km
        1.0      // path_id
      ];

      double score = await _mlService.predictSafetyScore(input);

      setState(() {
        isLoading = false;
        result = "Predicted Safety Score: ${score.toStringAsFixed(2)}";
        _routePoints = [
          LatLng(input[0], input[1]), // Start point
          LatLng(input[2], input[3]), // End point
        ];
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        result = "Prediction failed: ${e.toString()}";
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
      appBar: AppBar(title: Text("SafeRoute Map")),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 13.0,
                onTap: (tapPosition, point) {
                  // Handle map tap if needed
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
                  additionalOptions: {
                    'accessToken': mapboxToken,
                  },
                ),
                PolylineLayer(
                  polylines: [
                    if (_routePoints.length >= 2)
                      Polyline(
                        points: _routePoints,
                        color: Colors.blue,
                        strokeWidth: 3.0,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (_routePoints.isNotEmpty)
                      Marker(
                        point: _routePoints.first,
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_on, color: Colors.green),
                      ),
                    if (_routePoints.length >= 2)
                      Marker(
                        point: _routePoints.last,
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_on, color: Colors.red),
                      ),
                  ],
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
                      Text("Processing prediction...", style: TextStyle(fontSize: 16)),
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

                SizedBox(height: 20),

                ElevatedButton(
                  onPressed: isLoading ? null : _testPrediction,
                  child: Text(isLoading ? "Processing..." : "Run ML Prediction"),
                )
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
