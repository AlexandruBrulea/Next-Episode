import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../application/providers.dart';
import '../data/alerts.dart';
import 'common.dart';
import 'alert_time_picker.dart';
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
    final uri = Uri(scheme: 'mailto', path: 'test@test.ro',
      query: 'subject=${Uri.encodeComponent('Next Episode support')}');
    try {
      final opened = await launchUrl(uri);
      if (!opened && mounted) message(context, 'No email app available. Contact test@test.ro.');
    } catch (_) {
      if (mounted) message(context, 'Could not open email. Contact test@test.ro.');
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
        Card(child: ListTile(leading: const Icon(Icons.video_library_outlined), title: const Text('Your library'),
          subtitle: Text(entries == null ? 'Loading…' : '${entries.where((e) => e.title.isTv).length} shows · ${entries.where((e) => !e.title.isTv).length} movies'))),
        const SizedBox(height: 20),
        Text('Notifications', style: Theme.of(context).textTheme.titleLarge),
        if (busy) const LinearProgressIndicator(),
        if (issue != null) Padding(padding: const EdgeInsets.all(12), child: Text(issue)),
        if (value != null) ...[
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Episode alerts'),
            subtitle: Text(alerts.supported ? 'Reminders for unwatched episodes in your library' : 'Available on iOS and Android'),
            value: value.enabled, onChanged: alerts.supported && !busy ? (v) => save(enabled: v) : null),
          const SizedBox(height: 12),
          AlertTimePicker(minutes: value.minutes, after: value.after, onChanged: saveTime),
          const Text('Before and after refer to the episode start time. Delivery may be delayed by your device. Upcoming alerts refresh when you open the app.'),
        ],
        const SizedBox(height: 24),
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.mail_outline), title: const Text('Email Support'),
            subtitle: const Text('test@test.ro'), trailing: const Icon(Icons.chevron_right),
            onTap: emailSupport),
          ListTile(title: const Text('Terms of Use'), trailing: const Icon(Icons.chevron_right),
            onTap: () => openScreen(context, const LegalScreen(privacy: false))),
          ListTile(title: const Text('Privacy Policy'), trailing: const Icon(Icons.chevron_right),
            onTap: () => openScreen(context, const LegalScreen(privacy: true))),
          ListTile(title: const Text('Version'), trailing: Text(version)),
        ])),
        const SizedBox(height: 16),
        const ExpansionTile(title: Text('About & data credits'), children: [
          SourceCredit('TVmaze · CC BY-SA', 'https://www.tvmaze.com/api'),
          SourceCredit('TMDB', 'https://www.themoviedb.org'),
          Padding(padding: EdgeInsets.all(16), child: Text('This product uses the TMDB API but is not endorsed or certified by TMDB.\n\nStreaming availability powered by JustWatch.')),
        ]),
      ]),
    );
  }
}

class LegalScreen extends StatelessWidget {
  final bool privacy;
  const LegalScreen({super.key, required this.privacy});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(privacy ? 'Privacy Policy' : 'Terms of Use'),
      leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
    body: ListView(primary: true, padding: const EdgeInsets.all(24), children: [
      const Text('Test · Development draft · September 8, 2026'),
      const SizedBox(height: 24),
      Text(privacy ? '''Next Episode stores your library, watch history, preferences and cached title information on your device. This build does not provide an account or cloud synchronization and does not include advertising or analytics SDKs.

Search queries and requests for title information are sent to the configured catalog provider, TMDB or TVmaze. Images and trailer previews load from external services. These services receive network information such as your IP address. Opening a trailer or viewing link uses the external service and its privacy policy.

When you enable alerts, the app requests notification permission and gives episode titles and reminder times to your device's notification system. You can disable alerts in Settings. Notification content may be visible on your lock screen according to your device settings.

Removing a title from your library keeps its watch history for later re-adding. Clearing the app's stored data removes the local library and preferences. Device backups may retain app data according to your device settings.

Publisher: Test (temporary). A privacy contact address will be added before public release.''' : '''Next Episode helps you organize your library and track episodes. It does not stream films or shows and does not include subscriptions to third-party services.

Release dates, cast, images, ratings and viewing options come from external providers and may be incomplete or change. Viewing links do not guarantee availability in your location. Third-party services apply their own terms and charges.

Alerts are optional reminders based on the available release information. They depend on notification permissions and device scheduling. When no exact airtime is provided, the app uses the fallback time you select. Alerts are not guaranteed to arrive at an exact time.

Your library and progress are stored locally. Keep any device backups you need. This development build may change before release. Third-party artwork and metadata remain subject to their owners' rights and provider licenses.

Publisher: Test (temporary). Contact details and final terms will be added before public release. These draft terms do not limit rights that cannot be excluded under applicable law.''', style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
    ]),
  );
}
