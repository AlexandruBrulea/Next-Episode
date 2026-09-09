import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../application/providers.dart';
import '../data/alerts.dart';
import 'common.dart';
import 'alert_time_picker.dart';
import 'legal.dart';
import '../application/app_contact.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AlertSettings? settings;
  String version = 'Loading…';
  String? error;
  bool busy = false;
  (int, bool)? pendingTime;
  void saveTime(int minutes, bool after) {
    if (busy) {
      pendingTime = (minutes, after);
      return;
    }
    if (settings?.minutes == minutes && settings?.after == after) return;
    save(minutes: minutes, after: after);
  }
  Future<void> emailSupport() async {
    final uri = Uri(scheme: 'mailto', path: supportEmail,
      query: 'subject=${Uri.encodeComponent('Next Episode support')}');
    try {
      final opened = await launchUrl(uri);
      if (!opened && mounted) message(context, 'No email app available. Contact $supportEmail.');
    } catch (_) {
      if (mounted) message(context, 'Could not open email. Contact $supportEmail.');
    }
  }
  @override
  void initState() {
    super.initState();
    load();
  }
  Future<void> load() async {
    try {
      final value = await AlertSettings.load(ref.read(databaseProvider));
      if (mounted) setState(() => settings = value);
    } catch (_) {
      if (mounted) setState(() => error = 'Settings could not be loaded.');
    }
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => version = '${info.version} (${info.buildNumber})');
    } catch (_) {
      if (mounted) setState(() => version = 'Unavailable');
    }
  }
  Future<void> save({bool? enabled, bool? after, int? minutes, TimeOfDay? fallback}) async {
    final old = settings;
    if (old == null || busy) return;
    setState(() { busy = true; error = null; });
    final alerts = ref.read(episodeAlertsProvider);
    try {
      if (enabled == true && !await alerts.requestPermission()) {
        throw Exception('Permission denied');
      }
      final next = AlertSettings(enabled: enabled ?? old.enabled, after: after ?? old.after,
        minutes: minutes ?? old.minutes, fallbackHour: fallback?.hour ?? old.fallbackHour,
        fallbackMinute: fallback?.minute ?? old.fallbackMinute);
      await next.save(ref.read(databaseProvider));
      if (mounted) setState(() => settings = next);
      final snapshot = await ref.read(libraryProvider.future);
      await alerts.refresh(ref.read(databaseProvider), snapshot.series.values, snapshot.watched);
      ref.read(alertErrorProvider.notifier).update(null);
    } catch (_) {
      if (mounted) setState(() => error = 'Alerts could not be updated. Allow notifications in your device settings and try again.');
    } finally {
      if (mounted) {
        setState(() => busy = false);
        final pending = pendingTime;
        pendingTime = null;
        if (pending != null) saveTime(pending.$1, pending.$2);
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(libraryProvider).asData?.value.entries;
    final alerts = ref.watch(episodeAlertsProvider);
    final issue = error ?? ref.watch(alertErrorProvider);
    final value = settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), leading: IconButton(
        tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
      body: ListView(primary: true, padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: [
        Card(margin: EdgeInsets.zero, child: ListTile(leading: const Icon(Icons.video_library_outlined), title: const Text('Your library'),
          subtitle: Text(entries == null ? 'Loading…' : '${entries.where((e) => e.title.isTv).length} shows · ${entries.where((e) => !e.title.isTv).length} movies'))),
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Notifications', style: Theme.of(context).textTheme.titleLarge)),
        if (busy) const LinearProgressIndicator(),
        if (issue != null) Padding(padding: const EdgeInsets.all(12), child: Text(issue)),
        if (value != null) ...[
          SwitchListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16), title: const Text('Episode alerts'),
            subtitle: Text(alerts.supported ? 'Reminders for unwatched episodes in your library' : 'Available on iOS and Android'),
            value: value.enabled, onChanged: alerts.supported && !busy ? (v) => save(enabled: v) : null),
          const SizedBox(height: 12),
          AlertTimePicker(minutes: value.minutes, after: value.after, onChanged: saveTime),
        ],
        const SizedBox(height: 24),
        Card(margin: EdgeInsets.zero, child: Column(children: [
          ListTile(title: const Text('Email Support'),
            subtitle: const Text(supportContactLabel), trailing: const Icon(Icons.chevron_right),
            onTap: supportEmail.isEmpty ? null : emailSupport),
          ListTile(title: const Text('Terms of Use'), trailing: const Icon(Icons.chevron_right),
            onTap: () => openScreen(context, const LegalScreen(privacy: false))),
          ListTile(title: const Text('Privacy Policy'), trailing: const Icon(Icons.chevron_right),
            onTap: () => openScreen(context, const LegalScreen(privacy: true))),
          ListTile(title: const Text('Version'), trailing: Text(version)),
        ])),
        const SizedBox(height: 16),
        const ExpansionTile(title: Text('About & data credits'), children: [
          // SourceCredit('TVmaze · CC BY-SA', 'https://www.tvmaze.com/api'),
          TmdbCredits(),
        ]),
      ]),
    );
  }
}
