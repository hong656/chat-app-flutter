import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart'; // Import shimmer
import 'chat_screen.dart';

import 'models/chat_model.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  // State variables
  late Future<List<Chat>> _chatsFuture;

  @override
  void initState() {
    super.initState();
    _chatsFuture = _fetchChats();
  }

  Future<List<Chat>> _fetchChats() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      throw Exception('Authentication Token not found. Please log in.');
    }

    // Use your API endpoint
    final response = await http.get(
      Uri.parse('https://dev.api.chat.d.aditidemo.asia/api/chat'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> body = jsonDecode(response.body);
      if (body['success'] == true) {
        final List<dynamic> data = body['data'];
        return data.map((json) => Chat.fromJson(json)).toList();
      } else {
        throw Exception('API returned success: false');
      }
    } else {
      // Handle specific errors like 401 Unauthorized
      if (response.statusCode == 401) {
        throw Exception('Unauthorized (401). Your session may have expired.');
      }
      throw Exception('Failed to load chats. Status code: ${response.statusCode}');
    }
  }

  // --- Helper Functions (like in Nuxt) ---
  String _getChatTitle(Chat chat) {
    if (chat.isGroup) {
      return chat.title;
    } else {
      // Find the member who is not you
      final otherMember = chat.members.firstWhere((m) => !m.isYou, orElse: () => chat.members.first);
      return otherMember.name;
    }
  }

  String _getInitials(String name) {
    return name.isNotEmpty
        ? name.trim().split(' ').map((l) => l[0]).take(2).join().toUpperCase()
        : '';
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) return 'now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24) return '${difference.inHours}h';
    if (difference.inDays < 7) return '${difference.inDays}d';
    return '${time.day}/${time.month}/${time.year}';
  }

  void _refreshChats() {
    setState(() {
      _chatsFuture = _fetchChats();
    });
  }

  // --- UI Building ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshChats,
          ),
        ],
      ),
      // FutureBuilder handles loading/error/data states for a Future
      body: FutureBuilder<List<Chat>>(
        future: _chatsFuture,
        builder: (context, snapshot) {
          // 1. Loading State
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildShimmerList();
          }

          // 2. Error State
          if (snapshot.hasError) {
            return _buildErrorWidget(snapshot.error);
          }

          // 3. Data State
          final chats = snapshot.data!;
          if (chats.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              return _buildChatListItem(chat);
            },
          );
        },
      ),
    );
  }

  // --- UI Helper Widgets ---

  // Corresponds to the v-if="pending" block
  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        itemCount: 5,
        itemBuilder: (context, index) => const Card(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(radius: 30),
            title: SizedBox(height: 16, child: ColoredBox(color: Colors.white)),
            subtitle: SizedBox(height: 12, child: ColoredBox(color: Colors.white)),
          ),
        ),
      ),
    );
  }

  // Corresponds to the v-if="error" block
  Widget _buildErrorWidget(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 16),
            Text(
              'Error loading chats',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString().replaceAll('Exception: ', ''),
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshChats,
              child: const Text('Try Again'),
            )
          ],
        ),
      ),
    );
  }

  // Corresponds to the v-if="chats.length === 0" block
  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.message_outlined, size: 60, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No conversations',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4),
          Text(
            'Start a new conversation to get started.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Corresponds to the v-for="chat in chats" block
  Widget _buildChatListItem(Chat chat) {
    final title = _getChatTitle(chat);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                chatId: chat.chatId,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      _getInitials(title),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 20),
                    ),
                  ),
                  if (!chat.isGroup)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    )
                ],
              ),
              const SizedBox(width: 12),
              // Chat Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.latestMessage != null)
                          Text(
                            _formatTime(chat.latestMessage!.createdAt),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (chat.latestMessage != null)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${chat.latestMessage!.sender.isYou ? "You" : chat.latestMessage!.sender.name}: ',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            TextSpan(
                              text: chat.latestMessage!.text,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      const Text(
                        'No messages yet',
                        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Arrow Indicator
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}