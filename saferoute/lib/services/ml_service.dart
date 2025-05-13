import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class MLServiceException implements Exception {
  final String message;
  MLServiceException(this.message);
  
  @override
  String toString() => 'MLServiceException: $message';
}

class MLService {
  Interpreter? _interpreter;
  static const int expectedInputSize = 10;
  
  // Constants for score normalization
  static const double minScore = 1.0;
  static const double maxScore = 10.0;
  static const double minRawScore = 0.0;  // Adjust this based on your model's minimum output
  static const double maxRawScore = 25.0; // Adjust this based on your model's maximum output

  Future<void> loadModel() async {
    try {
      print("⏳ Starting model loading process...");
      
      // Check if the asset exists
      try {
        await rootBundle.load('assets/safety_model.tflite');
        print("✅ Model file found in assets");
      } catch (e) {
        throw MLServiceException('Model file not found in assets: $e');
      }

      // Platform-specific checks
      if (Platform.isAndroid) {
        print("📱 Running on Android");
      } else if (Platform.isIOS) {
        print("📱 Running on iOS");
      } else {
        print("⚠️ Running on unsupported platform: ${Platform.operatingSystem}");
      }

      print("⏳ Loading model from asset...");
      _interpreter = await Interpreter.fromAsset('assets/safety_model.tflite');
      
      if (_interpreter == null) {
        throw MLServiceException('Interpreter is null after loading');
      }

      print("✅ Model loaded successfully");
      print("📐 Input shape: ${_interpreter!.getInputTensor(0).shape}");
      print("📐 Output shape: ${_interpreter!.getOutputTensor(0).shape}");
      
      // Verify model input/output
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      
      if (inputShape[1] != expectedInputSize) {
        throw MLServiceException('Model expects ${inputShape[1]} features, but code expects $expectedInputSize');
      }
      
      print("✅ Model input/output shapes verified");
    } catch (e) {
      print("❌ Detailed error during model loading: $e");
      throw MLServiceException('Failed to load model: $e');
    }
  }

  Future<double> predictSafetyScore(List<double> inputData) async {
    if (_interpreter == null) {
      throw MLServiceException('Model not loaded. Call loadModel() first.');
    }

    if (inputData.length != expectedInputSize) {
      throw MLServiceException('Invalid input size. Expected $expectedInputSize features, got ${inputData.length}');
    }

    try {
      final input = Float32List.fromList(inputData).reshape([1, expectedInputSize]);
      final output = List.filled(1 * 1, 0.0).reshape([1, 1]);

      print("▶️ Running model on input: $inputData");
      _interpreter!.run(input, output);

      print("✅ Raw output: $output");
      
      // Get the raw score
      double rawScore = output[0][0];
      
      // Normalize the score to 1-10 range
      double normalizedScore = _normalizeScore(rawScore);
      
      // Round to 1 decimal place for cleaner output
      normalizedScore = (normalizedScore * 10).round() / 10;
      
      print("📊 Normalized safety score (1-10): $normalizedScore");
      return normalizedScore;
    } catch (e) {
      print("❌ Detailed prediction error: $e");
      throw MLServiceException('Prediction failed: $e');
    }
  }

  double _normalizeScore(double rawScore) {
    // Clamp the raw score to the expected range
    rawScore = rawScore.clamp(minRawScore, maxRawScore);
    
    // Normalize to 1-10 range using linear scaling
    double normalized = minScore + (maxScore - minScore) * 
        ((rawScore - minRawScore) / (maxRawScore - minRawScore));
    
    // Ensure the score is within bounds
    return normalized.clamp(minScore, maxScore);
  }

  void dispose() {
    print("🧹 Disposing MLService...");
    _interpreter?.close();
    _interpreter = null;
    print("✅ MLService disposed");
  }
}
