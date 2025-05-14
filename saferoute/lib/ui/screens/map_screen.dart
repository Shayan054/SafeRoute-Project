import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadModel();
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
    if (!isModelLoaded) {
      setState(() {
        result = "Model is still loading. Please wait.";
      });
      return;
    }

    setState(() {
      isLoading = true;
      result = "Predicting...";
    });

    try {
      // Example input data with 11 features
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
    return Scaffold(
      appBar: AppBar(title: Text("SafeRoute Prediction")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
    );
  }

  @override
  void dispose() {
    _mlService.dispose();
    super.dispose();
  }
}
