import 'package:flutter/material.dart';
import '../../services/ml_service.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MLService _mlService = MLService();
  String result = "Prediction not made";
  bool isLoading = false;
  bool isModelLoaded = false;  // Flag to track if the model is loaded

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  // Load the model when the screen is initialized
  Future<void> _loadModel() async {
    await _mlService.loadModel();
    setState(() {
      isModelLoaded = true;  // Model has finished loading
      result = "Model loaded successfully";
    });
  }

  // Run the prediction when the button is pressed
  void _testPrediction() async {
    if (!isModelLoaded) {
      setState(() {
        result = "Model is still loading. Please wait.";
      });
      return;
    }

    setState(() {
      isLoading = true;
      result = "Predicting...";  // Display loading message
    });

    // Example input data [start_lat, start_lng, end_lat, end_lng, time, day, count, severity, length, ...]
    List<double> input = [31.5204, 74.3587, 31.5400, 74.3700, 2, 5, 14, 6.2, 3.4, 1];

    double score = await _mlService.predictSafetyScore(input);

    setState(() {
      isLoading = false;
      if (score == -1.0) {
        result = "Model not loaded. Please try again.";
      } else if (score == -2.0) {
        result = "Prediction failed.";
      } else {
        result = "Predicted Safety Score: ${score.toStringAsFixed(2)}";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("SafeRoute Prediction")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Display loading spinner while prediction is in progress
            if (isLoading) CircularProgressIndicator(),

            // Display the prediction result
            if (!isLoading) Text(result, style: TextStyle(fontSize: 18)),

            SizedBox(height: 20),

            // Button to trigger prediction
            ElevatedButton(
              onPressed: _testPrediction,
              child: Text("Run ML Prediction"),
            )
          ],
        ),
      ),
    );
  }
}
