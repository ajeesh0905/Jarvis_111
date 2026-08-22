import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum VoiceState { idle, listening, wakeListening, speaking, error }

/// Wraps speech-to-text and text-to-speech, plus a simple "wake word"
/// loop that keeps re-listening for the word "jarvis" while the toggle
/// is on and the app is in the foreground.
///
/// IMPORTANT HONEST LIMITATION: this is *foreground* wake-word detection.
/// Android does not let a normal app keep the microphone hot-listening
/// with the screen off / app fully backgrounded without a dedicated
/// on-device wake-word engine (e.g. Picovoice Porcupine) running in a
/// foreground service with its own wake lock — that needs a (free-tier)
/// Picovoice account and access key. This service is structured so you
/// can drop that in later (see README "Real always-on wake word").
class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttReady = false;
  bool _wakeLoopActive = false;

  final _stateController = StreamController<VoiceState>.broadcast();
  Stream<VoiceState> get stateStream => _stateController.stream;
  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  void _setState(VoiceState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> init() async {
    if (_sttReady) return true;
    if (!await _ensureMicPermission()) return false;
    _sttReady = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (_state == VoiceState.listening) _setState(VoiceState.idle);
        }
      },
      onError: (e) {
        // The recognizer fires onError constantly during normal use —
        // e.g. "error_no_match" / "error_speech_timeout" every time a
        // listen window ends without hearing anything, which happens on
        // essentially every wake-loop cycle. Those are expected and not
        // a real problem, so only surface a "Mic error" for errors the
        // plugin itself flags as permanent (e.g. missing recognizer,
        // permission revoked) — transient ones just drop back to idle
        // so the badge doesn't get stuck showing an error forever.
        if (e.permanent) {
          _setState(VoiceState.error);
        } else if (_state == VoiceState.listening ||
            _state == VoiceState.wakeListening) {
          _setState(VoiceState.idle);
        }
      },
    );
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    if (_sttReady && _state == VoiceState.error) {
      // Recovered — clear any stale error state from a previous session.
      _setState(VoiceState.idle);
    }
    return _sttReady;
  }

  /// Tap-to-talk: listens once, returns the recognized text (or null).
  Future<String?> listenOnce({Duration timeout = const Duration(seconds: 8)}) async {
    if (!await init()) return null;
    final completer = Completer<String?>();
    _setState(VoiceState.listening);
    await _speech.listen(
      listenFor: timeout,
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
      onResult: (result) {
        if (result.finalResult && !completer.isCompleted) {
          _setState(VoiceState.idle);
          completer.complete(result.recognizedWords);
        }
      },
    );
    // Safety timeout in case onResult never fires a final result.
    Future.delayed(timeout + const Duration(seconds: 2), () {
      if (!completer.isCompleted) {
        _speech.stop();
        _setState(VoiceState.idle);
        completer.complete(null);
      }
    });
    return completer.future;
  }

  Future<void> speak(String text) async {
    _setState(VoiceState.speaking);
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(text);
    _setState(VoiceState.idle);
  }

  Future<void> stopSpeaking() => _tts.stop();

  /// Starts a foreground loop that keeps listening for short phrases and
  /// calls [onWake] whenever "jarvis" is heard. Call [stopWakeLoop] to
  /// cancel. Safe to call repeatedly; it no-ops if already running.
  Future<void> startWakeLoop({required void Function() onWake}) async {
    if (_wakeLoopActive) return;
    if (!await init()) return;
    _wakeLoopActive = true;
    _runWakeCycle(onWake);
  }

  static const _wakeListenWindow = Duration(seconds: 6);

  Future<void> _runWakeCycle(void Function() onWake) async {
    while (_wakeLoopActive) {
      if (_state == VoiceState.speaking || _state == VoiceState.listening) {
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }
      _setState(VoiceState.wakeListening);
      var woke = false;
      try {
        await _speech.listen(
          listenFor: _wakeListenWindow,
          pauseFor: const Duration(seconds: 2),
          localeId: 'en_US',
          onResult: (result) {
            if (result.recognizedWords.toLowerCase().contains('jarvis')) {
              woke = true;
            }
          },
        );
      } catch (_) {
        // Transient recognizer error — just try again next cycle.
      }

      // `listen()` returns as soon as the session *starts*, not when it
      // finishes, so give it its full window before touching state again.
      await Future.delayed(_wakeListenWindow);
      await _speech.stop();
      if (_state == VoiceState.wakeListening) {
        _setState(VoiceState.idle);
      }

      if (woke && _wakeLoopActive) {
        onWake();
        // Let the resulting conversation turn (tap-to-talk style listen +
        // Gemini reply + TTS) play out before resuming wake listening.
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  void stopWakeLoop() {
    _wakeLoopActive = false;
    _speech.stop();
    if (_state == VoiceState.wakeListening) _setState(VoiceState.idle);
  }

  void dispose() {
    _wakeLoopActive = false;
    _speech.stop();
    _tts.stop();
    _stateController.close();
  }
}
