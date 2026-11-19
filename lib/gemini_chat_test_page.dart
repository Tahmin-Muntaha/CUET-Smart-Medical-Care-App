import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';

// ============================================================================
// GEMINI CHAT TEST PAGE
//
// File:
// lib/gemini_chat_test_page.dart
//
// Purpose:
// Tests Firebase AI Logic + Gemini end-to-end.
//
// Features:
// - Gemini 3.8 Flash
// - Multi-turn chat
// - 30-second timeout
// - Automatic retry for temporary 503 errors
// - Detailed console logging
// - Error messages shown inside the app
// ============================================================================

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;

  _ChatMessage(
    this.text, {
    required this.isUser,
    this.isError = false,
  });
}

class GeminiChatTestPage extends StatefulWidget {
  const GeminiChatTestPage({super.key});

  @override
  State<GeminiChatTestPage> createState() => _GeminiChatTestPageState();
}

class _GeminiChatTestPageState extends State<GeminiChatTestPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [];

  ChatSession? _chatSession;

  bool _isLoading = false;
  bool _isInitializing = true;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  // ==========================================================================
  // INITIALIZE GEMINI
  // ==========================================================================

  Future<void> _initChat() async {
    try {
      debugPrint('==========================================');
      debugPrint('Initializing Firebase AI Logic...');
      debugPrint('Model: gemini-3.5-flash-lite');
      debugPrint('==========================================');

      final model = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-3.5-flash-lite',
      );

      _chatSession = model.startChat();

      if (!mounted) return;

      setState(() {
        _isInitializing = false;
        _initError = null;
      });

      debugPrint('Gemini model initialized successfully.');
      debugPrint('Ready to send messages.');
    } catch (e, stackTrace) {
      debugPrint('==========================================');
      debugPrint('GEMINI INITIALIZATION ERROR');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('==========================================');

      if (!mounted) return;

      setState(() {
        _isInitializing = false;
        _initError = e.toString();
      });
    }
  }

  // ==========================================================================
  // SEND MESSAGE
  // ==========================================================================

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      return;
    }

    if (_chatSession == null) {
      _showErrorMessage(
        'Gemini is not initialized yet.',
      );
      return;
    }

    if (_isLoading) {
      return;
    }

    // Add user message to the chat.
    setState(() {
      _messages.add(
        _ChatMessage(
          text,
          isUser: true,
        ),
      );

      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom();

    try {
      debugPrint('==========================================');
      debugPrint('Sending message to Gemini...');
      debugPrint('Message: $text');
      debugPrint('==========================================');

      GenerateContentResponse? response;

      // ----------------------------------------------------------------------
      // RETRY TEMPORARY 503 ERRORS
      // ----------------------------------------------------------------------

      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          debugPrint(
            'Gemini request attempt $attempt/3',
          );

          response = await _chatSession!
              .sendMessage(
                Content.text(text),
              )
              .timeout(
                const Duration(seconds: 30),
              );

          // Request succeeded.
          break;
        } catch (e, stackTrace) {
          debugPrint(
            'Gemini attempt $attempt failed.',
          );
          debugPrint('Error: $e');
          debugPrint('Stack trace: $stackTrace');

          final errorText = e.toString();

          final isTemporaryServerError =
              errorText.contains('503') ||
              errorText.contains('UNAVAILABLE') ||
              errorText.contains('Deadline expired');

          // If this isn't a temporary 503 error,
          // don't retry it.
          if (!isTemporaryServerError || attempt == 3) {
            rethrow;
          }

          // Wait longer after each failed attempt.
          final waitSeconds = attempt * 2;

          debugPrint(
            'Temporary server error detected. '
            'Retrying in $waitSeconds seconds...',
          );

          await Future.delayed(
            Duration(seconds: waitSeconds),
          );
        }
      }

      final reply = response?.text;

      debugPrint('==========================================');
      debugPrint('Gemini response received.');
      debugPrint('Response: $reply');
      debugPrint('==========================================');

      if (!mounted) return;

      setState(() {
        _isLoading = false;

        if (reply == null || reply.trim().isEmpty) {
          _messages.add(
            _ChatMessage(
              'Gemini connected, but returned an empty response.',
              isUser: false,
              isError: true,
            ),
          );
        } else {
          _messages.add(
            _ChatMessage(
              reply,
              isUser: false,
            ),
          );
        }
      });
    } catch (e, stackTrace) {
      debugPrint('==========================================');
      debugPrint('GEMINI REQUEST FAILED');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('==========================================');

      if (!mounted) return;

      String errorMessage;

      if (e is TimeoutException) {
        errorMessage =
            'Gemini did not respond within 30 seconds.\n\n'
            'The request timed out. Please try again.';
      } else {
        final errorText = e.toString();

        if (errorText.contains('503') ||
            errorText.contains('UNAVAILABLE') ||
            errorText.contains('Deadline expired')) {
          errorMessage =
              'Gemini is temporarily unavailable.\n\n'
              'The Firebase server returned a 503 '
              'UNAVAILABLE error.\n\n'
              'Please try again in a few seconds.';
        } else {
          errorMessage =
              'Gemini request failed.\n\n'
              '$e';
        }
      }

      setState(() {
        _isLoading = false;

        _messages.add(
          _ChatMessage(
            errorMessage,
            isUser: false,
            isError: true,
          ),
        );
      });
    }

    _scrollToBottom();
  }

  // ==========================================================================
  // SHOW ERROR
  // ==========================================================================

  void _showErrorMessage(String message) {
    if (!mounted) return;

    setState(() {
      _messages.add(
        _ChatMessage(
          message,
          isUser: false,
          isError: true,
        ),
      );
    });

    _scrollToBottom();
  }

  // ==========================================================================
  // SCROLL TO BOTTOM
  // ==========================================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ==========================================================================
  // DISPOSE
  // ==========================================================================

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // BUILD UI
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final bool isReady =
        !_isInitializing &&
        _initError == null &&
        _chatSession != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      // ----------------------------------------------------------------------
      // APP BAR
      // ----------------------------------------------------------------------

      appBar: AppBar(
        backgroundColor: const Color(0xFF003D9B),
        foregroundColor: Colors.white,
        title: const Text(
          'Gemini Connection Test',
        ),
      ),

      // ----------------------------------------------------------------------
      // BODY
      // ----------------------------------------------------------------------

      body: Column(
        children: [
          // ==================================================================
          // CONNECTION STATUS
          // ==================================================================

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 16,
            ),
            color: _isInitializing
                ? Colors.grey.shade200
                : (_initError != null
                    ? const Color(0xFFFFF2F2)
                    : const Color(0xFFEAF7EA)),
            child: Row(
              children: [
                Icon(
                  _isInitializing
                      ? Icons.hourglass_top
                      : (_initError != null
                          ? Icons.error_outline
                          : Icons.check_circle_outline),
                  size: 18,
                  color: _isInitializing
                      ? Colors.grey.shade700
                      : (_initError != null
                          ? Colors.red
                          : Colors.green.shade700),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    _isInitializing
                        ? 'Initializing Gemini via Firebase AI Logic...'
                        : (_initError != null
                            ? 'Initialization failed: $_initError'
                            : 'Model initialized. Send a message to test the full round trip.'),
                    style: TextStyle(
                      fontSize: 12,
                      color: _isInitializing
                          ? Colors.grey.shade700
                          : (_initError != null
                              ? Colors.red.shade700
                              : Colors.green.shade800),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ==================================================================
          // MESSAGE LIST
          // ==================================================================

          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Send a message below.\n\n'
                        'For example:\n'
                        '"Hello Gemini, are you working?"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF737685),
                          height: 1.5,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];

                      return Align(
                        alignment: msg.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(
                            bottom: 10,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            color: msg.isError
                                ? const Color(0xFFFFE5E5)
                                : msg.isUser
                                    ? const Color(0xFF003D9B)
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: msg.isUser || msg.isError
                                ? null
                                : Border.all(
                                    color: const Color(0xFFC3C6D6),
                                  ),
                          ),
                          child: Text(
                            msg.text,
                            style: TextStyle(
                              color: msg.isError
                                  ? Colors.red.shade900
                                  : msg.isUser
                                      ? Colors.white
                                      : const Color(0xFF111C2D),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // ==================================================================
          // LOADING INDICATOR
          // ==================================================================

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(
                bottom: 8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Waiting for Gemini response...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF737685),
                    ),
                  ),
                ],
              ),
            ),

          // ==================================================================
          // INPUT ROW
          // ==================================================================

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                12,
                8,
                12,
                12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,

                      enabled: isReady && !_isLoading,

                      textInputAction: TextInputAction.send,

                      decoration: InputDecoration(
                        hintText: 'Type a test message...',
                        filled: true,
                        fillColor: Colors.white,

                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Color(0xFFC3C6D6),
                          ),
                        ),
                      ),

                      onSubmitted: (_) {
                        _sendMessage();
                      },
                    ),
                  ),

                  const SizedBox(width: 8),

                  IconButton(
                    onPressed: !isReady || _isLoading
                        ? null
                        : _sendMessage,

                    icon: const Icon(
                      Icons.send,
                    ),

                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF003D9B),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          Colors.grey.shade300,
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
}