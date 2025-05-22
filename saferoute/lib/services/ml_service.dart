import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class MLServiceException implements Exception {
  final String message;
  MLServiceException(this.message);

  @override
  String toString() => 'MLServiceException: $message';
}

class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance; //ye return krta eisting object
  MLService._internal();

  Interpreter? _interpreter;
  static const int expectedInputSize = 11;
  bool _isModelLoaded = false;

  bool get isModelLoaded => _isModelLoaded;

  Future<void> loadModel() async {
    if (_isModelLoaded) return;

    try {
      _interpreter = await Interpreter.fromAsset('assets/safe_model_updated.tflite');
      _isModelLoaded = true;
    } catch (e) {
      _isModelLoaded = false;
      throw MLServiceException('Failed to load model: $e');
    }
  }

  Future<double> predictSafetyScore(List<double> inputData) async {
    if (!_isModelLoaded) {
      throw MLServiceException('Model not loaded. Call loadModel() first.');
    }

    if (inputData.length != expectedInputSize) {
      throw MLServiceException('Expected $expectedInputSize features, got ${inputData.length}.');
    }

    try {
      final input = Float32List.fromList(inputData).reshape([1, expectedInputSize]);
      final output = List.filled(1 * 1, 0.0).reshape([1, 1]);
      _interpreter!.run(input, output);
      return output[0][0];
    } catch (e) {
      throw MLServiceException('Prediction failed: $e');
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
  }
}
