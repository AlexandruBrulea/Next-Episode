import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../application/app_contact.dart';
import 'database.dart';
import '../domain/request_diagnostic.dart';

class FeedbackIssue {
  final String title;
  final String reason;
  final DateTime occurredAt;
  final String? entityKey;
  final RequestDiagnostic? diagnostic;
  final DateTime? resolvedAt;

  const FeedbackIssue(
    this.title,
    this.reason,
    this.occurredAt, {
    this.entityKey,
    this.diagnostic,
    this.resolvedAt,
  });

  Map<String, Object?> toJson() => {
    'title': title,
    'reason': reason,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (entityKey != null) 'entityKey': entityKey,
    if (diagnostic != null) 'request': diagnostic!.toJson(),
    if (resolvedAt != null) 'resolvedAt': resolvedAt!.toUtc().toIso8601String(),
  };

  static FeedbackIssue? fromJson(Object? value) {
    if (value is! Map ||
        value['title'] is! String ||
        value['reason'] is! String ||
        value['occurredAt'] is! String) {
      return null;
    }
    final date = DateTime.tryParse(value['occurredAt'] as String);
    if (date == null) return null;
    return FeedbackIssue(
      (value['title'] as String).trim(),
      (value['reason'] as String).trim(),
      date,
      entityKey:
          value['entityKey'] is String &&
              RegExp(r'^(tv|movie):\d+$').hasMatch(value['entityKey'] as String)
          ? value['entityKey'] as String
          : null,
      diagnostic: RequestDiagnostic.fromJson(value['request']),
      resolvedAt: value['resolvedAt'] is String
          ? DateTime.tryParse(value['resolvedAt'] as String)
          : null,
    );
  }
}

/// Bounded local diagnostics. Reads no episode cache or watched history.
class FeedbackIssueStore {
  static const _key = 'recent_sync_issues';
  static const maxIssues = 20;
  final AppDatabase db;

  FeedbackIssueStore(this.db);

  Future<List<FeedbackIssue>> load() async {
    final saved = await db.preference(_key);
    if (saved == null) return const [];
    try {
      final data = jsonDecode(saved);
      if (data is! List) return const [];
      final issues = <FeedbackIssue>[];
      for (final item in data) {
        final issue = FeedbackIssue.fromJson(item);
        if (issue != null) issues.add(issue);
      }
      return issues.take(maxIssues).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> record(
    List<FeedbackIssue> failures, {
    Set<String> resolvedKeys = const {},
    DateTime? resolvedAt,
  }) async {
    if (failures.isEmpty && resolvedKeys.isEmpty) return;
    final previous = await load();
    if (failures.isEmpty &&
        !previous.any(
          (e) => e.resolvedAt == null && resolvedKeys.contains(e.entityKey),
        )) {
      return;
    }
    final unique = <String, FeedbackIssue>{};
    for (final issue in [...failures.reversed, ...previous]) {
      final safe = FeedbackIssue(
        issue.title.length > 120 ? issue.title.substring(0, 120) : issue.title,
        issue.reason.length > 240
            ? issue.reason.substring(0, 240)
            : issue.reason,
        issue.occurredAt,
        entityKey: issue.entityKey,
        diagnostic: issue.diagnostic,
        resolvedAt: resolvedKeys.contains(issue.entityKey)
            ? issue.resolvedAt ?? resolvedAt ?? DateTime.now()
            : issue.resolvedAt,
      );
      unique.putIfAbsent(
        '${safe.entityKey ?? safe.title}\u0000${safe.reason}',
        () => safe,
      );
    }
    final encoded = jsonEncode(
      unique.values.take(maxIssues).map((issue) => issue.toJson()).toList(),
    );
    if (encoded !=
        jsonEncode(previous.map((issue) => issue.toJson()).toList())) {
      await db.setPreference(_key, encoded);
    }
  }
}

enum FeedbackMailResult { sent, saved, cancelled, opened, shared }

/// Builds the report only after an explicit tap. Nothing runs at app startup.
class FeedbackSender {
  final String recipient;
  final Future<PackageInfo> Function() packageInfo;
  final Future<EmailCapabilities> Function() capabilities;
  final Future<EmailSendResult> Function(Email) sendEmail;
  final Future<ShareResult> Function(ShareParams) shareReport;

  FeedbackSender({
    this.recipient = supportEmail,
    Future<PackageInfo> Function()? getPackageInfo,
    Future<EmailCapabilities> Function()? getCapabilities,
    Future<EmailSendResult> Function(Email)? send,
    Future<ShareResult> Function(ShareParams)? share,
  }) : packageInfo = getPackageInfo ?? PackageInfo.fromPlatform,
       capabilities = getCapabilities ?? FlutterEmailSender.getCapabilities,
       sendEmail = send ?? FlutterEmailSender.send,
       shareReport = share ?? SharePlus.instance.share;

  bool get configured => recipient.trim().isNotEmpty;

  Future<FeedbackMailResult> _share(Uint8List bytes, String filename) async {
    // A share sheet preserves the separate attachment, but cannot prefill a
    // reliable email recipient. The UI shows the address for manual entry.
    final result = await shareReport(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'text/plain')],
        fileNameOverrides: [filename],
        subject: 'Next Episode update issue report',
        text: 'Please email this report to $recipient.',
      ),
    );
    return result.status == ShareResultStatus.dismissed
        ? FeedbackMailResult.cancelled
        : FeedbackMailResult.shared;
  }

  Future<FeedbackMailResult> send(List<FeedbackIssue> issues) async {
    if (!configured) {
      throw const FeedbackSendException('Support email is not configured yet.');
    }
    if (issues.isEmpty) {
      throw const FeedbackSendException(
        'There are no recent update issues to report.',
      );
    }
    final app = await packageInfo();
    final report = [
      'Next Episode update issue report',
      'App: ${app.version} (${app.buildNumber})',
      'Platform: ${Platform.operatingSystem}',
      'Report format: 2 (request durations include retries; no headers or response bodies)',
      'Sync concurrency: ${const int.fromEnvironment('SYNC_CONCURRENCY', defaultValue: 3).clamp(1, 4)}',
      'Issues:',
      for (final issue in issues.take(FeedbackIssueStore.maxIssues))
        '${issue.occurredAt.toUtc().toIso8601String()} | ${issue.title}: ${issue.reason}\n'
            '  State: ${issue.resolvedAt != null
                ? 'resolved at ${issue.resolvedAt!.toUtc().toIso8601String()}'
                : issue.entityKey == null
                ? 'historical (current state unknown)'
                : 'unresolved at last attempt'}'
            '${issue.entityKey == null ? '' : '\n  Resource: ${issue.entityKey}'}'
            '${issue.diagnostic == null ? '' : '\n  Request: ${jsonEncode(issue.diagnostic!.toJson())}'}',
    ].join('\n');
    final bytes = Uint8List.fromList(utf8.encode('$report\n'));
    final filename = 'next-episode-update-report.txt';
    final email = Email(
      recipients: [recipient],
      subject: 'Next Episode update issue report',
      body: 'The update issue report is attached. Please send this email to support.',
      attachments: [
        EmailAttachment.data(bytes, fileName: filename, mimeType: 'text/plain'),
      ],
    );
    try {
      final available = await capabilities();
      if (available.canSend && available.supportsAttachments) {
        final result = await sendEmail(email);
        return switch (result) {
          EmailSendResult.sent => FeedbackMailResult.sent,
          EmailSendResult.saved => FeedbackMailResult.saved,
          EmailSendResult.cancelled => FeedbackMailResult.cancelled,
          EmailSendResult.unknown => FeedbackMailResult.opened,
        };
      }
      // Gmail-only iPhones cannot receive an attachment through mailto:.
      return await _share(bytes, filename);
    } on FlutterEmailSenderUnsupportedFeatureException {
      return _share(bytes, filename);
    } on FlutterEmailSenderNotAvailableException {
      return _share(bytes, filename);
    } catch (_) {
      throw const FeedbackSendException(
        'Could not open the report. Please try again.',
      );
    }
  }
}

class FeedbackSendException implements Exception {
  final String message;
  const FeedbackSendException(this.message);
}
