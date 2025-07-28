import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'users_list_screen.dart';
import 'chat_list_screen.dart';

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
        '/users_list': (context) => const UsersListScreen(),
        '/chat_list': (context) => const ChatListScreen(),
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
        title: const Text('Main Menu'), // Updated title
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                // Navigate using the named route
                Navigator.pushNamed(context, '/users_list');
              },
              child: const Text('Go to Users List'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Navigate using the named route
                Navigator.pushNamed(context, '/chat_list');
              },
              child: const Text('Go to Chat List'),
            ),
          ],
        ),
      ),
    );
  }
}
