import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/transaction_record.dart';
import '../providers/transaction_provider.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final _notificationService = NotificationService();
  bool _notifAccess = false;
  bool _smsPermission = false;
  bool _locationPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final notif = await _notificationService.isNotificationAccessGranted();
    final sms = await Permission.sms.isGranted;
    final loc = await Permission.location.isGranted;
    if (mounted) {
      setState(() {
        _notifAccess = notif;
        _smsPermission = sms;
        _locationPermission = loc;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final cs = Theme.of(context).colorScheme;
    final syncSvc = provider.syncService;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _buildSectionHeader(context, 'Permissions'),
          _buildPermissionTile(
            icon: Icons.notifications_active_outlined,
            title: 'Notification Access',
            subtitle: _notifAccess
                ? 'Granted — UPI app notifications can be captured'
                : 'Required to read payment notifications',
            granted: _notifAccess,
            onTap: () => _notificationService.openNotificationAccessSettings(),
          ),
          _buildPermissionTile(
            icon: Icons.sms_outlined,
            title: 'SMS Access',
            subtitle: _smsPermission
                ? 'Granted — can read bank SMS'
                : 'Required to read bank transaction SMS',
            granted: _smsPermission,
            onTap: () async {
              await Permission.sms.request();
              _checkPermissions();
            },
          ),
          _buildPermissionTile(
            icon: Icons.location_on_outlined,
            title: 'Location Access',
            subtitle: _locationPermission
                ? 'Granted — tagging transaction locations'
                : 'Optional — tag transactions with location',
            granted: _locationPermission,
            onTap: () async {
              await Permission.location.request();
              _checkPermissions();
            },
          ),

          _buildSectionHeader(context, 'Tracking'),
          ListTile(
            leading: Icon(Icons.date_range, color: cs.primary),
            title: const Text('Start Date'),
            subtitle: Text(
              provider.startDate != null
                  ? 'Tracking from ${DateFormat('dd MMM yyyy').format(provider.startDate!)}'
                  : 'No start date — capturing all transactions',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (provider.startDate != null)
                  IconButton(
                    icon: Icon(Icons.clear, size: 18, color: cs.error),
                    tooltip: 'Remove start date',
                    onPressed: () async {
                      await provider.setStartDate(null);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Start date removed — showing all transactions')),
                        );
                      }
                    },
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: provider.startDate ?? DateTime.now(),
                firstDate: DateTime(2016),
                lastDate: DateTime.now(),
                helpText: 'Ignore transactions before this date',
              );
              if (picked != null && context.mounted) {
                await provider.setStartDate(picked);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Now tracking from ${DateFormat('dd MMM yyyy').format(picked)}')),
                );
              }
            },
          ),
          SwitchListTile(
            secondary: Icon(Icons.sensors, color: cs.primary),
            title: const Text('Live Monitoring'),
            subtitle: Text(
              !provider.filtersLoaded
                  ? 'Spam filter failed to load — messages are not being filtered'
                  : provider.isListening
                      ? 'Actively listening for new transactions'
                      : 'Start to automatically capture payments',
            ),
            value: provider.isListening,
            onChanged: (val) {
              if (val) {
                provider.startListening();
              } else {
                provider.stopListening();
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.history, color: cs.primary),
            title: const Text('Scan SMS History'),
            subtitle: const Text('Import past UPI transactions from SMS'),
            trailing: provider.isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: provider.isLoading
                ? null
                : () async {
                    await provider.scanSmsHistory();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(provider.error ?? 'SMS scan complete')),
                      );
                    }
                  },
          ),

          _buildSectionHeader(context, 'Cloud Sync'),
          ListTile(
            leading: Icon(Icons.cloud_sync_outlined, color: cs.primary),
            title: const Text('Sync Status'),
            subtitle: Text(
              syncSvc.lastSyncTime != null
                  ? 'Last synced: ${DateFormat.yMd().add_jm().format(syncSvc.lastSyncTime!)} (${syncSvc.lastSyncCount} records)'
                  : 'Not synced yet',
            ),
          ),
          ListTile(
            leading: Icon(Icons.sync, color: cs.primary),
            title: const Text('Sync Now'),
            subtitle: Text(
              provider.isSyncing
                  ? 'Syncing...'
                  : syncSvc.isSyncEnabled
                      ? 'Push pending records to cloud'
                      : 'Sync is disabled in .env',
            ),
            trailing: provider.isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: (syncSvc.isSyncEnabled && !provider.isSyncing)
                ? () async {
                    final result = await provider.triggerSync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result.message)),
                      );
                    }
                  }
                : null,
          ),

          _buildSectionHeader(context, 'Data'),
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: cs.primary),
            title: const Text('Add Manual Transaction'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAddDialog(context, provider),
          ),
          ListTile(
            leading: Icon(Icons.storage_outlined, color: cs.primary),
            title: const Text('Local Records'),
            subtitle: Text('${provider.totalCount} transactions stored locally'),
          ),

          _buildSectionHeader(context, 'About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('UPI Tracker'),
            subtitle: Text('v1.0.0 — Unified UPI payment tracker\nAll data stored locally first, synced to cloud.'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: granted ? Colors.green : cs.error),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: granted
          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : OutlinedButton(onPressed: onTap, child: const Text('Grant')),
      onTap: granted ? null : onTap,
    );
  }

  void _showAddDialog(BuildContext context, TransactionProvider provider) {
    final amountController = TextEditingController();
    final nameController = TextEditingController();
    final noteController = TextEditingController();
    var isDebit = true;
    String? selectedApp;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add Transaction', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Paid'), icon: Icon(Icons.arrow_upward)),
                  ButtonSegment(value: false, label: Text('Received'), icon: Icon(Icons.arrow_downward)),
                ],
                selected: {isDebit},
                onSelectionChanged: (val) => setSheetState(() => isDebit = val.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (₹)', prefixText: '₹ '),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Counterparty Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'App'),
                initialValue: selectedApp,
                items: const [
                  DropdownMenuItem(value: 'gpay', child: Text('Google Pay')),
                  DropdownMenuItem(value: 'phonepe', child: Text('PhonePe')),
                  DropdownMenuItem(value: 'paytm', child: Text('Paytm')),
                  DropdownMenuItem(value: 'bhim', child: Text('BHIM')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (val) => setSheetState(() => selectedApp = val),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text);
                  if (amount == null || amount <= 0) return;

                  provider.addManualTransaction(
                    amount: amount,
                    type: isDebit ? TransactionType.debit : TransactionType.credit,
                    counterpartyName: nameController.text.isNotEmpty ? nameController.text : null,
                    upiApp: selectedApp,
                    note: noteController.text.isNotEmpty ? noteController.text : null,
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transaction added')),
                  );
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
