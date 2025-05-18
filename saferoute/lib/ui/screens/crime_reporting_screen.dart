import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/colors.dart';

class CrimeReportingScreen extends StatefulWidget {
  const CrimeReportingScreen({Key? key}) : super(key: key);

  @override
  State<CrimeReportingScreen> createState() => _CrimeReportingScreenState();
}

class _CrimeReportingScreenState extends State<CrimeReportingScreen> {
  final _formKey = GlobalKey<FormState>();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  String? _mapboxToken;
  List<Map<String, dynamic>> _searchSuggestions = [];
  bool _isSearching = false;

  // Form data
  String? _selectedCity;
  String? _selectedCrimeType;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  LatLng? _selectedLocation;
  String _locationText = "Select location";

  // UI related
  bool _isFieldFocused = false;
  final _cityFocusNode = FocusNode();
  final _crimeTypeFocusNode = FocusNode();
  int _currentStep = 0;

  // Loading states - separate form submission from map operations
  bool _isLoading = false; // Only for form submission
  bool _isInitializing = true;
  bool _isMapLoading = false; // New variable specifically for map operations

  // Map variables
  LatLng _center = LatLng(31.4900, 74.3000); // Default center
  List<String> _cities = [
    "Lahore",
    "Islamabad",
    "Karachi"
  ]; // Initial cities list
  List<String> _crimeTypes = [
    "Robbery",
    "Theft",
    "Burglary",
    "Fraud",
    "Assault"
  ];

  @override
  void initState() {
    super.initState();
    _initializeScreen();
    _setupFocusListeners();
  }

  void _setupFocusListeners() {
    _cityFocusNode.addListener(() {
      setState(() {
        _isFieldFocused = _cityFocusNode.hasFocus;
      });
    });
    _crimeTypeFocusNode.addListener(() {
      setState(() {
        _isFieldFocused = _crimeTypeFocusNode.hasFocus;
      });
    });
  }

  Future<void> _initializeScreen() async {
    try {
      // Load environment variables
      await _loadEnv();

      // Try to load cities from Firestore
      await _loadCities();

      // Update state when everything is done
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      print("Error initializing screen: $e");
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _loadEnv() async {
    try {
      // Make sure dotenv is loaded
      await dotenv.load();
      _mapboxToken = dotenv.env['MAPBOX_TOKEN'];
      print("Mapbox token loaded: ${_mapboxToken != null}");
    } catch (e) {
      print("Error loading env variables: $e");
    }
  }

  Future<void> _loadCities() async {
    try {
      if (!Firebase.apps.isNotEmpty) {
        print("Firebase not initialized yet");
        return;
      }

      // Get cities from Firestore if available
      final snapshot =
          await FirebaseFirestore.instance.collection('firestore_crime').get();
      final Set<String> cities = {};

      for (var doc in snapshot.docs) {
        if (doc.data().containsKey('city') && doc['city'] != null) {
          cities.add(doc['city'].toString());
        }
      }

      if (cities.isNotEmpty && mounted) {
        setState(() {
          _cities = cities.toList();
        });
      }
    } catch (e) {
      print("Error loading cities: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
          return;
        }
      }

      // Use the map-specific loading state
      setState(() {
        _isMapLoading = true;
      });

      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _center = LatLng(position.latitude, position.longitude);
          _isMapLoading = false;
        });
        _mapController.move(_center, 15.0);
      }
    } catch (e) {
      setState(() {
        _isMapLoading = false;
      });
      print("Error getting location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _getSearchSuggestions(String query) async {
    if (query.isEmpty || _mapboxToken == null || _mapboxToken!.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      // Mapbox Geocoding API endpoint for place suggestions
      final url = Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json?access_token=$_mapboxToken&autocomplete=true&limit=5');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        List<Map<String, dynamic>> suggestions = [];

        for (var feature in features) {
          suggestions.add({
            'name': feature['place_name'] as String,
            'coordinates': LatLng(
              feature['center'][1] as double,
              feature['center'][0] as double,
            ),
          });
        }

        if (mounted) {
          setState(() {
            _searchSuggestions = suggestions;
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      print('Error getting search suggestions: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        Location location = locations.first;
        final newLocation = LatLng(location.latitude, location.longitude);

        setState(() {
          _selectedLocation = newLocation;
        });
        _mapController.move(newLocation, 15.0);

        // Get readable address for the selected location
        _updateLocationText();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location not found: $query')),
      );
    }
  }

  void _selectSuggestion(Map<String, dynamic> suggestion) {
    _searchController.text = suggestion['name'];
    final location = suggestion['coordinates'] as LatLng;

    setState(() {
      _selectedLocation = location;
      _searchSuggestions = [];
    });

    _mapController.move(location, 15.0);
  }

  Future<void> _updateLocationText() async {
    if (_selectedLocation == null) return;

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          _selectedLocation!.latitude, _selectedLocation!.longitude);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String address = '';

        if (place.street != null && place.street!.isNotEmpty) {
          address += place.street!;
        }

        if (place.locality != null && place.locality!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.locality!;
        }

        if (place.subAdministrativeArea != null &&
            place.subAdministrativeArea!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.subAdministrativeArea!;
        }

        if (address.isEmpty) {
          address =
              '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}';
        }

        setState(() {
          _locationText = address;
        });
      } else {
        setState(() {
          _locationText =
              '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}';
        });
      }
    } catch (e) {
      setState(() {
        _locationText =
            '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}';
      });
    }
  }

  void _showLocationPicker() async {
    // Don't change the main loading state
    // We'll use the map-specific loading state inside the modal

    // Check if we have a valid Mapbox token
    if (_mapboxToken == null || _mapboxToken!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Map service not available. Please try again later.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Get location after the modal is shown
            Future.delayed(const Duration(milliseconds: 300), () {
              if (context.mounted) {
                // Set loading state within the modal's context
                setModalState(() {
                  _isMapLoading = true;
                });

                // Get current location
                _getCurrentLocation().then((_) {
                  if (context.mounted) {
                    setModalState(() {
                      // _isMapLoading is already updated in _getCurrentLocation
                    });
                  }
                });
              }
            });

            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    spreadRadius: 0,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Location',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              setModalState(() {
                                _searchSuggestions = [];
                              });
                              Navigator.pop(context);
                            }),
                      ],
                    ),
                  ),

                  // Search bar with suggestions
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search for a location...',
                              hintStyle: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 16,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: AppColors.primary,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 20,
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isSearching)
                                    Container(
                                      width: 24,
                                      height: 24,
                                      padding: const EdgeInsets.all(4.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: Colors.grey[400],
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setModalState(() {
                                        _searchSuggestions = [];
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            onChanged: (value) {
                              _getSearchSuggestions(value).then((_) {
                                setModalState(() {});
                              });
                            },
                            onSubmitted: (value) {
                              if (_searchSuggestions.isNotEmpty) {
                                _selectSuggestion(_searchSuggestions[0]);
                              } else {
                                _searchLocation(value);
                              }
                              setModalState(() {
                                _searchSuggestions = [];
                              });
                            },
                          ),
                        ),

                        // Suggestions list
                        if (_searchSuggestions.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            margin: const EdgeInsets.only(top: 8),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _searchSuggestions.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: Colors.grey[200],
                              ),
                              itemBuilder: (context, index) {
                                return ListTile(
                                  title: Text(
                                    _searchSuggestions[index]['name'],
                                    style: const TextStyle(
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  leading: Icon(
                                    Icons.location_on,
                                    color: AppColors.primary,
                                  ),
                                  dense: true,
                                  onTap: () {
                                    _selectSuggestion(
                                        _searchSuggestions[index]);
                                    setModalState(() {
                                      _searchSuggestions = [];
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Map
                  Expanded(
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _center,
                            initialZoom: 15.0,
                            onTap: (tapPosition, point) {
                              setModalState(() {
                                _selectedLocation = point;
                              });
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
                              additionalOptions: {
                                'accessToken': _mapboxToken ?? '',
                              },
                            ),
                            MarkerLayer(
                              markers: [
                                if (_selectedLocation != null)
                                  Marker(
                                    point: _selectedLocation!,
                                    width: 40,
                                    height: 40,
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 20,
                                          width: 20,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.2),
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          width: 2,
                                          height: 10,
                                          color: AppColors.primary,
                                        ),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        // My location button
                        Positioned(
                          right: 16,
                          bottom: 100,
                          child: FloatingActionButton(
                            heroTag: "locationBtn",
                            mini: true,
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            elevation: 4,
                            child: const Icon(Icons.my_location),
                            onPressed: () {
                              // Use getCurrentLocation but update the modal state
                              setModalState(() {
                                _isMapLoading = true;
                              });

                              _getCurrentLocation().then((_) {
                                if (context.mounted) {
                                  setModalState(() {
                                    // _isMapLoading is already set to false in _getCurrentLocation
                                  });
                                }
                              });
                            },
                          ),
                        ),

                        // Loading indicator (only inside the map modal)
                        if (_isMapLoading)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.3),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Confirm button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          spreadRadius: 0,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _selectedLocation == null
                          ? null
                          : () {
                              _updateLocationText();
                              Navigator.pop(context);
                            },
                      child: const Text(
                        'CONFIRM LOCATION',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _submitReport() async {
    if (!Firebase.apps.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Firebase is not initialized. Please try again later.')),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (_selectedLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a location on the map')),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final dateFormatted = DateFormat('yyyy-MM-dd').format(_selectedDate);
        final timeFormatted =
            '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

        // Save to Firestore without timestamp field
        await FirebaseFirestore.instance.collection('firestore_crime').add({
          'city': _selectedCity,
          'crime_type': _selectedCrimeType,
          'date': dateFormatted,
          'time': timeFormatted,
          'latitude': _selectedLocation!.latitude,
          'longitude': _selectedLocation!.longitude,
        });

        setState(() {
          _isLoading = false;
        });

        // Show success message with animation
        _showSuccessDialog();
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting report: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    color: Colors.green[700],
                    size: 50,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Thank You!",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Your crime report has been submitted successfully.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop(); // Return to previous screen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    "OK",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Report Crime"),
          backgroundColor: AppColors.primary,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Loading..."),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Report Crime",
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
      ),
      body: _isLoading ? _buildLoadingScreen() : _buildStepperForm(),
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              "Submitting your report...",
              style: TextStyle(
                fontSize: 18,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperForm() {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Progress Indicator
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildProgressIndicator(0, "Details"),
                      _buildProgressConnector(0),
                      _buildProgressIndicator(1, "Location"),
                      _buildProgressConnector(1),
                      _buildProgressIndicator(2, "Submit"),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Form Content
          Expanded(
            child: Stepper(
              type: StepperType.horizontal,
              currentStep: _currentStep,
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: details.onStepContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            _currentStep == 2 ? 'SUBMIT' : 'CONTINUE',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (_currentStep > 0) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: details.onStepCancel,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text('BACK'),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
              onStepContinue: () {
                if (_currentStep < 2) {
                  // Validate current step
                  bool canContinue = true;

                  if (_currentStep == 0) {
                    canContinue =
                        _selectedCity != null && _selectedCrimeType != null;
                    if (!canContinue) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please select city and crime type')),
                      );
                    }
                  } else if (_currentStep == 1) {
                    canContinue = _selectedLocation != null;
                    if (!canContinue) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please select a location')),
                      );
                    }
                  }

                  if (canContinue) {
                    setState(() {
                      _currentStep += 1;
                    });
                  }
                } else {
                  _submitReport();
                }
              },
              onStepCancel: () {
                if (_currentStep > 0) {
                  setState(() {
                    _currentStep -= 1;
                  });
                }
              },
              steps: [
                Step(
                  title: const Text('Crime Details'),
                  content: _buildCrimeDetailsStep(),
                  isActive: _currentStep >= 0,
                  state:
                      _currentStep > 0 ? StepState.complete : StepState.indexed,
                ),
                Step(
                  title: const Text('Location'),
                  content: _buildLocationStep(),
                  isActive: _currentStep >= 1,
                  state:
                      _currentStep > 1 ? StepState.complete : StepState.indexed,
                ),
                Step(
                  title: const Text('Confirm'),
                  content: _buildConfirmStep(),
                  isActive: _currentStep >= 2,
                  state:
                      _currentStep == 2 ? StepState.indexed : StepState.indexed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(int step, String label) {
    bool isActive = _currentStep >= step;
    bool isCurrent = _currentStep == step;

    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
            shape: BoxShape.circle,
            border:
                isCurrent ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Center(
            child: isActive
                ? Icon(
                    step < _currentStep ? Icons.check : Icons.circle,
                    color: AppColors.primary,
                    size: 18,
                  )
                : Text(
                    "${step + 1}",
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressConnector(int step) {
    bool isActive = _currentStep > step;

    return Container(
      width: 60,
      height: 2,
      color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
    );
  }

  Widget _buildCrimeDetailsStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // City dropdown
          _buildDropdownField(
            label: "City",
            hint: "Select a city",
            value: _selectedCity,
            items: _cities.map((city) {
              return DropdownMenuItem<String>(
                value: city,
                child: Text(city),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedCity = value as String?;
              });
            },
            focusNode: _cityFocusNode,
          ),
          const SizedBox(height: 20),

          // Crime type dropdown
          _buildDropdownField(
            label: "Crime Type",
            hint: "Select crime type",
            value: _selectedCrimeType,
            items: _crimeTypes.map((type) {
              return DropdownMenuItem<String>(
                value: type,
                child: Text(type),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedCrimeType = value as String?;
              });
            },
            focusNode: _crimeTypeFocusNode,
          ),
          const SizedBox(height: 20),

          // Date picker
          _buildDateField(),
          const SizedBox(height: 20),

          // Time picker
          _buildTimeField(),
        ],
      ),
    );
  }

  Widget _buildLocationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Location field with map icon
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Location",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _showLocationPicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedLocation != null
                          ? AppColors.primary
                          : Colors.grey.shade300,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedLocation == null
                              ? "Select a location on the map"
                              : _locationText,
                          style: TextStyle(
                            color: _selectedLocation == null
                                ? Colors.grey[600]
                                : Colors.black,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.map,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_selectedLocation != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.blue.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Selected Location:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _locationText,
                  style: const TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 4),
                Text(
                  "Coordinates: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildConfirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCard(
          "Crime Details",
          [
            ["City", _selectedCity ?? "Not selected"],
            ["Crime Type", _selectedCrimeType ?? "Not selected"],
            ["Date", DateFormat('yyyy-MM-dd').format(_selectedDate)],
            [
              "Time",
              '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}'
            ],
          ],
          Icons.description,
        ),
        const SizedBox(height: 16),
        _buildSummaryCard(
          "Location",
          [
            ["Address", _locationText],
            [
              "Coordinates",
              "${_selectedLocation?.latitude.toStringAsFixed(6) ?? ''}, ${_selectedLocation?.longitude.toStringAsFixed(6) ?? ''}"
            ],
          ],
          Icons.location_on,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.yellow.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.yellow.shade200),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.amber[700],
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Please review your report details carefully before submitting.",
                  style: TextStyle(
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
      String title, List<List<String>> details, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: details.map((detail) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          "${detail[0]}:",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          detail[1],
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String hint,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required void Function(Object?) onChanged,
    required FocusNode focusNode,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            value: value,
            focusNode: focusNode,
            items: items,
            onChanged: onChanged,
            icon: Icon(
              Icons.arrow_drop_down,
              color: AppColors.primary,
            ),
            isExpanded: true,
            dropdownColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Date",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _selectDate(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade300,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('yyyy-MM-dd').format(_selectedDate),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.calendar_today,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Time",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _selectTime(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade300,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.access_time,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    _cityFocusNode.dispose();
    _crimeTypeFocusNode.dispose();
    super.dispose();
  }
}
