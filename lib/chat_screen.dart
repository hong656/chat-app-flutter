import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_flutter_reverb/simple_flutter_reverb.dart';
import 'package:simple_flutter_reverb/simple_flutter_reverb_options.dart';

// Import the new model
import 'models/user_profile_model.dart';

// --- The widget now only needs the chatId to start ---
class ChatScreen extends StatefulWidget {
  final int chatId;

  const ChatScreen({
    Key? key,
    required this.chatId,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class Message {
  final int messageId; // Add messageId for deletion
  final String sender;
  final int senderId;
  final String text;
  final DateTime time;
  bool isMe;

  Message({
    required this.messageId,
    required this.sender,
    required this.senderId,
    required this.text,
    required this.time,
    required this.isMe,
  });

  factory Message.fromJson(Map<String, dynamic> json, int currentUserId) {
    final senderData = json['sender'] as Map<String, dynamic>? ?? {};
    final senderId = senderData['user_id'] as int? ?? 0;
    final senderName = senderData['name'] as String? ?? 'Unknown User';

    final createdAt = json['created_at'] as String? ?? DateTime.now().toIso8601String();

    return Message(
      messageId: json['message_id'],
      sender: senderName,
      senderId: senderId,
      text: json['text'] as String? ?? '',
      time: DateTime.parse(createdAt),
      isMe: senderId == currentUserId,
    );
  }
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();
  late SimpleFlutterReverb reverb;

  // --- State variables matching the Nuxt 'ref's ---
  List<Message> _messages = [];
  String? _token;
  int? _currentUserId;
  String _chatTitle = 'Loading...';

  bool _isLoading = true;
  String? _error;

  final String baseUrl = 'https://api-test-chat.d.aditidemo.asia/api';

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  // --- Master initialization, equivalent to onMounted ---
  Future<void> _initializeChat() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      if (_token == null) throw Exception('Auth token not found.');

      // Perform fetches in sequence, just like the Nuxt example
      await _fetchUserProfile();
      await _fetchChatData();
      await _fetchMessages();
      _setupReverbListeners();

      setState(() => _isLoading = false);

    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // --- Equivalent to fetchUserProfile() ---
  Future<void> _fetchUserProfile() async {
    final response = await http.get(
      Uri.parse('$baseUrl/profile'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final profile = UserProfile.fromJson(jsonResponse['data']);
      _currentUserId = profile.userId;
    } else {
      throw Exception('Failed to fetch user profile.');
    }
  }

  // --- Equivalent to fetchChatData() ---
  Future<void> _fetchChatData() async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/${widget.chatId}'),
      headers: {'Authorization': 'Bearer $_token', 'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      if (jsonResponse['success'] == true && jsonResponse['data'] != null) {
        final chatData = jsonResponse['data'];
        if (chatData['is_group']) {
          setState(() => _chatTitle = chatData['title']);
        } else {
          final members = chatData['members'] as List;
          final otherMember = members.firstWhere((m) => m['is_you'] == false, orElse: () => null);
          setState(() => _chatTitle = otherMember != null ? otherMember['name'] : 'Chat');
        }
      }
    } else {
      setState(() => _chatTitle = 'Chat');
      throw Exception('Failed to fetch chat data.');
    }
  }

  // --- Equivalent to fetchMessages() ---
  Future<void> _fetchMessages() async {
    if (_currentUserId == null) return;
    final response = await http.get(
      Uri.parse('$baseUrl/messages/${widget.chatId}'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final List<dynamic> data = jsonResponse['data'];
      setState(() {
        _messages = data.map((json) => Message.fromJson(json, _currentUserId!)).toList();
      });
      _scrollToBottom(isAnimated: false);
    } else {
      throw Exception('Failed to load messages.');
    }
  }

  // --- Equivalent to sendMessage() ---
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _token == null) return;

    try {
      await http.post(
        Uri.parse('$baseUrl/messages'),
        headers: {
          'Accept': 'application/json', 'Authorization': 'Bearer $_token', 'Content-Type': 'application/json',
        },
        body: jsonEncode({'chat_id': widget.chatId, 'message_type': 'text', 'text': text}),
      );
      _controller.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
    }
  }

  // --- Equivalent to deleteMessage() ---
  Future<void> _deleteMessage(int messageId, bool deleteForEveryone) async {
    setState(() {
      _messages.removeWhere((msg) => msg.messageId == messageId);
    });

    try {
      await http.delete(
        Uri.parse('$baseUrl/messages/$messageId'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'delete_for_everyone': deleteForEveryone}),
      );
    } catch (e) {
      print('Error deleting message: $e. Restoring UI.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete message.'), backgroundColor: Colors.red)
        );
        _fetchMessages();
      }
    }
  }

  void _setupReverbListeners() {
    if (_token == null || _currentUserId == null) return;

    final options = SimpleFlutterReverbOptions(
      scheme: 'wss', host: 'api-test-chat.d.aditidemo.asia', port: '443',
      appKey: '5wigxwtui29q0dviuc4a', authUrl: 'https://api-test-chat.d.aditidemo.asia/broadcasting/auth', authToken: _token!,
    );

    reverb = SimpleFlutterReverb(options: options);
    final channelName = 'chat.${widget.chatId}';

    reverb.listen((event) {
      if (event?.data == null || event!.event == null) return;

      switch (event.event) {
        case 'App\\Events\\MessageSent':
        // This part works, so we keep it.
          try {
            final messageData = event.data['message'];
            if (messageData == null) return;
            final newMessage = Message.fromJson(messageData, _currentUserId!);

            if (!_messages.any((msg) => msg.messageId == newMessage.messageId)) {
              setState(() => _messages.add(newMessage));
              _scrollToBottom();
            }
          } catch (e) {
            print('Error processing MessageSent: $e');
          }
          break;

        case 'App\\Events\\MessageDeleted':
          try {
            // --- THE ROBUST FIX ---
            // 1. Get the ID as a dynamic type.
            final dynamic receivedId = event.data['messageId'];
            if (receivedId == null) return;

            // 2. Safely parse it to an integer. If it's already an int, this does nothing.
            // If it's a String like "123", it becomes the int 123.
            // If it's a double like 123.0, it becomes the int 123.
            // We use toString() to handle all cases (int, double, string).
            final int? deletedMessageId = int.tryParse(receivedId.toString());
            if (deletedMessageId == null) return; // If parsing fails, do nothing.

            // 3. Now the comparison is guaranteed to be between two integers.
            setState(() {
              _messages.removeWhere((msg) => msg.messageId == deletedMessageId);
            });
            print('Successfully removed message ID: $deletedMessageId in real-time.');

          } catch (e) {
            print('Error processing MessageDeleted: $e');
          }
          break;

        default:
          print('Received unhandled event type: ${event.event}');
      }
    }, channelName, isPrivate: true);
  }

  // --- UI Functions ---

  void _showDeleteDialog(Message message) {
    String deleteOption = 'me'; // 'me' or 'everyone'

    showDialog(
      context: context,
      builder: (context) {
        // StatefulBuilder is used to manage state inside the dialog
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Delete Message'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: const Text('Delete for me'),
                    value: 'me',
                    groupValue: deleteOption,
                    onChanged: (value) => setDialogState(() => deleteOption = value!),
                  ),
                  if (message.isMe) // Only show 'delete for everyone' if it's your message
                    RadioListTile<String>(
                      title: const Text('Delete for everyone'),
                      value: 'everyone',
                      groupValue: deleteOption,
                      onChanged: (value) => setDialogState(() => deleteOption = value!),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _deleteMessage(message.messageId, deleteOption == 'everyone');
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Helper Functions & Lifecycle ---

  void _scrollToBottom({bool isAnimated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (isAnimated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  String _formatTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    reverb.close();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // --- Build Methods ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF232B38),
      appBar: AppBar(
        title: Text(_chatTitle),
        backgroundColor: const Color(0xFF2D3A53),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)));

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
    );
  }

  Widget _buildMessageBubble(Message msg) {
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        onLongPress: () => _showDeleteDialog(msg), // Trigger delete dialog on long press
        borderRadius: BorderRadius.circular(16),
        child: Container(
          // ... (rest of the bubble styling is the same)
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: msg.isMe ? const Color(0xFF2D3A53) : const Color(0xFFB0B6C1),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
              bottomLeft: msg.isMe ? const Radius.circular(16) : const Radius.circular(4),
              bottomRight: msg.isMe ? const Radius.circular(4) : const Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg.sender,
                style: TextStyle(color: msg.isMe ? Colors.blue[200] : Colors.grey[800], fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                msg.text,
                style: TextStyle(color: msg.isMe ? Colors.white : Colors.black, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  _formatTime(msg.time),
                  style: TextStyle(color: msg.isMe ? Colors.blue[100] : Colors.grey[700], fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true, fillColor: const Color(0xFF2D3A53),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blue[400],
            child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendMessage),
          ),
        ],
      ),
    );
  }
}