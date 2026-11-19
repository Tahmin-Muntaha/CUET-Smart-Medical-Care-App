import 'package:flutter/material.dart'; // Flutter UI widgets
import 'package:firebase_core/firebase_core.dart'; // Firebase setup
import 'package:firebase_app_check/firebase_app_check.dart'; // Protects your Firebase from fake apps

import 'firebase_options.dart'; // Auto-generated Firebase settings
import 'home_page.dart'; // Contains LandingPage (the first screen)
import 'login_page.dart'; // The login screen

// The app starts here; async because we wait for Firebase to start
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Get Flutter ready before using Firebase

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Use the settings for this device (Android/iOS/web)
  );

  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug, // Debug mode for Android (change to Play Integrity before release)
  );

  runApp(const SmartMedicalStoreApp()); // Start the app
}

// The root of the app; it never changes itself, so it is Stateless
class SmartMedicalStoreApp extends StatelessWidget {
  const SmartMedicalStoreApp({super.key}); // Constructor (key is optional)

  @override
  Widget build(BuildContext context) {
    // build() draws the app
    return MaterialApp(
      // MaterialApp = app-wide settings
      debugShowCheckedModeBanner: false, // Hide the red "DEBUG" banner
      title: 'CUET Medical Care', // App name

      theme: ThemeData(
        // App-wide look
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003D9B), // Make all colors from this blue
        ),
        useMaterial3: true, // Use the newer Material 3 design
      ),

      home: const LandingPage(), // First screen shown when the app opens

      routes: {
        // Named pages (used with Navigator.pushNamed)
        '/login': (context) => const LoginPage(), // "/login" opens the login page
      },
    );
  }
}
