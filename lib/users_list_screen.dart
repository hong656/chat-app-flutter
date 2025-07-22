// lib/users_list_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Import your User model
import 'models/user_model.dart';

// We need a StatefulWidget to manage state like loading, errors, and the user list.
class UsersListScreen extends StatefulWidget {
  const UsersListScreen({super.key});

  @override
  State<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  // State variables equivalent to Nuxt's ref()
  bool _isLoading = true;
  String? _error;
  List<User> _users = [];
  String? _token;

  // This is the equivalent of Nuxt's onMounted hook.
  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  // --- Logic to fetch the list of users ---
  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. Get the token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');

      if (_token == null) {
        throw Exception('Authentication token not found. Please log in again.');
      }

      // IMPORTANT: Use your actual API endpoint. 
      // For Android emulator, use 10.0.2.2 to access localhost.
      // For web/desktop, '127.0.0.1' is fine.
      final response = await http.get(Uri.parse('https://api-test-chat.d.aditidemo.asia/api/get'));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        // Map the JSON list to a List<User> using our model
        setState(() {
          _users = data.map((json) => User.fromJson(json)).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load users. Status code: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // --- Logic to create a new chat ---
  Future<void> _createChat(int otherUserId) async {
    if (_token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Not authenticated.')),
      );
      return;
    }

    // Show a loading dialog to the user
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final chatData = {
        'is_group': false,
        'title': null,
        'members': [otherUserId],
      };

      final response = await http.post(
        Uri.parse('https://api-test-chat.d.aditidemo.asia/api/chat'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode(chatData),
      );

      // Dismiss the loading dialog
      if (mounted) Navigator.of(context).pop();

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Success! You might want to navigate to the chat screen here.
        // For now, we just show a confirmation message.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat created successfully!'), backgroundColor: Colors.green),
        );
      } else {
        // Handle server-side errors
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to create chat.');
      }
    } catch (e) {
      // Dismiss the loading dialog if it's still visible
      if (mounted) Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  // --- Build the UI based on the current state ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          // Add a refresh button to re-fetch users
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUsers,
          ),
        ],
      ),
      // This is the equivalent of the v-if/v-else-if/v-else block
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $_error', style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchUsers,
                child: const Text('Retry'),
              )
            ],
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return const Center(child: Text('No users found.'));
    }

    // This is the equivalent of the v-for loop rendering the table
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(user.name.isNotEmpty ? user.name[0] : 'U'),
            ),
            title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(user.email),
            trailing: TextButton(
              onPressed: () => _createChat(user.userId),
              child: const Text('Chat'),
            ),
          ),
        );
      },
    );
  }
}