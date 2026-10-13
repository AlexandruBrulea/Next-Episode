import 'dart:convert';

import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/feedback.dart';
import 'package:next_episode/domain/request_diagnostic.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test(
    'stores only recent safe issues and does no write for an empty report',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final store = FeedbackIssueStore(db);
      final before =
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      await store.record(const []);
      final after =
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      expect(after, before);

      final date = DateTime.utc(2026, 10, 10);
      await store.record([
        for (var i = 0; i < 25; i++)
          FeedbackIssue('Show $i', 'Timed out', date),
      ]);
      expect((await store.load()).length, FeedbackIssueStore.maxIssues);
      await store.record([FeedbackIssue('Show 24', 'Timed out', date)]);
      final issues = await FeedbackIssueStore(db).load();
      expect(issues.length, FeedbackIssueStore.maxIssues);
      expect(issues.first.title, 'Show 24');
    },
  );

  test('prepares an attached report only after an explicit action', () async {
    Email? drafted;
    final sender = FeedbackSender(
      recipient: 'support@example.com',
      getPackageInfo: () async => PackageInfo(
        appName: 'Next Episode',
        packageName: 'test.next.episode',
        version: '0.1.2',
        buildNumber: '10',
      ),
      getCapabilities: () async => const EmailCapabilities(
        canSend: true,
        supportsCc: true,
        supportsBcc: true,
        supportsSubject: true,
        supportsPlainTextBody: true,
        supportsHtmlBody: false,
        supportsAttachments: true,
      ),
      send: (email) async {
        drafted = email;
        return EmailSendResult.unknown;
      },
    );
    expect(drafted, isNull);
    final result = await sender.send([
      FeedbackIssue(
        'A show',
        'TVmaze timed out.',
        DateTime.utc(2026, 10, 10),
        entityKey: 'tv:10',
        diagnostic: RequestDiagnostic(
          endpoint: '/tv/42/season/2',
          exceptionType: 'receiveTimeout',
          durationMs: 15000,
          attempts: 3,
          occurredAt: DateTime.utc(2026, 10, 10),
        ),
      ),
    ]);
    expect(result, FeedbackMailResult.opened);
    expect(drafted?.recipients, ['support@example.com']);
    expect(
      drafted?.attachments.single.fileName,
      'next-episode-update-report.txt',
    );
    final report = utf8.decode(drafted!.attachments.single.data!);
    expect(report, contains('A show: TVmaze timed out.'));
    expect(report, contains('App: 0.1.2 (10)'));
    expect(report, isNot(contains('watched')));
    expect(report, contains('/tv/42/season/2'));
    expect(report, contains('"attempts":3'));
    expect(report, contains('Resource: tv:10'));
    expect(report, contains('unresolved at last attempt'));
    expect(report, isNot(contains('Authorization')));
  });

  test('missing support email stops before opening a composer', () async {
    final sender = FeedbackSender(recipient: '');
    expect(sender.configured, isFalse);
    await expectLater(
      sender.send([FeedbackIssue('Show', 'Offline', DateTime.utc(2026))]),
      throwsA(isA<FeedbackSendException>()),
    );
  });

  test('shares a separate file when native mail cannot attach', () async {
    ShareParams? shared;
    final sender = FeedbackSender(
      recipient: 'support@example.com',
      getPackageInfo: () async => PackageInfo(
        appName: 'Next Episode',
        packageName: 'test.next.episode',
        version: '0.1.2',
        buildNumber: '10',
      ),
      getCapabilities: () async =>
          const EmailCapabilities.mailto(canSend: true),
      share: (params) async {
        shared = params;
        return const ShareResult('mail', ShareResultStatus.success);
      },
    );
    final result = await sender.send([
      FeedbackIssue('Show', 'Offline', DateTime.utc(2026)),
    ]);
    expect(result, FeedbackMailResult.shared);
    expect(shared?.fileNameOverrides, ['next-episode-update-report.txt']);
    expect(shared?.files, hasLength(1));
    expect(shared?.text, contains('support@example.com'));
  });
}
