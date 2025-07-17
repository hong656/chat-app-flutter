// This file contains the data structures for your chat list.

class ApiResponse {
  final bool success;
  final List<Chat> data;

  ApiResponse({required this.success, required this.data});

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    var list = json['data'] as List;
    List<Chat> chatList = list.map((i) => Chat.fromJson(i)).toList();
    return ApiResponse(
      success: json['success'],
      data: chatList,
    );
  }
}

class Chat {
  final int chatId;
  final bool isGroup;
  final String title;
  final List<ChatMember> members;
  final LatestMessage? latestMessage;

  Chat({
    required this.chatId,
    required this.isGroup,
    required this.title,
    required this.members,
    this.latestMessage,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    var memberList = json['members'] as List;
    List<ChatMember> members = memberList.map((i) => ChatMember.fromJson(i)).toList();

    return Chat(
      chatId: json['chat_id'],
      isGroup: json['is_group'],
      title: json['title'],
      members: members,
      latestMessage: json['latest_message'] != null
          ? LatestMessage.fromJson(json['latest_message'])
          : null,
    );
  }
}

class ChatMember {
  final int userId;
  final String name;
  final bool isYou;

  ChatMember({required this.userId, required this.name, required this.isYou});

  factory ChatMember.fromJson(Map<String, dynamic> json) {
    return ChatMember(
      userId: json['user_id'],
      name: json['name'],
      isYou: json['is_you'],
    );
  }
}

class LatestMessage {
  final String text;
  final String createdAt;
  final ChatMember sender;

  LatestMessage({required this.text, required this.createdAt, required this.sender});

  factory LatestMessage.fromJson(Map<String, dynamic> json) {
    return LatestMessage(
      text: json['text'],
      createdAt: json['created_at'],
      sender: ChatMember.fromJson(json['sender']),
    );
  }
}