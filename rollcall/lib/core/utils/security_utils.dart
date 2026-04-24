import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SecurityUtils {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Retrieves a unique ID for the specific device hardware.
  static Future<String> getUniqueDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        // androidId is generally stable across app re-installs.
        return androidInfo.id; 
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'ios_unknown_device';
      }
      return 'unknown_platform_device';
    } catch (e) {
      return 'error_retrieving_device_id';
    }
  }

  /// Generates a time-based token (rotating every 30s) for beacon security.
  /// Used to prevent "buddy reporting" by requiring proximity at a specific moment.
  static String generateTimeToken(String secret, {int intervalSeconds = 30}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ (intervalSeconds * 1000);
    final key = utf8.encode('$secret-$timestamp');
    final hash = sha256.convert(key);
    
    // Using a portion of the hash for the beacon Minor ID (which must be an int 0-65535)
    // We take the last 2 bytes for simplicity
    final bytes = hash.bytes;
    final int value = (bytes[bytes.length - 1] << 8) | bytes[bytes.length - 2];
    return (value % 65535).toString();
  }

  /// Verifies if a sent token is valid for the current or previous time window.
  static bool verifyTimeToken(String secret, String sentToken, {int intervalSeconds = 30}) {
    final current = generateTimeToken(secret, intervalSeconds: intervalSeconds);
    
    // Also check the previous window to account for network latency
    final previousTimestamp = (DateTime.now().millisecondsSinceEpoch ~/ (intervalSeconds * 1000)) - 1;
    final prevKey = utf8.encode('$secret-$previousTimestamp');
    final prevHash = sha256.convert(prevKey);
    final prevBytes = prevHash.bytes;
    final int prevValue = (prevBytes[prevBytes.length - 1] << 8) | prevBytes[prevBytes.length - 2];
    final prev = (prevValue % 65535).toString();

    return sentToken == current || sentToken == prev;
  }
}
