import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/support_chat_message.dart';

class OrderChatParams {
  final String customerUserId;
  final int? orderId;

  const OrderChatParams({
    required this.customerUserId,
    this.orderId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderChatParams &&
          runtimeType == other.runtimeType &&
          customerUserId == other.customerUserId &&
          orderId == other.orderId;

  @override
  int get hashCode => customerUserId.hashCode ^ orderId.hashCode;
}

/// Realtime chat stream for a specific customer order
final customerOrderChatProvider = StreamProvider.autoDispose
    .family<List<SupportChatMessage>, OrderChatParams>((ref, params) {
  final supabase = Supabase.instance.client;
  final customerUserId = params.customerUserId;
  final orderId = params.orderId;

  final controller = StreamController<List<SupportChatMessage>>();
  List<SupportChatMessage> messages = [];

  void updateStream() {
    if (!controller.isClosed) controller.add(List.from(messages));
  }

  // 1. Initial Fetch
  dynamic query = supabase.from('chat_messages').select();
  if (customerUserId.isNotEmpty) {
    query = query.eq('user_id', customerUserId);
  }
  if (orderId != null) {
    query = query.eq('order_id', orderId);
  } else if (customerUserId.isNotEmpty) {
    query = query.filter('order_id', 'is', null);
  }

  query.order('created_at', ascending: false).then((data) {
    messages = (data as List)
        .map((m) => SupportChatMessage.fromJson(m))
        .toList();
    updateStream();
  }).catchError((e) {
    if (!controller.isClosed) controller.add([]);
  });

  // 2. Realtime Postgres Changes Subscription
  final channelName = 'store_customer_chat_${orderId ?? "gen"}_${customerUserId.isNotEmpty ? customerUserId : "all"}';
  
  final subscription = supabase
      .channel(channelName)
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chat_messages',
        filter: customerUserId.isNotEmpty
            ? PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: customerUserId,
              )
            : null,
        callback: (payload) {
          final msgOrderId = payload.newRecord['order_id'];
          if (orderId != null) {
            if (msgOrderId != orderId) return;
          } else {
            if (msgOrderId != null) return;
          }

          final newMsg = SupportChatMessage.fromJson(payload.newRecord);
          if (!messages.any((m) => m.id == newMsg.id && newMsg.id.isNotEmpty)) {
            messages.insert(0, newMsg);
            updateStream();
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    subscription.unsubscribe();
    controller.close();
  });

  return controller.stream;
});

class SupportChatService {
  /// Store staff sends message to customer for this order
  static Future<void> sendStoreMessageToCustomer({
    required String customerUserId,
    int? orderId,
    required String message,
  }) async {
    await Supabase.instance.client.from('chat_messages').insert({
      'user_id': customerUserId,
      'order_id': orderId,
      'message': message,
      'is_admin_reply': true, // Sent by Store / Operations
    });
  }

  /// Customer or fallback support message
  static Future<void> sendMessage({
    required String userId,
    int? orderId,
    required String message,
  }) async {
    await Supabase.instance.client.from('chat_messages').insert({
      'user_id': userId,
      'order_id': orderId,
      'message': message,
      'is_admin_reply': true,
    });
  }
}
