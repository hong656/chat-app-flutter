import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_flutter_reverb/simple_flutter_reverb.dart';
import 'package:simple_flutter_reverb/simple_flutter_reverb_options.dart';

// --- Import the WebRTC Service and its dependencies ---
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'services/webrtc_service.dart';

// Import the user profile model
import 'models/user_profile_model.dart';

// The widget now only needs the chatId to start
class ChatScreen extends StatefulWidget {
  final int chatId;

  const ChatScreen({
    Key? key,
    required this.chatId,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// (The Message class remains the same)
class Message {
  final int messageId;
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
  // --- Existing State Variables ---
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();
  late SimpleFlutterReverb reverb;
  List<Message> _messages = [];
  String? _token;
  int? _currentUserId;
  String _chatTitle = 'Loading...';
  bool _isLoading = true;
  String? _error;
  final String baseUrl = 'http://127.0.0.1:8000/api';

  // --- NEW: State for WebRTC and Calling ---
  final WebRTCService _webRTCService = WebRTCService();
  bool _isCalling = false; // Controls the UI state (chat vs. calling)


  @override
  void initState() {
    super.initState();
    _initializeChat();
    // Initialize the WebRTC service when the screen loads
    _webRTCService.initialize();
  }

  // --- Master initialization, equivalent to onMounted ---
  Future<void> _initializeChat() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      if (_token == null) throw Exception('Auth token not found.');

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

  // --- NEW: Function to handle initiating a call ---
  void _handleCall(BuildContext context, {required bool isVideoCall}) async {
    setState(() {
      _isCalling = true;
    });

    try {
      // Use the service to start the call process
      await _webRTCService.initiateCall(
        // The service expects a String, but our widget has an int
        chatId: widget.chatId.toString(),
        isVideoCall: isVideoCall,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calling... Awaiting response.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      // In a real app, you would now navigate to a dedicated call screen
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initiating call: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      // If the call fails, return to the chat UI
      setState(() {
        _isCalling = false;
      });
    }
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
        // --- NEW: Call buttons in the AppBar ---
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Video Call',
            // Disable button if a call is already in progress
            onPressed: _isCalling ? null : () => _handleCall(context, isVideoCall: true),
          ),
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Audio Call',
            onPressed: _isCalling ? null : () => _handleCall(context, isVideoCall: false),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // --- NEW: Conditionally show calling UI or chat UI ---
            Expanded(
                child: _isCalling ? _buildCallingUI() : _buildBody()
            ),
            // The message input is hidden when calling
            if (!_isCalling) _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  // --- NEW: Widget to display while a call is being initiated ---
  Widget _buildCallingUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Initiating Call...',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(),
          const SizedBox(height: 30),
          // Container for the local video feed preview
          Container(
            width: 200,
            height: 266,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade700, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: RTCVideoView(
                _webRTCService.localRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Button to cancel the call attempt
          ElevatedButton.icon(
            onPressed: () {
              // TODO: Implement call cancellation on the backend if needed
              setState(() { _isCalling = false; });
            },
            icon: const Icon(Icons.call_end),
            label: const Text('Cancel'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          )
        ],
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

  // (All other methods like _fetchUserProfile, _sendMessage, _deleteMessage, _buildMessageBubble, etc. remain unchanged)
  // --- All the existing chat logic from your original file goes here ---

  @override
  void dispose() {
    reverb.close();
    _scrollController.dispose();
    _controller.dispose();
    _webRTCService.dispose(); // --- NEW: Dispose the service
    super.dispose();
  }

  // --- Paste all your other unchanged methods here ---
  Future<void> _fetchUserProfile() async { /* ... your existing code ... */
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
  Future<void> _fetchChatData() async { /* ... your existing code ... */
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
  Future<void> _fetchMessages() async { /* ... your existing code ... */
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
  Future<void> _sendMessage() async { /* ... your existing code ... */
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
  Future<void> _deleteMessage(int messageId, bool deleteForEveryone) async { /* ... your existing code ... */
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
  void _setupReverbListeners() { /* ... your existing code ... */
    if (_token == null || _currentUserId == null) return;

    final options = SimpleFlutterReverbOptions(
      scheme: 'ws', host: '127.0.0.1', port: '8080',
      appKey: '5wigxwtui29q0dviuc4a', authUrl: 'http://127.0.0.1:8000/broadcasting/auth', authToken: _token!,
    );

    reverb = SimpleFlutterReverb(options: options);
    final channelName = 'chat.${widget.chatId}';

    reverb.listen((event) {
      if (event?.data == null || event!.event == null) return;

      switch (event.event) {
        case 'App\\Events\\MessageSent':
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
            final dynamic receivedId = event.data['messageId'];
            if (receivedId == null) return;
            final int? deletedMessageId = int.tryParse(receivedId.toString());
            if (deletedMessageId == null) return;

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
  void _showDeleteDialog(Message message) { /* ... your existing code ... */
    String deleteOption = 'me';

    showDialog(
      context: context,
      builder: (context) {
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
                  if (message.isMe)
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
  void _scrollToBottom({bool isAnimated = true}) { /* ... your existing code ... */
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
  String _formatTime(DateTime time) { /* ... your existing code ... */
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }
  Widget _buildMessageBubble(Message msg) { /* ... your existing code ... */
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        onLongPress: () => _showDeleteDialog(msg),
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
  Widget _buildMessageInput() { /* ... your existing code ... */
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