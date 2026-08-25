class SupportChatMessage {
  final String id;
  final int? orderId;
  final String userId;
  final String message;
  final bool isAdminReply;
  final DateTime createdAt;

  const SupportChatMessage({
    required this.id,
    this.orderId,
    required this.userId,
    required this.message,
    required this.isAdminReply,
    required this.createdAt,
  });

  factory SupportChatMessage.fromJson(Map<String, dynamic> json) {
    return SupportChatMessage(
      id: json['id']?.toString() ?? '',
      orderId: json['order_id'] as int?,
      userId: json['user_id']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      isAdminReply: json['is_admin_reply'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'order_id': orderId,
      'message': message,
      'is_admin_reply': isAdminReply,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
