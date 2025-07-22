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
  // State Variables
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();
  late SimpleFlutterReverb reverb;
  List<Message> _messages = [];
  String? _token;
  int? _currentUserId;
  String _chatTitle = 'Loading...';
  bool _isLoading = true;
  String? _error;
  final String baseUrl = 'http://127.0.0.1:8000/api'; // Ensure this is your correct local URL for testing

  // WebRTC & Calling State
  final WebRTCService _webRTCService = WebRTCService();
  bool _isCalling = false;

  // =========== Lifecycle Methods ===========

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _webRTCService.initialize();
  }

  @override
  void dispose() {
    // This is the single, correct dispose method
    reverb.close();
    _scrollController.dispose();
    _controller.dispose();
    _webRTCService.dispose();
    super.dispose();
  }

  // =========== Core Initialization & Listeners ===========

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

  void _setupReverbListeners() {
    if (_token == null || _currentUserId == null) return;

    final String hostIp = '127.0.0.1'; // <-- CHANGE THIS IF ON IOS SIMULATOR

    final options = SimpleFlutterReverbOptions(
      scheme: 'ws',
      host: hostIp,
      port: '8080', // Default Reverb port is 8080
      appKey: '5wigxwtui29q0dviuc4a', // Your local app key from .env
      authUrl: 'http://$hostIp:8000/broadcasting/auth', // Your Laravel server URL
      authToken: _token!,
    );

    reverb = SimpleFlutterReverb(options: options);
    final channelName = 'chat.${widget.chatId}';

    reverb.listen((event) {
      if (event?.data == null || event!.event == null) return;

      switch (event.event) {
      // --- FIXED CASE 1: MESSAGE SENT ---
        case 'App\\Events\\MessageSent':
          try {
            final messageData = event.data['message'];
            if (messageData == null) return;

            final newMessage = Message.fromJson(messageData, _currentUserId!);

            // Prevent adding a message that's already in the list
            if (!_messages.any((msg) => msg.messageId == newMessage.messageId)) {
              setState(() {
                _messages.add(newMessage);
              });
              _scrollToBottom();
            }
          } catch (e) {
            print('Error processing MessageSent: $e');
          }
          break;

      // --- FIXED CASE 2: MESSAGE DELETED ---
        case 'App\\Events\\MessageDeleted':
          try {
            // Robustly parse the message ID
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

      // --- WORKING CASE 3: INCOMING CALL ---
        case 'App\\Events\\IncomingCall':
          try {
            if (_isCalling) return;
            print('INCOMING CALL EVENT RECEIVED!');
            final data = event.data as Map<String, dynamic>;
            final callerInfo = data['caller'] as Map<String, dynamic>;
            final offer = data['offer'] as Map<String, dynamic>;
            _showIncomingCallDialog(callerInfo, offer);
          } catch (e) {
            print('Error processing IncomingCall event: $e');
          }
          break;

        default:
          print('Received unhandled event type: ${event.event}');
      }
    }, channelName, isPrivate: true);
  }

  // =========== Calling Logic ===========

  void _handleCall(BuildContext context, {required bool isVideoCall}) async {
    setState(() { _isCalling = true; });
    try {
      await _webRTCService.initiateCall(
        chatId: widget.chatId.toString(),
        isVideoCall: isVideoCall,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calling... Awaiting response.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initiating call: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
      setState(() { _isCalling = false; });
    }
  }

  void _showIncomingCallDialog(Map<String, dynamic> callerInfo, Map<String, dynamic> offer) {
    if (ModalRoute.of(context)?.isCurrent != true) return; // Prevent showing dialog if not on this screen
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final callerName = callerInfo['name'] ?? 'Someone';
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('Incoming Call'),
          content: Text('$callerName is calling...'),
          actions: <Widget>[
            TextButton(
              child: const Text('Decline', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onPressed: () {
                // TODO: Notify the caller that the call was declined.
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Accept'),
              onPressed: () {
                Navigator.of(context).pop();
                _acceptCall(offer);
              },
            ),
          ],
        );
      },
    );
  }

  void _acceptCall(Map<String, dynamic> offer) {
    print("Call accepted! Now processing this offer: $offer");
    // TODO: This is the next major step.
    // 1. Set the 'offer' as the remote description.
    // 2. Get local camera/mic stream.
    // 3. Create an 'Answer'.
    // 4. Set the 'Answer' as the local description.
    // 5. Send the 'Answer' back to the caller via a new API endpoint.
  }

  // =========== Data Fetching & Message Handling ===========

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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _token == null) return;
    try {
      await http.post(
        Uri.parse('$baseUrl/messages'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'chat_id': widget.chatId, 'message_type': 'text', 'text': text}),
      );
      _controller.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
    }
  }

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete message.'), backgroundColor: Colors.red));
        _fetchMessages(); // Restore messages on failure
      }
    }
  }

  void _showDeleteDialog(Message message) {
    String deleteOption = 'me';
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Delete Message'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
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
              ]),
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

  void _scrollToBottom({bool isAnimated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (isAnimated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
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

  // =========== UI Build Methods ===========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF232B38),
      appBar: AppBar(
        title: Text(_chatTitle),
        backgroundColor: const Color(0xFF2D3A53),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Video Call',
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
            Expanded(child: _isCalling ? _buildCallingUI() : _buildBody()),
            if (!_isCalling) _buildMessageInput(),
          ],
        ),
      ),
    );
  }

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
          ElevatedButton.icon(
            onPressed: () {
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

  Widget _buildMessageBubble(Message msg) {
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
                filled: true,
                fillColor: const Color(0xFF2D3A53),
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