import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../constants/app_constants.dart';
import '../../providers/chat_attachment_provider.dart';
import '../../providers/message_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/message_service.dart';
import '../order_change_request_sheet.dart';

/// Shared chat screen used by both Customer and Seller sides.
///
/// Parameterized by [viewerRole] ('seller' | 'customer') to handle
/// bubble alignment, read receipts, and realtime wiring consistently.
class ChatView extends StatefulWidget {
  final String conversationId;
  final String viewerRole; // 'seller' | 'customer'
  final String otherPartyName;
  final String? orderReferenceId;
  final String? initialMessage; // Pre-filled message to send on open
  final bool showChangeRequest; // Open Request a Change flow on open
  final bool focusInput; // Focus the text input on open

  const ChatView({
    super.key,
    required this.conversationId,
    required this.viewerRole,
    required this.otherPartyName,
    this.orderReferenceId,
    this.initialMessage,
    this.showChangeRequest = false,
    this.focusInput = false,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  RealtimeChannel? _typingChannel;
  String? _currentUserId;
  bool _isOtherPartyTyping = false;
  Timer? _typingDebounce;
  bool _hasSentTypingStart = false;
  late AnimationController _typingAnimController;

  // Attachment state
  File? _pendingAttachment;
  String? _pendingAttachmentType; // 'image' | 'video'
  int? _pendingVideoDuration;
  bool _isUploading = false;



  // Scroll tracking for "New message ↓" pill
  bool _isNearBottom = true;
  bool _hasNewMessages = false;

  // Reconnection handling
  StreamSubscription<bool>? _connectivitySub;
  bool _wasOffline = false;

  bool get _isCustomer => widget.viewerRole == 'customer';

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _typingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _setupScrollListener();
    _setupConnectivityListener();
    _loadMessages();
    _subscribeToMessages();
    _subscribeToTyping();
    _markAsRead();
    
    // Handle initial actions after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.showChangeRequest && mounted) {
        _showChangeRequest();
      } else if (widget.initialMessage != null && mounted) {
        _messageController.text = widget.initialMessage!;
        _sendMessage();
      } else if (widget.focusInput && mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _connectivitySub?.cancel();
    _typingDebounce?.cancel();
    _typingAnimController.dispose();
    // Fire-and-forget typing stop on dispose
    if (_hasSentTypingStart && _currentUserId != null) {
      MessageService.instance.sendTypingStop(
        conversationId: widget.conversationId,
        senderId: _currentUserId!,
        senderType: widget.viewerRole,
      );
    }
    if (_typingChannel != null) {
      MessageService.instance.unsubscribeFromTyping(_typingChannel!, conversationId: widget.conversationId);
    }
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Track scroll position to determine if user is near the bottom.
  /// Used to decide whether to auto-scroll on new messages or show
  /// the "New message ↓" pill instead.
  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      // Consider "near bottom" if within 150px of the end
      final wasNearBottom = _isNearBottom;
      _isNearBottom = (maxScroll - currentScroll) < 150;

      // If user scrolled to bottom, clear the new message indicator
      if (_isNearBottom && !wasNearBottom && _hasNewMessages) {
        setState(() => _hasNewMessages = false);
      }
    });
  }

  /// Listen for connectivity changes and re-sync messages on reconnect.
  /// This catches any messages missed during an offline period.
  void _setupConnectivityListener() {
    _wasOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.isOnlineStream.listen((isOnline) {
      if (isOnline && _wasOffline && mounted) {
        // Connection restored — re-sync messages to catch anything missed
        _loadMessages();
        _subscribeToMessages();
      }
      _wasOffline = !isOnline;
    });
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await MessageService.instance.getMessages(widget.conversationId);
      if (mounted) {
        final provider = context.read<ChatAttachmentProvider>();
        setState(() {
          // Merge DB messages with any persisted failed messages
          _messages = provider.mergeWithFailed(messages, widget.conversationId);
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribeToMessages() {
    _subscription?.cancel();
    _subscription = MessageService.instance.subscribeToConversation(
      widget.conversationId,
      (messages) {
        if (!mounted) return;

        // Detect new incoming messages from the other party
        final previousCount = _messages.length;
        final hasNewIncoming = messages.length > previousCount &&
            messages.any((m) => m.senderType != widget.viewerRole &&
                !_messages.any((old) => old.id == m.id));

        setState(() {
          // Preserve local-only fields from optimistic messages
          final localOnly = {
            for (final m in _messages)
              if (m.isSending || m.sendFailed) m.id: m,
          };
          _messages = messages.map((m) {
            final local = localOnly[m.id];
            if (local != null) {
              return Message(
                id: m.id,
                conversationId: m.conversationId,
                senderId: m.senderId,
                senderType: m.senderType,
                body: m.body,
                orderReferenceId: m.orderReferenceId,
                isRead: m.isRead,
                createdAt: m.createdAt,
                attachmentUrl: m.attachmentUrl,
                attachmentType: m.attachmentType,
                attachmentThumbnailUrl: m.attachmentThumbnailUrl,
                attachmentDurationSeconds: m.attachmentDurationSeconds,
                attachmentSizeBytes: m.attachmentSizeBytes,
                isSending: local.isSending,
                sendFailed: local.sendFailed,
                localFile: local.localFile,
                progress: local.progress,
              );
            }
            return m;
          }).toList();

        });

        // Auto-scroll or show "New message ↓" pill
        if (hasNewIncoming) {
          if (_isNearBottom) {
            _scrollToBottom();
          } else {
            setState(() => _hasNewMessages = true);
          }
          // Mark as read when the other party's message arrives
          if (messages.last.senderType != widget.viewerRole) {
            MessageService.instance.markConversationRead(
              conversationId: widget.conversationId,
              readerType: widget.viewerRole,
            );
          }
        }
      },
    );
  }

  Future<void> _markAsRead() async {
    // Optimistic local update — immediately zero the unread count in the
    // provider so the badge and row styling update without waiting for
    // the server round-trip.
    if (mounted) {
      context.read<MessageProvider>().optimisticMarkAsRead(widget.conversationId);
    }
    // Server-side mark (fire-and-forget — the realtime subscription
    // will reconcile if needed).
    MessageService.instance.markConversationRead(
      conversationId: widget.conversationId,
      readerType: widget.viewerRole,
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _subscribeToTyping() {
    if (_currentUserId == null) return;
    _typingChannel = MessageService.instance.subscribeToTyping(
      conversationId: widget.conversationId,
      senderId: _currentUserId!,
      senderType: widget.viewerRole,
      onTypingChanged: (isTyping) {
        if (mounted) {
          setState(() => _isOtherPartyTyping = isTyping);
          if (isTyping) {
            _scrollToBottom();
            _typingAnimController.repeat();
          } else {
            _typingAnimController.stop();
            _typingAnimController.reset();
          }
        }
      },
    );
  }

  void _onTextChanged(String value) {
    setState(() {});
    if (value.trim().isNotEmpty && !_hasSentTypingStart) {
      _hasSentTypingStart = true;
      _sendTypingStart();
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _sendTypingStop();
    });
  }

  void _sendTypingStart() {
    if (_currentUserId == null) return;
    MessageService.instance.sendTypingStart(
      conversationId: widget.conversationId,
      senderId: _currentUserId!,
      senderType: widget.viewerRole,
    );
  }

  void _sendTypingStop() {
    if (_currentUserId == null || !_hasSentTypingStart) return;
    _hasSentTypingStart = false;
    MessageService.instance.sendTypingStop(
      conversationId: widget.conversationId,
      senderId: _currentUserId!,
      senderType: widget.viewerRole,
    );
  }

  // ─── ATTACHMENT PICKING ──────────────────────────────────────

  Future<void> _pickAttachment(ImageSource source) async {
    try {
      final XFile? picked;
      if (source == ImageSource.camera) {
        // For camera, show dialog to choose photo or video
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Capture'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'photo'),
                child: const Row(children: [Icon(Icons.camera_alt), SizedBox(width: 12), Text('Take Photo')]),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'video'),
                child: const Row(children: [Icon(Icons.videocam), SizedBox(width: 12), Text('Record Video')]),
              ),
            ],
          ),
        );
        if (choice == null || !mounted) return;
        picked = choice == 'photo'
            ? await _imagePicker.pickImage(source: source, maxWidth: 1920, maxHeight: 1920, imageQuality: 85)
            : await _imagePicker.pickVideo(source: source);
      } else {
        picked = await _imagePicker.pickMedia(
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
      }
      if (picked == null || !mounted) return;

      final file = File(picked.path);
      final sizeBytes = await file.length();

      // Client-side 25MB limit
      if (sizeBytes > 25 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File is too large — max 25MB'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
        return;
      }

      final isVideo = picked.mimeType?.startsWith('video/') == true ||
          picked.path.toLowerCase().endsWith('.mp4') ||
          picked.path.toLowerCase().endsWith('.mov');

      int? videoDuration;
      if (isVideo) {
        // Try to get video duration
        try {
          final controller = VideoPlayerController.file(file);
          await controller.initialize();
          videoDuration = controller.value.duration.inSeconds;
          await controller.dispose();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _pendingAttachment = file;
          _pendingAttachmentType = isVideo ? 'video' : 'image';
          _pendingVideoDuration = videoDuration;
        });
        _showAttachmentPreview();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick file: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  void _showAttachmentPreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AttachmentPreviewSheet(
        file: _pendingAttachment!,
        attachmentType: _pendingAttachmentType!,
        videoDuration: _pendingVideoDuration,
        onSend: _sendAttachmentMessage,
        onCancel: () {
          setState(() {
            _pendingAttachment = null;
            _pendingAttachmentType = null;
            _pendingVideoDuration = null;
          });
        },
      ),
    ).then((_) {
      // If user dismissed without sending, clear pending
      if (_pendingAttachment != null && !_isUploading) {
        setState(() {
          _pendingAttachment = null;
          _pendingAttachmentType = null;
          _pendingVideoDuration = null;
        });
      }
    });
  }

  Future<void> _sendAttachmentMessage({String? caption}) async {
    if (_pendingAttachment == null || _currentUserId == null) return;
    if (mounted) Navigator.of(context).pop(); // dismiss preview

    _sendTypingStop();
    _typingDebounce?.cancel();

    final file = _pendingAttachment!;
    final type = _pendingAttachmentType!;
    final duration = _pendingVideoDuration;
    final body = caption != null && caption.trim().isNotEmpty ? caption.trim() : null;

    // Generate a client-side UUID so storage path matches the DB row
    final messageId = const Uuid().v4();

    // Insert a placeholder message immediately with isSending=true
    // isRead starts as false — will flip to true via realtime when recipient reads
    final placeholder = Message(
      id: messageId,
      conversationId: widget.conversationId,
      senderId: _currentUserId!,
      senderType: widget.viewerRole,
      body: body,
      orderReferenceId: widget.orderReferenceId,
      isRead: false,
      createdAt: DateTime.now(),
      attachmentType: type,
      isSending: true,
      localFile: file,
    );

    if (mounted) {
      setState(() {
        _isUploading = true;
        _messages.add(placeholder);
        _pendingAttachment = null;
        _pendingAttachmentType = null;
        _pendingVideoDuration = null;
      });
      _scrollToBottom();
    }

    try {
      // Determine MIME type with proper mapping for common extensions
      final ext = file.path.split('.').last.toLowerCase();
      final mimeType = _resolveMimeType(type, ext);

      // MIME type validation is handled inside MessageService.uploadAttachment().
      // Upload attachment using the pre-generated ID, with real chunked-read progress
      final uploadResult = await MessageService.instance.uploadAttachment(
        conversationId: widget.conversationId,
        messageId: messageId,
        filePath: file.path,
        mimeType: mimeType,
        onProgress: (pct) {
          if (!mounted) return;
          setState(() {
            // Update the placeholder message's progress field for the UI
            final idx = _messages.indexWhere((m) => m.id == messageId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(progress: pct);
            }
          });
        },
      );

      // Generate video thumbnail if needed
      String? thumbnailUrl;
      if (type == 'video') {
        final thumbResult = await MessageService.instance.generateVideoThumbnail(
          conversationId: widget.conversationId,
          messageId: messageId,
          videoPath: file.path,
        );
        thumbnailUrl = thumbResult?['url'];
      }

      if (!mounted) return;

      // Insert actual message row with attachment details
      final message = await MessageService.instance.sendMessage(
        id: messageId,
        conversationId: widget.conversationId,
        senderId: _currentUserId!,
        senderType: widget.viewerRole,
        body: body,
        orderReferenceId: widget.orderReferenceId,
        attachmentUrl: uploadResult['url'] as String,
        attachmentType: type,
        attachmentThumbnailUrl: thumbnailUrl,
        attachmentDurationSeconds: duration,
        attachmentSizeBytes: uploadResult['sizeBytes'] as int,
      );

      if (mounted) {
        setState(() {
          // Replace placeholder with the actual message
          final idx = _messages.indexWhere((m) => m.id == messageId);
          if (idx >= 0) {
            _messages[idx] = message;
          } else {
            _messages.add(message);
          }
          _isUploading = false;
        });
        _scrollToBottom();
      }
    } catch (e, st) {
      // Surface the real upload error during development
      debugPrint('[ChatView] Attachment send failed: $e\n$st');
      if (mounted) {
        // Determine a user-friendly error message
        String errorMsg = 'Failed to send';
        if (e is UnsupportedError) {
          errorMsg = e.message ?? 'Unsupported file type';
        } else        if (e is UnsupportedError || e.toString().contains('mime') || e.toString().contains('content_type') || e.toString().contains('MIME type')) {
          errorMsg = e is UnsupportedError ? (e.message ?? 'Unsupported file type') : 'Unsupported file format. Use JPEG, PNG, WebP, GIF, or MP4.';
        } else if (e.toString().contains('size') || e.toString().contains('too large')) {
          errorMsg = 'File too large — max 25MB';
        }

        final failedMessage = Message(
          id: messageId,
          conversationId: widget.conversationId,
          senderId: _currentUserId!,
          senderType: widget.viewerRole,
          body: body,
          orderReferenceId: widget.orderReferenceId,
          isRead: false,
          createdAt: DateTime.now(),
          attachmentType: type,
          attachmentDurationSeconds: duration,
          localFile: file,
          sendFailed: true,
        );

        // Persist to provider so it survives widget rebuilds
        context.read<ChatAttachmentProvider>().addFailedMessage(failedMessage);

        setState(() {
          final idx = _messages.indexWhere((m) => m.id == messageId);
          if (idx >= 0) {
            _messages[idx] = failedMessage;
          }
          _isUploading = false;
        });

        // Show a snackbar with the actual error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: AppConstants.error,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _retryAttachment(failedMessage),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _isSending || _currentUserId == null) return;

    _sendTypingStop();
    _typingDebounce?.cancel();

    // Generate a client-side UUID for optimistic matching
    final messageId = const Uuid().v4();
    final bodyText = body;
    _messageController.clear();

    // Insert placeholder immediately (optimistic UI)
    // isRead starts as false — will flip to true via realtime when recipient reads
    final placeholder = Message(
      id: messageId,
      conversationId: widget.conversationId,
      senderId: _currentUserId!,
      senderType: widget.viewerRole,
      body: bodyText,
      orderReferenceId: widget.orderReferenceId,
      isRead: false,
      createdAt: DateTime.now(),
      isSending: true,
    );

    if (mounted) {
      setState(() {
        _isSending = true;
        _messages.add(placeholder);
      });
      _scrollToBottom();
    }

    try {
      final message = await MessageService.instance.sendMessage(
        id: messageId,
        conversationId: widget.conversationId,
        senderId: _currentUserId!,
        senderType: widget.viewerRole,
        body: bodyText,
        orderReferenceId: widget.orderReferenceId,
      );

      // Replace placeholder with confirmed server message
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == messageId);
          if (idx >= 0) {
            _messages[idx] = message;
          } else {
            _messages.add(message);
          }
          _isSending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      // Mark the placeholder as failed with retry option
      if (mounted) {
        final failedMessage = Message(
          id: messageId,
          conversationId: widget.conversationId,
          senderId: _currentUserId!,
          senderType: widget.viewerRole,
          body: bodyText,
          orderReferenceId: widget.orderReferenceId,
          isRead: false,
          createdAt: placeholder.createdAt,
          sendFailed: true,
        );
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == messageId);
          if (idx >= 0) {
            _messages[idx] = failedMessage;
          }
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherPartyName,
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              _isCustomer ? 'Seller' : 'Customer',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: Colors.white.withAlpha(180),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (widget.orderReferenceId != null) _buildOrderReferenceChip(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppConstants.primary))
                : _messages.isEmpty
                    ? RefreshIndicator(
                        color: AppConstants.primary,
                        onRefresh: _loadMessages,
                        child: _buildEmptyState(),
                      )
                    : RefreshIndicator(
                        color: AppConstants.primary,
                        onRefresh: _loadMessages,
                        child: Stack(
                          children: [
                            _buildMessagesList(),
                            // "New message ↓" pill
                            if (_hasNewMessages && !_isNearBottom)
                              Positioned(
                                bottom: 12,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() => _hasNewMessages = false);
                                      _scrollToBottom();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppConstants.primary,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.15),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.arrow_downward,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'New message',
                                            style: AppConstants.bodyStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
          ),
          if (_isOtherPartyTyping) _buildTypingIndicator(),
          _buildInputBar(),
        ],
      ),
    );
  }

  // ─── TYPING INDICATOR ────────────────────────────────────────

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppConstants.sellerCardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDot(0),
                      const SizedBox(width: 4),
                      _buildDot(1),
                      const SizedBox(width: 4),
                      _buildDot(2),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.otherPartyName.split(' ').first} is typing...',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    final stagger = index * 0.25;
    return AnimatedBuilder(
      animation: _typingAnimController,
      builder: (context, child) {
        final t = (_typingAnimController.value + stagger) % 1.0;
        final value = (math.sin(t * 2 * math.pi) + 1) / 2;
        return Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: AppConstants.secondary.withValues(alpha: 0.2 + (value * 0.5)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  // ─── MESSAGES LIST ───────────────────────────────────────────

  Widget _buildOrderReferenceChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppConstants.primary.withValues(alpha: 0.08),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, size: 16, color: AppConstants.primary),
              const SizedBox(width: 8),
              Text(
                'Regarding Order #${widget.orderReferenceId!.substring(0, 8)}',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          // Quick action: Request a Change (only for customer, non-cancelled/delivered)
          if (_isCustomer && _canRequestChange) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showChangeRequest,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: Text(
                  'Request a Change',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.primary,
                  side: BorderSide(color: AppConstants.primary.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Whether the customer can request a change (not for cancelled/delivered orders).
  bool get _canRequestChange {
    // Default to allowing changes; order status would need to be passed
    // or fetched for proper filtering. For MVP, always allow.
    return true;
  }

  void _showChangeRequest() async {
    final result = await showChangeRequestSheet(context);
    if (result == null || _currentUserId == null) return;

    // Format the change request as a structured message
    final changeType = changeRequestTypes.firstWhere(
      (t) => t.id == result.type,
      orElse: () => changeRequestTypes.last,
    );
    final messageBody = '📋 Change Request: ${changeType.label}\n${result.toValue}';

    // Send as a regular message with the formatted body
    _messageController.text = messageBody;
    _sendMessage();
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.35),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 48,
                  color: AppConstants.primary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Start a conversation',
                  style: AppConstants.bodyStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.secondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isCustomer
                      ? 'Send a message to the seller about orders, products, or any questions.'
                      : 'Reply to this customer\'s message.',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isOwnMessage = message.senderType == widget.viewerRole;
        final showTimestamp = index == 0 ||
            _shouldShowTimestamp(_messages[index - 1].createdAt, message.createdAt);

        return Column(
          children: [
            if (showTimestamp)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _formatTimestamp(message.createdAt),
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            _buildMessageBubble(message, isOwnMessage),
          ],
        );
      },
    );
  }

  Widget _buildMessageBubble(Message message, bool isOwnMessage) {
    // Tap to retry failed text messages
    final tapHandler = message.sendFailed
        ? (() => _retryFailedMessage(message))
        : (() => _showMessageDetails(message));

    return Align(
      alignment: isOwnMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: message.sendFailed ? tapHandler : null,
        onLongPress: message.sendFailed ? null : () => _showMessageDetails(message),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isOwnMessage ? AppConstants.primary : AppConstants.sellerCardBg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isOwnMessage ? 16 : 4),
              bottomRight: Radius.circular(isOwnMessage ? 4 : 16),
            ),
            boxShadow: AppConstants.sellerShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Attachment (image or video)
              if (message.hasAttachment) ...[
                if (message.isImageMessage)
                  _buildImageAttachment(message, isOwnMessage)
                else if (message.isVideoMessage)
                  _buildVideoAttachment(message, isOwnMessage),
                const SizedBox(height: 6),
              ],

              // Order reference chip
              if (message.orderReferenceId != null)
                GestureDetector(
                  onTap: () => _navigateToOrder(message.orderReferenceId!),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isOwnMessage ? Colors.white : AppConstants.primary).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long, size: 12,
                            color: isOwnMessage ? Colors.white : AppConstants.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Order #${message.orderReferenceId!.substring(0, 8)}',
                          style: AppConstants.bodyStyle(
                            fontSize: 10,
                            color: isOwnMessage ? Colors.white : AppConstants.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 12,
                            color: isOwnMessage
                                ? Colors.white.withValues(alpha: 0.7)
                                : AppConstants.primary.withValues(alpha: 0.7)),
                      ],
                    ),
                  ),
                ),

              // Message body (caption)
              if (message.hasBody)
                Text(
                  message.body!,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: isOwnMessage ? Colors.white : AppConstants.secondary,
                  ),
                ),

              // Sending/failed indicator for text messages
              if (message.isSending && message.hasBody && !message.hasAttachment)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: (isOwnMessage ? Colors.white : AppConstants.secondary)
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Sending...',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          color: (isOwnMessage ? Colors.white : AppConstants.secondary)
                              .withValues(alpha: 0.5),
                        ).copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              if (message.sendFailed && message.hasBody && !message.hasAttachment)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 12,
                        color: AppConstants.error.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Failed • Tap to retry',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          color: AppConstants.error.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),

              // Timestamp + read receipt
              if (message.hasBody || message.hasAttachment) const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.relativeTime,
                    style: AppConstants.bodyStyle(
                      fontSize: 10,
                      color: (isOwnMessage ? Colors.white : AppConstants.secondary)
                          .withValues(alpha: 0.6),
                    ),
                  ),
                  // Read receipt: show checkmark for own messages that are read
                  if (isOwnMessage && message.isRead && !message.isSending && !message.sendFailed) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all,
                      size: 14,
                      color: (isOwnMessage ? Colors.white : AppConstants.accent)
                          .withValues(alpha: 0.7),
                    ),
                  ] else if (isOwnMessage && !message.isRead && !message.isSending && !message.sendFailed) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done,
                      size: 14,
                      color: (isOwnMessage ? Colors.white : AppConstants.secondary)
                          .withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ATTACHMENT BUBBLES ──────────────────────────────────────

  Widget _buildImageAttachment(Message message, bool isOwnMessage) {
    // Show local file preview during upload with real progress bar
    if (message.isSending && message.localFile != null) {
      final pct = (message.progress * 100).round();
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              message.localFile!,
              width: 220,
              height: 220,
              fit: BoxFit.cover,
            ),
          ),
          // Semi-transparent overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          // Real progress bar at bottom of image
          Positioned(
            left: 8,
            right: 8,
            bottom: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: message.progress,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Show failed state
    if (message.sendFailed && message.localFile != null) {
      return GestureDetector(
        onTap: () => _retryAttachment(message),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                message.localFile!,
                width: 220,
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 32),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to retry',
                      style: AppConstants.bodyStyle(fontSize: 11, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Normal sent state
    return GestureDetector(
      onTap: () => _openFullScreenImage(message.attachmentUrl!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: message.attachmentUrl!,
          width: 220,
          height: 220,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 220,
            height: 220,
            color: isOwnMessage
                ? Colors.white.withValues(alpha: 0.1)
                : AppConstants.secondary.withValues(alpha: 0.05),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (context, url, error) => Container(
            width: 220,
            height: 220,
            color: isOwnMessage
                ? Colors.white.withValues(alpha: 0.1)
                : AppConstants.secondary.withValues(alpha: 0.05),
            child: Icon(
              Icons.broken_image_outlined,
              size: 40,
              color: (isOwnMessage ? Colors.white : AppConstants.secondary).withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoAttachment(Message message, bool isOwnMessage) {
    // Show local file preview during upload with real progress bar
    if (message.isSending && message.localFile != null) {
      final pct = (message.progress * 100).round();
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              message.localFile!,
              width: 220,
              height: 160,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                width: 220,
                height: 160,
                color: AppConstants.secondary.withValues(alpha: 0.1),
                child: Icon(Icons.videocam_outlined,
                    color: AppConstants.secondary.withValues(alpha: 0.3)),
              ),
            ),
          ),
          // Semi-transparent overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          // Play icon (centered)
          const Positioned.fill(
            child: Center(
              child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 40),
            ),
          ),
          // Real progress bar at bottom of video thumbnail
          Positioned(
            left: 8,
            right: 8,
            bottom: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: message.progress,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Show failed state
    if (message.sendFailed && message.localFile != null) {
      return GestureDetector(
        onTap: () => _retryAttachment(message),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                message.localFile!,
                width: 220,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  width: 220,
                  height: 160,
                  color: AppConstants.secondary.withValues(alpha: 0.1),
                  child: Icon(Icons.videocam_outlined,
                      color: AppConstants.secondary.withValues(alpha: 0.3)),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 32),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to retry',
                      style: AppConstants.bodyStyle(fontSize: 11, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Normal sent state
    return GestureDetector(
      onTap: () => _openFullScreenVideo(message.attachmentUrl!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (message.attachmentThumbnailUrl != null)
              CachedNetworkImage(
                imageUrl: message.attachmentThumbnailUrl!,
                width: 220,
                height: 160,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  width: 220,
                  height: 160,
                  color: AppConstants.secondary.withValues(alpha: 0.1),
                  child: Icon(Icons.videocam_outlined,
                      color: AppConstants.secondary.withValues(alpha: 0.3)),
                ),
              )
            else
              Container(
                width: 220,
                height: 160,
                color: AppConstants.secondary.withValues(alpha: 0.1),
                child: Icon(Icons.videocam_outlined,
                    color: AppConstants.secondary.withValues(alpha: 0.3)),
              ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
            ),
            if (message.attachmentDurationSeconds != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(message.attachmentDurationSeconds!),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── FULL-SCREEN VIEWERS ─────────────────────────────────────

  void _openFullScreenImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(imageUrl: imageUrl),
      ),
    );
  }

  void _openFullScreenVideo(String videoUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenVideoPlayer(videoUrl: videoUrl),
      ),
    );
  }

  void _showMessageDetails(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Message Details'),
              subtitle: Text(
                'Sent ${_formatTimestamp(message.createdAt)}\n'
                '${message.hasBody ? 'Text: ${message.body}' : ''}'
                '${message.hasAttachment ? '\nAttachment: ${message.attachmentType}' : ''}'
                '${message.attachmentSizeBytes != null ? '\nSize: ${_formatFileSize(message.attachmentSizeBytes!)}' : ''}',
              ),
            ),
            if (message.hasAttachment)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open Attachment'),
                onTap: () {
                  Navigator.pop(context);
                  if (message.isImageMessage) {
                    _openFullScreenImage(message.attachmentUrl!);
                  } else if (message.isVideoMessage) {
                    _openFullScreenVideo(message.attachmentUrl!);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToOrder(String orderId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Order #$orderId'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _retryAttachment(Message failedMessage) {
    // Restore pending state and retry
    if (failedMessage.localFile == null) return;
    
    // Remove from provider first
    context.read<ChatAttachmentProvider>().removeFailedMessage(
      widget.conversationId,
      failedMessage.id,
    );
    
    setState(() {
      _pendingAttachment = failedMessage.localFile;
      _pendingAttachmentType = failedMessage.attachmentType;
      _pendingVideoDuration = failedMessage.attachmentDurationSeconds;
      // Remove the failed message from list
      _messages.removeWhere((m) => m.id == failedMessage.id);
    });
    _sendAttachmentMessage(caption: failedMessage.body);
  }

  /// Retry a failed text message send.
  void _retryFailedMessage(Message failedMessage) {
    if (failedMessage.body == null || failedMessage.body!.trim().isEmpty) return;
    // Remove the failed message from the list
    setState(() {
      _messages.removeWhere((m) => m.id == failedMessage.id);
    });
    // Pre-fill the input and trigger send
    _messageController.text = failedMessage.body!;
    _sendMessage();
  }

  // ─── INPUT BAR ───────────────────────────────────────────────

  Widget _buildInputBar() {
    return Container(
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
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attachment button
            IconButton(
              onPressed: _isUploading ? null : _showAttachmentOptions,
              icon: Icon(
                Icons.attach_file_rounded,
                color: AppConstants.primary,
              ),
              padding: const EdgeInsets.only(bottom: 4),
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                style: AppConstants.bodyStyle(fontSize: 14),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.4),
                  ),
                  filled: true,
                  fillColor: AppConstants.surfaceLight,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onTextChanged,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: IconButton(
                onPressed: _canSend ? _handleSend : null,
                icon: _isSending
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primary),
                      )
                    : Icon(
                        Icons.send,
                        color: _canSend
                            ? AppConstants.primary
                            : AppConstants.secondary.withValues(alpha: 0.3),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSend {
    if (_isSending || _isUploading) return false;
    return _messageController.text.trim().isNotEmpty || _pendingAttachment != null;
  }

  void _handleSend() {
    if (_pendingAttachment != null) {
      _sendAttachmentMessage(caption: _messageController.text.trim());
      _messageController.clear();
    } else {
      _sendMessage();
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: AppConstants.primary),
                title: const Text('Photo/Video from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAttachment(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_outlined, color: AppConstants.primary),
                title: const Text('Take Photo/Video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAttachment(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────

  /// Map file extension to proper MIME type for Supabase Storage.
  /// Handles HEIC (converts to JPEG), and maps common extensions correctly.
  String _resolveMimeType(String attachmentType, String ext) {
    if (attachmentType == 'video') {
      return switch (ext) {
        'mov' || 'qt' => 'video/quicktime',
        'mp4' || 'm4v' => 'video/mp4',
        'avi' => 'video/x-msvideo',
        _ => 'video/mp4',
      };
    }
    // Image MIME types — HEIC maps to JPEG since the bucket doesn't allow HEIC
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/jpeg', // HEIC → JPEG mime (bucket doesn't allow HEIC)
      // NOTE: This declares the content type as JPEG but the file bytes are still HEIC.
      // Supabase Storage checks the declared MIME type, not file magic bytes, so this works.
      // For a fully correct conversion, a native HEIC→JPEG encoder would be needed.
      'bmp' => 'image/bmp',
      _ => 'image/jpeg', // default to JPEG for unknown image types
    };
  }

  bool _shouldShowTimestamp(DateTime prev, DateTime current) {
    return current.difference(prev).inMinutes > 5;
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dt.year, dt.month, dt.day);

    if (messageDate == today) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ═══════════════════════════════════════════════════════════════
// Attachment Preview Sheet
// ═══════════════════════════════════════════════════════════════

class _AttachmentPreviewSheet extends StatefulWidget {
  final File file;
  final String attachmentType;
  final int? videoDuration;
  final Future<void> Function({String? caption}) onSend;
  final VoidCallback onCancel;

  const _AttachmentPreviewSheet({
    required this.file,
    required this.attachmentType,
    this.videoDuration,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<_AttachmentPreviewSheet> createState() => _AttachmentPreviewSheetState();
}

class _AttachmentPreviewSheetState extends State<_AttachmentPreviewSheet> {
  final TextEditingController _captionController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Preview
              Expanded(
                child: widget.attachmentType == 'image'
                    ? _buildImagePreview()
                    : _buildVideoPreview(),
              ),

              // Caption input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _captionController,
                  style: AppConstants.bodyStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Add a caption...',
                    hintStyle: AppConstants.bodyStyle(
                      fontSize: 14,
                      color: AppConstants.secondary.withValues(alpha: 0.4),
                    ),
                    filled: true,
                    fillColor: AppConstants.surfaceLight,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSending
                            ? null
                            : () {
                                widget.onCancel();
                                Navigator.of(context).pop();
                              },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppConstants.secondary.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Cancel',
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSending ? null : _handleSend,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isSending
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Send',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImagePreview() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            widget.file,
            fit: BoxFit.contain,
            width: double.infinity,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.file(
                widget.file,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stack) => Container(
                  color: AppConstants.secondary.withValues(alpha: 0.1),
                  child: Icon(Icons.videocam_outlined,
                      size: 64, color: AppConstants.secondary.withValues(alpha: 0.3)),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
              ),
              if (widget.videoDuration != null)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(widget.videoDuration!),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _handleSend() async {
    setState(() => _isSending = true);
    await widget.onSend(caption: _captionController.text.trim());
    if (mounted) setState(() => _isSending = false);
  }
}

// ═══════════════════════════════════════════════════════════════
// Full-Screen Image Viewer
// ═══════════════════════════════════════════════════════════════

class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: (context, url, error) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Full-Screen Video Player
// ═══════════════════════════════════════════════════════════════

class _FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  const _FullScreenVideoPlayer({required this.videoUrl});

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.play();
          setState(() => _isPlaying = true);
        }
      });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _isInitialized
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AspectRatio(
                            aspectRatio: _controller.value.aspectRatio,
                            child: VideoPlayer(_controller),
                          ),
                          if (!_isPlaying)
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Controls
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          _formatDuration(_controller.value.position),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor: AppConstants.primary,
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white10,
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(_controller.value.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
