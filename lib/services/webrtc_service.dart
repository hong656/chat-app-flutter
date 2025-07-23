import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  // Callback to notify the UI when the remote stream is available
  void Function(MediaStream stream)? onRemoteStream;

  // Store chat ID for reuse in service methods
  String? _chatId;

  // --- Core Methods ---

  Future<void> initialize() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> _requestPermissions(bool isVideo) async {
    await (isVideo
        ? [Permission.camera, Permission.microphone]
        : [Permission.microphone])
        .request();
  }

  Future<void> _createPeerConnection() async {
    // Clean up any previous connection before creating a new one
    await _closeConnection();

    final Map<String, dynamic> iceServers = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(iceServers);

    // Listen for ICE candidates and send them to the other peer
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        _sendIceCandidate(candidate);
      }
    };

    // Listen for the remote stream
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
        // Notify the UI that the remote video is ready to be shown
        onRemoteStream?.call(_remoteStream!);
      }
    };
  }

  // --- API Communication ---

  Future<void> _sendToBackend(String endpoint, Map<String, dynamic> body) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) throw Exception('Auth token not found.');

    // IMPORTANT: Use 10.0.2.2 for Android Emulator to reach your PC's localhost
    final url = 'http://127.0.0.1:8000/api/webrtc/$endpoint';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode >= 300) {
        debugPrint('API Error to $endpoint: ${response.body}');
      }
    } catch (e) {
      debugPrint('Exception sending to $endpoint: $e');
    }
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    if (_chatId == null) return;
    await _sendToBackend('ice-candidate', {
      'chat_id': int.tryParse(_chatId!),
      'candidate': candidate.toMap(),
    });
  }

  // --- Public Methods for UI to Call ---

  Future<void> initiateCall({required String chatId, required bool isVideoCall}) async {
    _chatId = chatId;
    await _requestPermissions(isVideoCall);
    await _createPeerConnection();

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideoCall,
    });
    localRenderer.srcObject = _localStream;

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    print("=========================================");
    print("--- CALLER'S ORIGINAL OFFER SDP (to be sent) ---");
    print(offer.sdp);
    print("=========================================");

    await _sendToBackend('call-user', {
      'chat_id': int.tryParse(chatId),
      'offer': offer.toMap(),
    });
  }

  Future<void> acceptCallAndCreateAnswer({
    required String chatId,
    required RTCSessionDescription offer,
    required bool isVideoCall,
  }) async {
    _chatId = chatId;
    print("SERVICE: 1. Requesting permissions...");
    await _requestPermissions(isVideoCall);

    print("SERVICE: 2. Creating peer connection...");
    await _createPeerConnection();

    print("SERVICE: 3. Setting remote description (the offer)...");
    await _peerConnection!.setRemoteDescription(offer);

    print("SERVICE: 4. Getting local camera/mic stream...");
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideoCall,
    });
    localRenderer.srcObject = _localStream;

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });
    print("SERVICE: 5. Local stream added to peer connection.");

    print("SERVICE: 6. Creating answer...");
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    print("SERVICE: 7. Answer created and set as local description.");

    print("SERVICE: 8. Sending answer to backend...");
    await _sendToBackend('answer-call', {
      'chat_id': int.tryParse(chatId),
      'answer': answer.toMap(),
    });
    print("SERVICE: 9. Answer sent successfully.");
  }

  Future<void> setRemoteAnswer(RTCSessionDescription answer) async {
    await _peerConnection?.setRemoteDescription(answer);
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection?.addCandidate(candidate);
  }

  Future<void> hangUp() async {
    if (_chatId != null) {
      await _sendToBackend('end-call', {'chat_id': int.parse(_chatId!)});
    }
    await _closeConnection();
  }

  Future<void> _closeConnection() async {
    // Use a try-catch for each cleanup step to prevent one failure from stopping others
    try { _localStream?.getTracks().forEach((track) => track.stop()); } catch (e) { print("Error stopping local tracks: $e"); }
    try { await _localStream?.dispose(); } catch (e) { print("Error disposing local stream: $e"); }
    try { await _remoteStream?.dispose(); } catch (e) { print("Error disposing remote stream: $e"); }
    try { await _peerConnection?.close(); } catch (e) { print("Error closing peer connection: $e"); }

    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    _chatId = null;

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
  }

  Future<void> dispose() async {
    await _closeConnection();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}