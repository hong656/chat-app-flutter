class LatestMessageSender {
  final int userId;
  final String name;
  final bool isYou;

  LatestMessageSender({required this.userId, required this.name, required this.isYou});

  factory LatestMessageSender.fromJson(Map<String, dynamic> json) {
    return LatestMessageSender(
      userId: json['user_id'],
      name: json['name'],
      isYou: json['is_you'],
    );
  }
}

class LatestMessage {
  final int messageId;
  final String text;
  final DateTime createdAt;
  final LatestMessageSender sender;

  LatestMessage({
    required this.messageId,
    required this.text,
    required this.createdAt,
    required this.sender,
  });

  factory LatestMessage.fromJson(Map<String, dynamic> json) {
    return LatestMessage(
      messageId: json['message_id'],
      text: json['text'],
      createdAt: DateTime.parse(json['created_at']),
      sender: LatestMessageSender.fromJson(json['sender']),
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

class Chat {
  final int chatId;
  final bool isGroup;
  final String title;
  final List<ChatMember> members;
  final LatestMessage? latestMessage; // Can be null

  Chat({
    required this.chatId,
    required this.isGroup,
    required this.title,
    required this.members,
    this.latestMessage,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    var membersList = json['members'] as List;
    List<ChatMember> members = membersList.map((i) => ChatMember.fromJson(i)).toList();

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