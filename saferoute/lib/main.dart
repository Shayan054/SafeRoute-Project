import 'package:flutter/material.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/home_dashboard.dart';
// You can import other screens later like HomeScreen, etc.

void main() {
  runApp(const SafeRouteApp());
}

class SafeRouteApp extends StatelessWidget {
  const SafeRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeRoute',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF686DF1)),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const MainScreen(),
        '/home': (context) => const HomeDashboard(),
        // Replace this with your actual HomePage widget later
      },
    );
  }
}
