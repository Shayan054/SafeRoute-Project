import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/app_provider.dart';

class SplashScreen extends StatefulWidget {
  final bool isLoggedIn;

  const SplashScreen({Key? key, required this.isLoggedIn}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    // Initialize providers
    await appProvider.initialize();

    // Check authentication state
    if (widget.isLoggedIn) {
      // Initialize user data if logged in
      await userProvider.initializeUser();
    }

    // Delay for showing splash screen (minimum 2 seconds)
    await Future.delayed(Duration(seconds: 2));

    // Navigate to the appropriate screen
    if (mounted) {
      if (appProvider.isFirstLaunch) {
        // First time launching the app
        Navigator.pushReplacementNamed(context, '/');
        // Mark first launch as complete
        appProvider.completeFirstLaunch();
      } else if (widget.isLoggedIn && userProvider.isLoggedIn) {
        // User is logged in, go to home
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // User is not logged in, go to login
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              height: 150,
              width: 150,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/gps.png',
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 40),

            // App Name
            Text(
              'SafeRoute',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),

            const SizedBox(height: 8),

            // Tagline
            Text(
              'Navigate with confidence',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),

            const SizedBox(height: 60),

            // Loading indicator
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          ],
        ),
      ),
    );
  }
}
