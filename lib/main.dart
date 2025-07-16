import 'package:flutter/material.dart';

import 'chat_screen.dart'; // Import your first chat screen
import 'chat_screen_2.dart'; // Import your second chat screen
import 'login_screen.dart'; // Import your login screen

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat Demo App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/': (context) => const HomePage(),
        '/chat1': (context) => const ChatScreen(),
        '/chat2': (context) => const ChatScreen2(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a Chat Screen'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ChatScreen()), // Nav to ChatScreen
                );
              },
              child: const Text('Go to Chat Screen 1'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ChatScreen2()), // Nav to ChatScreen2
                );
              },
              child: const Text('Go to Chat Screen 2'),
            ),
          ],
        ),
      ),
    );
  }
}