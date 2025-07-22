// lib/services/webrtc_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebRTCService {
  // Use a public STUN server for testing
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]
  };

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  // This will hold the local video feed
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  // Initialize the service
  Future<void> initialize() async {
    await localRenderer.initialize();
  }

  // A method to clean up resources
  Future<void> dispose() async {
    await _localStream?.dispose();
    await _peerConnection?.close();
    await localRenderer.dispose();
  }

  // The main function to initiate the call
  Future<void> initiateCall({
    required String chatId,
    required bool isVideoCall,
  }) async {
    // 1. Request Permissions
    await _requestPermissions(isVideoCall);

    // 2. Create Peer Connection
    _peerConnection = await createPeerConnection(_iceServers);

    // 3. Get local media stream (audio/video)
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideoCall,
    });

    // Set the local video renderer's stream
    localRenderer.srcObject = _localStream;

    // 4. Add local stream tracks to the peer connection
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // 5. Create an SDP Offer
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // 6. Send the offer to the backend
    await _sendCallRequest(chatId: chatId, offer: offer);
  }

  Future<void> _requestPermissions(bool isVideo) async {
    if (isVideo) {
      await [Permission.camera, Permission.microphone].request();
    } else {
      await Permission.microphone.request();
    }
  }

  // The API call to your Laravel backend
  Future<void> _sendCallRequest({
    required String chatId,
    required RTCSessionDescription offer,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      throw Exception('Authentication Token not found.');
    }

    final response = await http.post(
      // IMPORTANT: Use your actual endpoint for calling
      Uri.parse('http://127.0.0.1:8000/api/webrtc/call-user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        // Your backend expects an integer for chat_id
        'chat_id': int.tryParse(chatId) ?? 0,
        // The offer needs to be converted to a map
        'offer': offer.toMap(),
      }),
    );

    if (response.statusCode == 200) {
      debugPrint('Call initiated successfully');
      // Here you would typically wait for an "answer" from the other user
      // via your websocket (e.g., Laravel Echo)
    } else {
      debugPrint('API Error: ${response.body}');
      throw Exception('Failed to initiate call. Status: ${response.statusCode}');
    }
  }
}