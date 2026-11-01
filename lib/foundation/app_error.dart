import 'package:dio/dio.dart';
import 'package:venera/utils/translations.dart';

/// Presentation only: callers retain the original exception for diagnostics.
class AppErrorInfo {
  const AppErrorInfo(
    this.titleKey,
    this.messageKey, {
    this.canAutoRetry = false,
  });
  final String titleKey;
  final String messageKey;
  final bool canAutoRetry;
  String get title => titleKey.tl;
  String get message => messageKey.tl;

  static bool isTechnical(String text) =>
      statusCode(text) != null ||
      RegExp(
        r'HTTP\s+\d{3}|Exception|Bad state:|RangeError|NoSuchMethodError|Null check operator|Error:|TypeError|FormatError|StackTrace|Invalid status code|status code of|Cloudflare|key\(.+\) already exists|#\d+\s+|\bat .+\([^\n]+:\d+|\{.+\}|errno\s*=|XMLHttpRequest',
        caseSensitive: false,
      ).hasMatch(text) ||
      text.length > 300;

  static int? statusCode(Object error) {
    final raw = error.toString();
    if (RegExp(r'^\s*(?:HTTP\s*)?[45]\d{2}\s*$').hasMatch(raw)) {
      return int.parse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    }
    int? status = error is DioException ? error.response?.statusCode : null;
    return status ??
        int.tryParse(
          RegExp(
                r'(?:invalid\s+status\s+code\s*:?\s*|status\s+code\s+(?:of\s+)?|statuscode\s*[:=]\s*|http(?:\s+error)?\s+)(\d{3})\b',
                caseSensitive: false,
              ).firstMatch(raw)?.group(1) ??
              '',
        );
  }

  factory AppErrorInfo.from(Object error) {
    final raw = error.toString();
    final text = raw.toLowerCase();
    final status = statusCode(error);
    if (text.contains('requires an http proxy')) {
      return const AppErrorInfo(
        'Proxy configuration is unsupported',
        'Use an HTTP proxy server or switch to a direct connection in network settings.',
      );
    }
    if (text.contains('requires a newer android version')) {
      return const AppErrorInfo(
        'Extension is incompatible',
        'Update Android or choose an older version of this source extension.',
      );
    }
    if (text.contains('extension signature changed')) {
      return const AppErrorInfo(
        'Extension signature changed',
        'Use an update from the extension’s original repository.',
      );
    }
    if (text.contains('nosuchfieldexception') ||
        text.contains('nosuchfielderror')) {
      return const AppErrorInfo(
        'Source compatibility error',
        'Update Venera Z and try again.',
      );
    }
    if (text.contains('unsupported mihon extension api') ||
        text.contains('noclassdeffounderror') ||
        text.contains('nosuchmethoderror') ||
        text.contains('classnotfoundexception')) {
      return const AppErrorInfo(
        'Extension is incompatible',
        'Update Venera Z or the source extension, then try again.',
      );
    }
    if (text.contains('invalid extension apk') ||
        text.contains('not a mihon extension') ||
        text.contains('extension package does not match')) {
      return const AppErrorInfo(
        'Invalid source file',
        'Download the source again from its repository.',
      );
    }
    if (text.contains('cloudflare') &&
        (text.contains('exception') || text.contains('verification'))) {
      return const AppErrorInfo(
        'Website verification required',
        'The website requires a human verification. Tap Verify, complete it in the opened page, then return to continue.',
      );
    }
    if (RegExp(
      r'key\(.+\) already exists',
      caseSensitive: false,
    ).hasMatch(raw)) {
      return const AppErrorInfo(
        'This source is already installed',
        'Use Switch source library to change its provider. Your existing source does not need to be installed again.',
      );
    }
    if (text.contains('no space left') ||
        text.contains('disk full') ||
        text.contains('errno = 28')) {
      return const AppErrorInfo(
        'Not enough storage',
        'Free up storage on this device, then try again.',
      );
    }
    if (text.contains('permission denied') || text.contains('errno = 13')) {
      return const AppErrorInfo(
        'Cannot access this folder',
        'Grant file access or choose a folder the app can read and write.',
      );
    }
    if (text.contains('invalid webdav configuration')) {
      return const AppErrorInfo(
        'Sync settings are incomplete',
        'Check the WebDAV address, username and password in sync settings, then test the connection.',
      );
    }
    if (text.contains('no data file found')) {
      return const AppErrorInfo(
        'No cloud backup found',
        'Check the WebDAV folder address, or upload a backup from the device that has your data first.',
      );
    }
    if (text.contains('update checksum') ||
        text.contains('update download is incomplete') ||
        text.contains('update size mismatch') ||
        text.contains('unexpected update file')) {
      return const AppErrorInfo(
        'The update download could not be verified',
        'Download the update again. If verification still fails, download the APK from the app release page.',
      );
    }
    if (status == 401 ||
        text.contains('login expired') ||
        text == 'not login') {
      return const AppErrorInfo(
        'Sign-in required',
        'Your sign-in may have expired. Sign in again; for WebDAV, check the saved username and password.',
      );
    }
    if (status == 402) {
      return const AppErrorInfo(
        'Access restricted by the website',
        'The website has restricted access to this content. Open the website to check your sign-in, reading allowance and access rights, then try again.',
      );
    }
    if (status == 403) {
      return const AppErrorInfo(
        'The website refused access',
        'Check whether this content opens on the website. Complete any verification or sign-in there, and check your network settings.',
      );
    }
    if (status == 210) {
      return const AppErrorInfo(
        'The source temporarily refused the request',
        'Wait a while before trying again. If this continues, check the source website for access restrictions and update the source.',
      );
    }
    if (status == 429 || text.contains('too many requests')) {
      return const AppErrorInfo(
        'Too many requests',
        'The website is limiting requests. Wait a while before trying again; repeated refreshes may extend the wait.',
      );
    }
    if (status == 404) {
      return const AppErrorInfo(
        'Content could not be found',
        'The page may have moved or been removed. Refresh the comic details or update the source; for WebDAV, check the folder address.',
      );
    }
    if (status != null && status >= 500) {
      return const AppErrorInfo(
        'The website is temporarily unavailable',
        'Try again later. If the problem continues, check whether the website is available in your browser.',
      );
    }
    if (text.contains('certificate') || text.contains('handshakeexception')) {
      return const AppErrorInfo(
        'Secure connection failed',
        'Check the device date and network or proxy settings, then try again.',
      );
    }
    if (text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('socketexception') ||
        text.contains('unknownhostexception') ||
        text.contains('connectexception') ||
        text.contains('unable to resolve host') ||
        text.contains('connection error') ||
        text.contains('connection reset') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused')) {
      return const AppErrorInfo(
        'Could not connect',
        'Check your internet connection and proxy settings, then try again.',
        canAutoRetry: true,
      );
    }
    if (text.contains('filesystemexception') ||
        text.contains('no such file') ||
        text.contains('pathnotfound')) {
      return const AppErrorInfo(
        'Could not access the file',
        'The file may have moved or become unavailable. Check its location and storage permissions, then select it again.',
      );
    }
    if (text.contains('typeerror') ||
        text.contains('referenceerror') ||
        text.contains('syntaxerror') ||
        text.contains('cannot read property') ||
        text.contains('is not a subtype') ||
        text.contains('invalid data')) {
      return const AppErrorInfo(
        'The source could not read the website data',
        'Update the comic source and try again. If it still fails, send the diagnostic log to the source maintainer.',
      );
    }
    if (text.contains('formatexception') ||
        text.contains('invalid archive') ||
        text.contains('invalid zip')) {
      return const AppErrorInfo(
        'The data could not be read',
        'The file or website response is incomplete or has an unexpected format. Try downloading it again, or update the source if it came from a comic website.',
      );
    }
    if (text.contains('downloaded images are incomplete') ||
        text.contains('image list is') ||
        text.contains('no image list')) {
      return const AppErrorInfo(
        'Some comic pages could not be downloaded',
        'Retry the download. If the pages still fail, check access to this chapter on the source website.',
      );
    }
    if (text.contains('cancelled') || text.contains('canceled')) {
      return const AppErrorInfo(
        'Operation cancelled',
        'You can start it again when ready.',
      );
    }
    if (status != null ||
        isTechnical(raw) ||
        raw.contains(RegExp(r'https?://')) ||
        text == 'error' ||
        text == 'unknown error' ||
        text.isEmpty) {
      return const AppErrorInfo(
        'Operation could not be completed',
        'Try again. If the problem continues, open Diagnostic details or export the log to help identify the cause.',
      );
    }
    // Keep already meaningful application/source messages, including translations.
    return AppErrorInfo('Operation could not be completed', raw);
  }
}
