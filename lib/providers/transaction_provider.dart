import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../database/local_database.dart';
import '../database/remote_database.dart';
import '../models/transaction_record.dart';
import '../services/upi_parser.dart';
import '../services/dedup_service.dart';
import '../services/notification_service.dart';
import '../services/sms_service.dart';
import '../services/sync_service.dart';
import '../services/location_service.dart';
import '../services/ml/message_pipeline.dart';

class TransactionProvider extends ChangeNotifier {
  static const _startDateKey = 'tracking_start_date';

  final LocalDatabase _localDb = LocalDatabase();
  final RemoteDatabase _remoteDb = RemoteDatabase();
  late final DedupService _dedupService;
  late final SyncService _syncService;
  final NotificationService _notificationService = NotificationService();
  final SmsService _smsService = SmsService();
  final LocationService _locationService = LocationService();
  final _uuid = const Uuid();

  List<TransactionRecord> _transactions = [];
  Map<String, double> _summary = {'total_spent': 0, 'total_received': 0, 'net': 0};
  Map<String, double> _last24hSummary = {'total_spent': 0, 'total_received': 0, 'net': 0};
  Map<String, double> _prev24hSummary = {'total_spent': 0, 'total_received': 0, 'net': 0};
  Map<String, double> _spendingByApp = {};
  List<double> _last7dSpending = const [];
  int _last24hCount = 0;
  bool _isLoading = false;
  String? _error;
  int _totalCount = 0;

  DateTime? _startDate;
  String? _typeFilter;
  String? _appFilter;
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _searchQuery;

  StreamSubscription? _notifSub;
  StreamSubscription? _smsSub;
  bool _isListening = false;

  List<TransactionRecord> get transactions => _transactions;
  Map<String, double> get summary => _summary;

  /// Rolling 24-hour window summary (now-24h → now).
  Map<String, double> get last24hSummary => _last24hSummary;

  /// The preceding 24-hour window (now-48h → now-24h) used for trend comparison.
  Map<String, double> get prev24hSummary => _prev24hSummary;

  /// Backwards-compatible alias; the dashboard now renders the rolling 24h window here.
  Map<String, double> get todaySummary => _last24hSummary;

  Map<String, double> get spendingByApp => _spendingByApp;
  List<double> get last7dSpending => _last7dSpending;
  int get last24hCount => _last24hCount;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get totalCount => _totalCount;

  /// Transactions that fall inside the rolling 24h window, sorted newest-first.
  List<TransactionRecord> get recent24hTransactions {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return _transactions.where((t) => t.transactionDate.isAfter(cutoff)).toList();
  }

  /// Percent change of 24h spending vs the preceding 24h window.
  /// Returns `null` when the prior window has no spending (comparison is undefined).
  double? get spendingDeltaPct {
    final prev = _prev24hSummary['total_spent'] ?? 0;
    final curr = _last24hSummary['total_spent'] ?? 0;
    if (prev <= 0) return null;
    return ((curr - prev) / prev) * 100;
  }
  SyncService get syncService => _syncService;
  bool get isListening => _isListening;
  bool get isSyncing => _syncService.isSyncing;
  DateTime? get startDate => _startDate;

  String? get typeFilter => _typeFilter;
  String? get appFilter => _appFilter;
  DateTime? get fromDate => _fromDate;
  DateTime? get toDate => _toDate;
  String? get searchQuery => _searchQuery;

  /// The effective floor date — whichever is later: the user filter or the global start date.
  DateTime? get _effectiveFromDate {
    if (_fromDate != null && _startDate != null) {
      return _fromDate!.isAfter(_startDate!) ? _fromDate : _startDate;
    }
    return _fromDate ?? _startDate;
  }

  TransactionProvider() {
    _dedupService = DedupService(_localDb);
    _syncService = SyncService(_localDb, _remoteDb);
  }

  Future<void> initialize() async {
    await _loadStartDate();
    // Load the stacked classifier weights in parallel with first DB reads.
    // Failures are swallowed inside MessagePipeline (fail-open).
    unawaited(MessagePipeline.instance.load());
    await loadTransactions();
    await loadSummary();
    _syncService.startPeriodicSync();
  }

  Future<void> _loadStartDate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_startDateKey);
    if (stored != null) {
      _startDate = DateTime.tryParse(stored);
    }
  }

  Future<void> setStartDate(DateTime? date) async {
    _startDate = date;
    final prefs = await SharedPreferences.getInstance();
    if (date != null) {
      await prefs.setString(_startDateKey, date.toIso8601String());
    } else {
      await prefs.remove(_startDateKey);
    }
    await loadTransactions();
    await loadSummary();
  }

  Future<void> startListening() async {
    if (_isListening) return;
    _isListening = true;

    _notifSub = _notificationService.notificationStream.listen(_handleNotification);
    _smsSub = _smsService.incomingSmsStream.listen(_handleSms);

    notifyListeners();
  }

  void stopListening() {
    _notifSub?.cancel();
    _smsSub?.cancel();
    _isListening = false;
    notifyListeners();
  }

  Future<void> _handleNotification(Map<String, dynamic> data) async {
    final title = data['title'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    final pkg = data['package'] as String? ?? '';

    // Stacked classifier gate: spam → non-transactional → direction-check.
    // Fail-open on each layer: a missing model must never drop real messages.
    final decision = MessagePipeline.instance.evaluate('$title $text');
    if (!decision.shouldIngest) {
      debugPrint('[pipeline] drop notification:$pkg at ${decision.stage} — ${decision.reason}');
      return;
    }

    final parsed = UpiParser.parseNotification(
      packageName: pkg,
      title: title,
      text: text,
    );

    if (!parsed.isValid) return;

    if (decision.disagreesWithParser(parsed.type)) {
      debugPrint(
        '[pipeline] direction mismatch on notification:$pkg — '
        'parser=${parsed.type} model=${decision.directionHint} '
        '(p_credit=${decision.creditProbability?.toStringAsFixed(3)})',
      );
    }

    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      (data['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    );

    await _processTransaction(parsed, timestamp, 'notification', data['text'] as String? ?? '');
  }

  Future<void> _handleSms(Map<String, dynamic> data) async {
    final body = data['body'] as String? ?? '';
    final sender = data['sender'] as String? ?? '';
    if (!UpiParser.isUpiRelated(body)) return;

    final decision = MessagePipeline.instance.evaluate(body);
    if (!decision.shouldIngest) {
      debugPrint('[pipeline] drop sms:$sender at ${decision.stage} — ${decision.reason}');
      return;
    }

    final parsed = UpiParser.parseSms(
      sender: sender,
      body: body,
    );

    if (!parsed.isValid) return;

    if (decision.disagreesWithParser(parsed.type)) {
      debugPrint(
        '[pipeline] direction mismatch on sms:$sender — '
        'parser=${parsed.type} model=${decision.directionHint} '
        '(p_credit=${decision.creditProbability?.toStringAsFixed(3)})',
      );
    }

    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      (data['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    );

    await _processTransaction(parsed, timestamp, 'sms', body);
  }

  Future<void> _processTransaction(ParsedUpi parsed, DateTime timestamp, String source, String rawText) async {
    if (_startDate != null && timestamp.isBefore(_startDate!)) return;

    final dedupHash = _dedupService.generateDedupHash(parsed, rawText);

    if (await _dedupService.isDuplicate(parsed, timestamp, dedupHash)) return;

    LocationData? location;
    try {
      location = await _locationService.getCurrentLocation();
    } catch (_) {}

    final record = TransactionRecord(
      id: _uuid.v4(),
      amount: parsed.amount!,
      type: parsed.type!,
      upiApp: parsed.upiApp,
      upiTransactionId: parsed.upiTransactionId,
      bankReference: parsed.bankReference,
      counterpartyName: parsed.counterpartyName,
      counterpartyUpiId: parsed.counterpartyUpiId,
      accountInfo: parsed.accountInfo,
      description: parsed.description,
      source: source,
      rawText: rawText,
      dedupHash: dedupHash,
      transactionDate: timestamp,
      latitude: location?.latitude,
      longitude: location?.longitude,
      locationName: location?.name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _localDb.insertTransaction(record);
    await loadTransactions();
    await loadSummary();
  }

  Future<void> scanSmsHistory() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final messages = await _smsService.readSmsHistory(limit: 500);
      int added = 0;

      int skippedSpam = 0;
      int skippedNonTx = 0;
      for (final msg in messages) {
        final body = msg['body'] as String? ?? '';
        final sender = msg['sender'] as String? ?? '';
        if (!UpiParser.isUpiRelated(body)) continue;

        final decision = MessagePipeline.instance.evaluate(body);
        if (!decision.shouldIngest) {
          if (decision.stage == 'spam') {
            skippedSpam++;
          } else {
            skippedNonTx++;
          }
          continue;
        }

        final parsed = UpiParser.parseSms(
          sender: sender,
          body: body,
        );

        if (!parsed.isValid) continue;

        final timestamp = DateTime.fromMillisecondsSinceEpoch(
          (msg['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
        );

        if (_startDate != null && timestamp.isBefore(_startDate!)) continue;

        final dedupHash = _dedupService.generateDedupHash(parsed, body);
        if (await _dedupService.isDuplicate(parsed, timestamp, dedupHash)) continue;

        final record = TransactionRecord(
          id: _uuid.v4(),
          amount: parsed.amount!,
          type: parsed.type!,
          upiApp: parsed.upiApp,
          upiTransactionId: parsed.upiTransactionId,
          bankReference: parsed.bankReference,
          counterpartyName: parsed.counterpartyName,
          counterpartyUpiId: parsed.counterpartyUpiId,
          accountInfo: parsed.accountInfo,
          description: parsed.description,
          source: 'sms',
          rawText: body,
          dedupHash: dedupHash,
          transactionDate: timestamp,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await _localDb.insertTransaction(record);
        added++;
      }

      await loadTransactions();
      await loadSummary();
      final parts = <String>[];
      if (added > 0) parts.add('Found $added new transactions');
      if (skippedSpam > 0) parts.add('filtered $skippedSpam spam');
      if (skippedNonTx > 0) parts.add('skipped $skippedNonTx non-transactional');
      _error = parts.isEmpty ? 'No new transactions found' : parts.join(' • ');
    } catch (e) {
      _error = 'SMS scan failed: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTransactions() async {
    try {
      _transactions = await _localDb.getAllTransactions(
        typeFilter: _typeFilter,
        appFilter: _appFilter,
        fromDate: _effectiveFromDate,
        toDate: _toDate,
        searchQuery: _searchQuery,
      );
      _totalCount = await _localDb.getTransactionCount();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load transactions: $e';
      notifyListeners();
    }
  }

  Future<void> loadSummary({DateTime? from, DateTime? to}) async {
    try {
      final effectiveFrom = from ?? _effectiveFromDate;
      _summary = await _localDb.getSummary(fromDate: effectiveFrom, toDate: to ?? _toDate);
      _spendingByApp = await _localDb.getSpendingByApp(fromDate: effectiveFrom, toDate: to ?? _toDate);

      final now = DateTime.now();
      final last24hStart = now.subtract(const Duration(hours: 24));
      final prev24hStart = now.subtract(const Duration(hours: 48));

      _last24hSummary = await _localDb.getSummary(fromDate: last24hStart, toDate: now);
      _prev24hSummary = await _localDb.getSummary(fromDate: prev24hStart, toDate: last24hStart);

      final dailyRows = await _localDb.getDailyTotals(
        fromDate: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
        toDate: now,
      );
      _last7dSpending = _bucketDailySpending(dailyRows, now);

      // Count of transactions (both directions) in the past 24h — used by the widget.
      _last24hCount = _transactions
          .where((t) => t.transactionDate.isAfter(last24hStart))
          .length;

      notifyListeners();
      _refreshWidget();
    } catch (e) {
      _error = 'Failed to load summary: $e';
      notifyListeners();
    }
  }

  /// Build a 7-element list of daily spending (oldest → today) from the
  /// `getDailyTotals` rows. Missing days are zero-filled so widgets can always
  /// render a 7-bar sparkline.
  List<double> _bucketDailySpending(List<Map<String, dynamic>> rows, DateTime now) {
    final buckets = List<double>.filled(7, 0.0);
    for (final row in rows) {
      final type = row['transaction_type'] as String?;
      if (type != 'debit') continue;
      final dateStr = row['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      final today = DateTime(now.year, now.month, now.day);
      final days = today.difference(DateTime(date.year, date.month, date.day)).inDays;
      if (days < 0 || days > 6) continue;
      final idx = 6 - days;
      buckets[idx] = ((row['total'] as num?)?.toDouble() ?? 0.0);
    }
    return buckets;
  }

  Future<List<Map<String, dynamic>>> getDailyTotals(DateTime from, DateTime to) {
    return _localDb.getDailyTotals(fromDate: from, toDate: to);
  }

  void setFilters({
    String? typeFilter,
    String? appFilter,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchQuery,
  }) {
    _typeFilter = typeFilter;
    _appFilter = appFilter;
    _fromDate = fromDate;
    _toDate = toDate;
    _searchQuery = searchQuery;
    loadTransactions();
    loadSummary();
  }

  void clearFilters() {
    _typeFilter = null;
    _appFilter = null;
    _fromDate = null;
    _toDate = null;
    _searchQuery = null;
    loadTransactions();
    loadSummary();
  }

  Future<void> updateNote(String id, String note) async {
    final record = await _localDb.getTransactionById(id);
    if (record == null) return;

    final updated = record.copyWith(
      note: note,
      synced: false,
      updatedAt: DateTime.now(),
    );
    await _localDb.updateTransaction(updated);
    await loadTransactions();
  }

  Future<void> updateTags(String id, String tags) async {
    final record = await _localDb.getTransactionById(id);
    if (record == null) return;

    final updated = record.copyWith(
      tags: tags,
      synced: false,
      updatedAt: DateTime.now(),
    );
    await _localDb.updateTransaction(updated);
    await loadTransactions();
  }

  Future<void> deleteTransaction(String id) async {
    await _localDb.deleteTransaction(id);
    await loadTransactions();
    await loadSummary();
  }

  Future<void> addManualTransaction({
    required double amount,
    required TransactionType type,
    String? counterpartyName,
    String? upiApp,
    String? note,
    String? tags,
    DateTime? date,
  }) async {
    final now = date ?? DateTime.now();
    final record = TransactionRecord(
      id: _uuid.v4(),
      amount: amount,
      type: type,
      upiApp: upiApp,
      counterpartyName: counterpartyName,
      note: note,
      tags: tags ?? '',
      source: 'manual',
      dedupHash: 'manual:${_uuid.v4()}',
      transactionDate: now,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _localDb.insertTransaction(record);
    await loadTransactions();
    await loadSummary();
  }

  Future<SyncResult> triggerSync() async {
    notifyListeners();
    final result = await _syncService.syncNow();
    notifyListeners();
    return result;
  }

  void _refreshWidget() {
    // Push a self-contained snapshot to the native widget so it never has to
    // reopen SQLite from a BroadcastReceiver (which is the usual culprit behind
    // "Can't load widget" on Android launchers).
    final payload = <String, Object?>{
      'spent24h': _last24hSummary['total_spent'] ?? 0,
      'received24h': _last24hSummary['total_received'] ?? 0,
      'spentPrev24h': _prev24hSummary['total_spent'] ?? 0,
      'deltaPct': spendingDeltaPct,
      'count24h': _last24hCount,
      'spark7d': _last7dSpending,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    const MethodChannel('com.upitracker.app/methods')
        .invokeMethod('updateWidget', payload)
        .catchError((_) => null);
  }

  @override
  void dispose() {
    stopListening();
    _syncService.dispose();
    super.dispose();
  }
}
