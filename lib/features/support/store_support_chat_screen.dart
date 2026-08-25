import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/haptic_service.dart';
import '../../core/services/sound_service.dart';
import '../../core/theme/app_theme.dart';
import 'models/support_chat_message.dart';
import 'providers/support_chat_provider.dart';

class StoreSupportChatScreen extends ConsumerStatefulWidget {
  final String? customerUserId;
  final int? orderId;
  final String? orderRef;
  final String? customerName;
  final String? customerPhone;

  const StoreSupportChatScreen({
    super.key,
    this.customerUserId,
    this.orderId,
    this.orderRef,
    this.customerName,
    this.customerPhone,
  });

  @override
  ConsumerState<StoreSupportChatScreen> createState() => _StoreSupportChatScreenState();
}

class _StoreSupportChatScreenState extends ConsumerState<StoreSupportChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final SoundService _soundService = SoundService();

  late String _effectiveUserId;
  bool _isSending = false;

  bool get _isDirectCustomerChat => widget.customerUserId != null && widget.customerUserId!.isNotEmpty;

  List<String> get _quickChips => _isDirectCustomerChat
      ? [
          '⚖️ Weight confirmed, preparing now!',
          '✂️ Cleaning & cutting in progress.',
          '📦 Order packed & verified.',
          '🏍️ Delivery partner assigned & dispatched.',
          '🐟 Fresh morning catch from Pulicat!',
          '📞 Calling you now for confirmation.',
        ]
      : [
          '📞 Call Helpline (+91 9384332235)',
          '📦 Order Pipeline Issue',
          '⚖️ Weighing Scale / Sourcing',
          '🏍️ Delivery Partner Assignment',
          '💵 Cashflow & Expenses Settlement',
          '🙋 Speak with Operations Admin',
        ];

  @override
  void initState() {
    super.initState();
    final authUser = Supabase.instance.client.auth.currentUser;
    _effectiveUserId = (widget.customerUserId != null && widget.customerUserId!.isNotEmpty)
        ? widget.customerUserId!
        : (authUser?.id ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSendMessage([String? customText]) async {
    final text = (customText ?? _textController.text).trim();
    if (text.isEmpty || _isSending) return;

    if (_effectiveUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot identify chat user ID. Please check order details.')),
      );
      return;
    }

    if (customText == null) {
      _textController.clear();
    }

    setState(() => _isSending = true);
    AppHaptics.mediumImpact();
    _soundService.playStepTransition();

    try {
      await SupportChatService.sendStoreMessageToCustomer(
        customerUserId: _effectiveUserId,
        orderId: widget.orderId,
        message: text,
      );

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _makeDirectCall() async {
    AppHaptics.selectionClick();
    final rawPhone = widget.customerPhone ?? '9384332235';
    final cleanPhone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatParams = OrderChatParams(
      customerUserId: _effectiveUserId,
      orderId: widget.orderId,
    );
    final messagesAsync = ref.watch(customerOrderChatProvider(chatParams));

    final displayName = widget.customerName ?? (_isDirectCustomerChat ? 'Customer' : 'MeenMart Operations Support');
    final displayPhone = widget.customerPhone ?? (_isDirectCustomerChat ? '' : '+91 9384332235');
    final orderTag = widget.orderRef != null ? '#${widget.orderRef}' : (widget.orderId != null ? '#${widget.orderId}' : '');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: _isDirectCustomerChat ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                  child: Icon(
                    _isDirectCustomerChat ? Icons.person_rounded : Icons.support_agent_rounded,
                    color: _isDirectCustomerChat ? const Color(0xFF2563EB) : const Color(0xFF059669),
                    size: 22,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (orderTag.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            orderTag,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        width: 5.5,
                        height: 5.5,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        displayPhone.isNotEmpty ? '$displayPhone • Live Chat' : 'Online • Live Customer Sync',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF059669),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF059669), size: 21),
            tooltip: 'Call Phone',
            onPressed: _makeDirectCall,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // 1. QUICK ORDER COMMUNICATION CHIPS
          Container(
            height: 44,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _quickChips.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final chipText = _quickChips[index];
                return InkWell(
                  onTap: () {
                    if (chipText.startsWith('📞')) {
                      _makeDirectCall();
                    } else {
                      _handleSendMessage(chipText);
                    }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Center(
                      child: Text(
                        chipText,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // 2. LIVE CHAT MESSAGE LIST
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 10),
                      Text(
                        'No messages yet',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Send an update to start chatting with the customer.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _isDirectCustomerChat ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isDirectCustomerChat ? Icons.forum_rounded : Icons.mark_chat_read_rounded,
                              size: 40,
                              color: _isDirectCustomerChat ? const Color(0xFF2563EB) : const Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _isDirectCustomerChat ? 'Live Chat with $displayName' : 'MeenMart Operations Support',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isDirectCustomerChat
                                ? 'Send order status, weight updates, or delivery timing directly to the customer.'
                                : 'Ask questions regarding store operations, inventory, or rider allocation.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              color: const Color(0xFF64748B),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _buildMessageBubble(msg);
                  },
                );
              },
            ),
          ),

          // 3. BOTTOM CHAT INPUT BAR
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: const Color(0xFF0F172A), fontWeight: FontWeight.w500),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleSendMessage(),
                        decoration: InputDecoration(
                          hintText: _isDirectCustomerChat ? 'Message $displayName...' : 'Type message to support...',
                          hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(0xFF059669),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => _handleSendMessage(),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(SupportChatMessage msg) {
    // In Store App:
    // is_admin_reply == true -> Sent by Store Staff / Admin (ME, Right side)
    // is_admin_reply == false -> Sent by Customer (THEM, Left side)
    final isMe = msg.isAdminReply;
    final timeStr = DateFormat('hh:mm a').format(msg.createdAt);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF059669) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: isMe ? null : Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isMe ? 0.08 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded, size: 10, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.customerName ?? 'Customer',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(
              msg.message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isMe ? Colors.white : const Color(0xFF1E293B),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isMe ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF94A3B8),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.done_all_rounded, size: 13, color: Colors.white70),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
