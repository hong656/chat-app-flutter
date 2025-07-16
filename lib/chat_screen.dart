import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:simple_flutter_reverb/simple_flutter_reverb.dart';
import 'package:simple_flutter_reverb/simple_flutter_reverb_options.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class Message {
  final String sender;
  final String text;
  final DateTime time;
  final bool isMe;

  Message({required this.sender, required this.text, required this.time, required this.isMe});

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      sender: json['sender']['name'],
      text: json['text'],
      time: DateTime.parse(json['created_at']),
      isMe: json['is_you'],
    );
  }
}

class _ChatScreenState extends State<ChatScreen> {
  // --- STEP 1: CREATE A SCROLL CONTROLLER ---
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final String getApiUrl = 'https://api-test-chat.d.aditidemo.asia/api/messages/1';
  final String postApiUrl = 'https://api-test-chat.d.aditidemo.asia/api/messages';
  final String authToken = '1|w71aiWYbS2lCpSSA3cAphLWgHrXrFf9DYcS7CvUpa7ff69db';
  final int chatId = 1;
  late SimpleFlutterReverb reverb;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupReverb();
  }

  // --- HELPER FUNCTION TO SCROLL TO THE BOTTOM ---
  void _scrollToBottom() {
    // We use addPostFrameCallback to ensure the scroll happens after the UI has been updated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadMessages() async {
    try {
      final response = await http.get(
        Uri.parse(getApiUrl),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          final List<dynamic> data = jsonResponse['data'];
          setState(() {
            _messages = data.map((json) => Message.fromJson(json)).toList();
          });
          // --- STEP 3: SCROLL AFTER LOADING INITIAL MESSAGES ---
          _scrollToBottom();
        } else {
          print('API returned success: false');
        }
      } else {
        print('Failed to load messages. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(postApiUrl),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chat_id': chatId,
          'message_type': 'text',
          'text': text,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('Message sent successfully!');
        _controller.clear();
      } else {
        print('Failed to send message. Status code: ${response.statusCode}');
        print('Response body: ${response.body}');
      }
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  void _setupReverb() async {
    final options = SimpleFlutterReverbOptions(
      scheme: 'wss',
      host: 'api-test-chat.d.aditidemo.asia',
      port: '443',
      appKey: '5wigxwtui29q0dviuc4a',
      authUrl: 'https://api-test-chat.d.aditidemo.asia/broadcasting/auth',
      authToken: authToken,
    );

    reverb = SimpleFlutterReverb(options: options);

    reverb.listen((event) {
      print('Received event: ${event.event}');
      print('Complete event data: ${event.data}');

      if (event.data == null || event.data.isEmpty) {
        print('Received empty event data.  Skipping.');
        return;
      }

      try {
        final messageData = event.data['message'];
        final int currentUserId = 1;

        setState(() {
          _messages.add(
            Message(
              sender: messageData['sender']['name'],
              text: messageData['text'],
              time: DateTime.parse(messageData['created_at'] ?? DateTime.now().toIso8601String()),
              isMe: messageData['sender_id'] == currentUserId,
            ),
          );
        });
        // --- STEP 3: SCROLL AFTER RECEIVING A NEW MESSAGE ---
        _scrollToBottom();
      } catch (e) {
        print('Error processing Reverb message: $e');
        print('Raw event data: ${event.data}');
      }
    }, 'chat.$chatId', isPrivate: true);
  }

  @override
  void dispose() {
    // --- STEP 1: DISPOSE THE SCROLL CONTROLLER ---
    _scrollController.dispose();
    reverb.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF232B38),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                // --- STEP 2: ATTACH THE CONTROLLER TO THE LISTVIEW ---
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return Align(
                    alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      decoration: BoxDecoration(
                        color: msg.isMe ? const Color(0xFF2D3A53) : const Color(0xFFB0B6C1),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: msg.isMe ? const Radius.circular(16) : const Radius.circular(4),
                          bottomRight: msg.isMe ? const Radius.circular(4) : const Radius.circular(16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.sender,
                            style: TextStyle(
                              color: msg.isMe ? Colors.blue[200] : Colors.grey[800],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            msg.text,
                            style: TextStyle(
                              color: msg.isMe ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              "${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}",
                              style: TextStyle(
                                color: msg.isMe ? Colors.blue[100] : Colors.grey[700],
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF232B38),
                border: Border(top: BorderSide(color: Colors.grey[700]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey[600]!),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        filled: true,
                        fillColor: const Color(0xFF2D3A53),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.blue[400],
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}