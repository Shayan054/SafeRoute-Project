import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/firestore_service.dart';

class CrimeStatisticsPage extends StatefulWidget {
  const CrimeStatisticsPage({Key? key}) : super(key: key);

  @override
  State<CrimeStatisticsPage> createState() => _CrimeStatisticsPageState();
}

class _CrimeStatisticsPageState extends State<CrimeStatisticsPage> {
  String? selectedCity;
  Map<String, int> crimeStats = {};
  List<Map<String, dynamic>> crimeLocations = [];
  bool isLoading = false;
  List<String> cities = [];

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    final cityList = await FirestoreService().getAllCities();
    setState(() {
      cities = cityList;
    });
  }

  Future<void> _fetchData(String city) async {
    setState(() {
      isLoading = true;
    });
    final stats = await FirestoreService().getCrimeStatsByCity(city);
    final locations = await FirestoreService().getCrimeLocationsByCity(city);
    setState(() {
      crimeStats = stats;
      crimeLocations = locations;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        title: const Text('Crime Statistics'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedCity,
                  hint: const Text('Select City'),
                  items: cities.map((city) {
                    return DropdownMenuItem(
                      value: city,
                      child: Text(city),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    selectedCity = value;
                    await _fetchData(value!);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (crimeStats.isNotEmpty)
              Expanded(
                child: ListView(
                  children: [
                    const Text("Crime Distribution (Pie Chart)",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    SizedBox(height: 200, child: _buildPieChart()),
                    const SizedBox(height: 24),
                    const Text("Crime Trends (Bar Chart)",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    SizedBox(height: 200, child: _buildBarChart()),
                    const SizedBox(height: 24),
                    const Text("Crime Density (Heatmap)",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 300,
                      child: _buildHeatmap(),
                    ),
                  ],
                ),
              )
            else if (selectedCity != null)
              const Text("No data available for selected city."),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    final total = crimeStats.values.fold(0, (sum, val) => sum + val);
    final colors = [Colors.red, Colors.blue, Colors.green, Colors.orange];

    return PieChart(
      PieChartData(
        sections: crimeStats.entries.toList().asMap().entries.map((entry) {
          final index = entry.key;
          final type = entry.value.key;
          final count = entry.value.value;
          final percentage = ((count / total) * 100).toStringAsFixed(1);

          return PieChartSectionData(
            color: colors[index % colors.length],
            value: count.toDouble(),
            title: "$type\n$percentage%",
            radius: 60,
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        barGroups: crimeStats.entries.toList().asMap().entries.map((entry) {
          final index = entry.key;
          final type = entry.value.key;
          final count = entry.value.value;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                color: Colors.blueAccent,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            showingTooltipIndicators: [0],
          );
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final index = value.toInt();
                final keys = crimeStats.keys.toList();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    keys[index],
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value == value.floor()) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text('');
              },
              interval: 1,
              reservedSize: 40,
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true),
      ),
    );
  }

  Widget _buildHeatmap() {
    // Define city coordinates
    final cityCoordinates = {
      'Lahore': LatLng(31.5204, 74.3587),
      'Islamabad': LatLng(33.6844, 73.0479),
      'Karachi': LatLng(24.8607, 67.0011),
    };

    // Use the selected city's coordinates, default to Lahore if not found
    final center = cityCoordinates[selectedCity] ?? LatLng(31.5204, 74.3587);

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 11,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: ['a', 'b', 'c'],
        ),
        CircleLayer(
          circles: crimeLocations.map((location) {
            return CircleMarker(
              point: LatLng(location['lat'], location['lng']),
              radius: 10,
              color: Colors.red.withOpacity(0.5),
              useRadiusInMeter: false,
            );
          }).toList(),
        ),
      ],
    );
  }
}
