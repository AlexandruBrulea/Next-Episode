import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../data/feedback.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  final List<FeedbackIssue> currentIssues;
  const FeedbackScreen({super.key, this.currentIssues = const []});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  late final Future<List<FeedbackIssue>> issuesFuture;
  bool sending = false;
  FeedbackMailResult? mailResult;
  String? sendError;

  @override
  void initState() {
    super.initState();
    issuesFuture = FeedbackIssueStore(ref.read(databaseProvider)).load();
  }

  Future<void> sendFeedback(List<FeedbackIssue> issues) async {
    if (sending) return;
    setState(() {
      sending = true;
      sendError = null;
      mailResult = null;
    });
    try {
      final result = await ref.read(feedbackSenderProvider).send(issues);
      if (mounted) setState(() => mailResult = result);
    } on FeedbackSendException catch (error) {
      if (mounted) setState(() => sendError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => sendError = 'Could not open the report. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Update issues'),
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: FutureBuilder<List<FeedbackIssue>>(
      future: issuesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        final issues = snapshot.data?.isNotEmpty == true
            ? snapshot.data!
            : widget.currentIssues;
        if (issues.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No recent update issues. Your saved library is available.',
              ),
            ),
          );
        }
        final senderReady = ref.read(feedbackSenderProvider).configured;
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                itemCount: issues.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '${issues.length} recent ${issues.length == 1 ? 'issue' : 'issues'}. Your watched progress is safe. These details stay on this device until you choose to attach a report to an email.',
                      ),
                    );
                  }
                  final issue = issues[index - 1];
                  final localTime = issue.occurredAt.toLocal();
                  final localizations = MaterialLocalizations.of(context);
                  final timeLabel =
                      '${localizations.formatShortDate(localTime)} '
                      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localTime))}';
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(issue.title),
                      subtitle: Text('${issue.reason}\n$timeLabel'),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Attach a separate text-file report of these issues and the app version to an email for ${ref.read(feedbackSenderProvider).recipient}. No watched history or complete library is included. You review and send the email yourself. If a share menu opens, choose your email app and enter the address if needed.',
                  ),
                  if (!senderReady)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Support email is not configured in this build.',
                      ),
                    ),
                  if (sendError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(sendError!),
                    ),
                  if (mailResult != null)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(switch (mailResult!) {
                        FeedbackMailResult.sent =>
                          'Email sent or queued by the mail app. Thank you.',
                        FeedbackMailResult.saved =>
                          'Email saved as a draft. It has not been sent.',
                        FeedbackMailResult.cancelled => 'Email was not sent.',
                        FeedbackMailResult.opened => 'Email composer closed. Check your mail app to confirm whether it was sent.',
                        FeedbackMailResult.shared =>
                          'Report shared. If you selected an email app, send it to ${ref.read(feedbackSenderProvider).recipient}. The recipient may need to be entered manually.',
                      }),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: !senderReady || sending
                        ? null
                        : () => sendFeedback(issues),
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: const Text('Email report'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
