import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScrollLockApp());
}

class ScrollLockApp extends StatelessWidget {
  const ScrollLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScrollLock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFE1306C),
        scaffoldBackgroundColor: const Color(0xFF0F1016),
        cardTheme: CardThemeData(
          color: const Color(0xFF181922),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF282A3A), width: 1),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const MethodChannel _channel =
      MethodChannel('com.example.scroll_lock/channel');

  int _scrollCount = 0;
  int _scrollLimit = 5;
  String _lastResetDate = '';
  bool _isAccessibilityEnabled = false;
  bool _hasOverlayPermission = false;
  bool _isLocked = false;
  bool _resetLimitDaily = false;
  bool _isLoading = true;

  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchStats();
    // Refresh stats periodically to reflect live scroll updates from the native service
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _fetchStats(showLoading: false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchStats(showLoading: false);
    }
  }

  Future<void> _fetchStats({bool showLoading = true}) async {
    if (showLoading && _isLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStats');
      if (res != null && mounted) {
        setState(() {
          _scrollCount = (res['scrollCount'] as num?)?.toInt() ?? 0;
          _scrollLimit = (res['scrollLimit'] as num?)?.toInt() ?? 5;
          _lastResetDate = (res['lastResetDate'] as String?) ?? '';
          _isAccessibilityEnabled =
              (res['isAccessibilityEnabled'] as bool?) ?? false;
          _hasOverlayPermission =
              (res['hasOverlayPermission'] as bool?) ?? false;
          _isLocked = (res['isLocked'] as bool?) ?? false;
          _resetLimitDaily = (res['resetLimitDaily'] as bool?) ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateLimit(int newLimit) async {
    if (newLimit < 1) newLimit = 1;
    if (newLimit > 500) newLimit = 500;
    setState(() {
      _scrollLimit = newLimit;
      _isLocked = _scrollCount >= _scrollLimit;
    });
    try {
      await _channel.invokeMethod('setScrollLimit', {'limit': newLimit});
      _fetchStats(showLoading: false);
    } catch (_) {}
  }

  Future<void> _resetCounter() async {
    try {
      await _channel.invokeMethod('resetScrollCount');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Today\'s scroll count reset to 0!'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
      _fetchStats(showLoading: false);
    } catch (_) {}
  }

  Future<void> _simulateScroll() async {
    try {
      final newCount = await _channel.invokeMethod<int>('simulateScroll');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Simulated 1 scroll! (Total today: $newCount / $_scrollLimit)'),
            backgroundColor: (newCount ?? 0) >= _scrollLimit
                ? const Color(0xFFEF4444)
                : const Color(0xFF6366F1),
            duration: const Duration(milliseconds: 1200),
          ),
        );
      }
      _fetchStats(showLoading: false);
    } catch (_) {}
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  Future<void> _openOverlaySettings() async {
    try {
      await _channel.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  Future<void> _openInstagram() async {
    try {
      await _channel.invokeMethod('openInstagram');
    } catch (_) {}
  }

  Future<void> _toggleDailyLimitReset(bool value) async {
    setState(() => _resetLimitDaily = value);
    try {
      await _channel.invokeMethod('setResetLimitDaily', {'enabled': value});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final double progress = _scrollLimit > 0
        ? (_scrollCount / _scrollLimit).clamp(0.0, 1.0)
        : 0.0;
    final int remaining = (_scrollLimit - _scrollCount).clamp(0, _scrollLimit);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFFCB045)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.lock_clock, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text(
              'ScrollLock',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: () => _fetchStats(showLoading: false),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchStats(showLoading: false),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  _buildSetupCard(),
                  const SizedBox(height: 16),
                  _buildLimitControlCard(),
                  const SizedBox(height: 16),
                  _buildStatsProgressCard(progress, remaining),
                  const SizedBox(height: 16),
                  _buildTestControlsCard(),
                  const SizedBox(height: 16),
                  _buildGuideCard(),
                  const SizedBox(height: 16),
                  _buildBankingTipsCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSetupCard() {
    final isReady = _isAccessibilityEnabled;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isReady ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: isReady ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  isReady ? 'Service Active & Running' : 'Setup Required',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isReady ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isReady
                  ? 'ScrollLock is actively listening for Instagram. The floating counter overlay will appear automatically when you open Instagram.'
                  : 'To count scrolls and display the overlay on top of Instagram, enable the ScrollLock Accessibility Service.',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (isReady) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openAccessibilitySettings,
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Manage / Pause Service in Settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD1D5DB),
                    side: const BorderSide(color: Color(0xFF374151)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (!isReady) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openAccessibilitySettings,
                  icon: const Icon(Icons.accessibility_new, size: 18),
                  label: const Text('Enable in Accessibility Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE1306C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (!_hasOverlayPermission) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openOverlaySettings,
                  icon: const Icon(Icons.layers, size: 18),
                  label: const Text('Grant Overlay (Draw Over Apps) Permission'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD1D5DB),
                    side: const BorderSide(color: Color(0xFF374151)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLimitControlCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Daily Scroll Limit',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF232534),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 14, color: Color(0xFF9CA3AF)),
                      SizedBox(width: 4),
                      Text(
                        'Resets Daily',
                        style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Instagram will be locked as soon as you reach this number of scrolls.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
            const SizedBox(height: 20),
            // Stepper and large number
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: _scrollLimit > 1 ? () => _updateLimit(_scrollLimit - 1) : null,
                  icon: const Icon(Icons.remove, size: 24),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF282A3A),
                    padding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(width: 24),
                Column(
                  children: [
                    Text(
                      '$_scrollLimit',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'scrolls allowed',
                      style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                IconButton.filledTonal(
                  onPressed: () => _updateLimit(_scrollLimit + 1),
                  icon: const Icon(Icons.add, size: 24),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF282A3A),
                    padding: const EdgeInsets.all(14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Quick preset chips
            const Text(
              'Quick Presets:',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [3, 5, 10, 15, 25, 50].map((preset) {
                final isSelected = _scrollLimit == preset;
                return ChoiceChip(
                  label: Text(
                    preset == 5 ? '5 (Default)' : '$preset',
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFD1D5DB),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFFE1306C),
                  backgroundColor: const Color(0xFF232534),
                  onSelected: (_) => _updateLimit(preset),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFE1306C),
                inactiveTrackColor: const Color(0xFF282A3A),
                thumbColor: const Color(0xFFFF5277),
              ),
              child: Slider(
                value: _scrollLimit.clamp(1, 100).toDouble(),
                min: 1,
                max: 100,
                divisions: 99,
                label: '$_scrollLimit scrolls',
                onChanged: (val) => _updateLimit(val.round()),
              ),
            ),
            const Divider(color: Color(0xFF282A3A), height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reset limit to default (5) daily',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _resetLimitDaily
                            ? 'Every midnight, the limit resets back to 5.'
                            : 'Keeps your custom limit every day.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _resetLimitDaily,
                  activeThumbColor: const Color(0xFFE1306C),
                  onChanged: _toggleDailyLimitReset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsProgressCard(double progress, int remaining) {
    Color progressColor = const Color(0xFF10B981);
    if (_isLocked) {
      progressColor = const Color(0xFFEF4444);
    } else if (_scrollCount >= _scrollLimit - 1 && _scrollLimit > 1) {
      progressColor = const Color(0xFFF59E0B);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Today\'s Activity',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: progressColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: progressColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _isLocked
                        ? '🔒 LOCKED'
                        : (_scrollCount >= _scrollLimit - 1 && _scrollLimit > 1
                            ? '⚠️ ALMOST REACHED'
                            : '🟢 ACTIVE'),
                    style: TextStyle(
                      color: progressColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 9,
                        backgroundColor: const Color(0xFF282A3A),
                        valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$_scrollCount',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '/ $_scrollLimit',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatItem('Scrolls Used', '$_scrollCount of $_scrollLimit'),
                      const SizedBox(height: 8),
                      _buildStatItem('Scrolls Remaining', '$remaining left'),
                      const SizedBox(height: 8),
                      _buildStatItem(
                        'Daily Reset',
                        _lastResetDate.isNotEmpty ? 'Date: $_lastResetDate' : 'At midnight',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _resetCounter,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset Today\'s Count to 0'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD1D5DB),
                  side: const BorderSide(color: Color(0xFF374151)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildTestControlsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Test & Simulation',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Simulate scrolls or launch Instagram to test the floating counter and lock overlay.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _simulateScroll,
                    icon: const Icon(Icons.touch_app, size: 18),
                    label: const Text('+1 Scroll'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF282A3A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openInstagram,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open Instagram'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE1306C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How ScrollLock Works',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildGuideStep('1', 'Floating Overlay',
                'Whenever you open Instagram, a small pill appears showing your scroll count till now (e.g. "0 / 5"). You can drag it anywhere on screen.'),
            const SizedBox(height: 10),
            _buildGuideStep('2', 'Scroll Counting',
                'Each finger swipe or feed scroll increments your counter by 1.'),
            const SizedBox(height: 10),
            _buildGuideStep('3', 'App Locking',
                'When you reach your scroll limit (default 5), Instagram is locked with a full-screen mindful break reminder.'),
            const SizedBox(height: 10),
            _buildGuideStep('4', 'Daily Reset',
                'Your scroll count resets every day at midnight so you get a fresh quota every day.'),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: const Color(0xFF282A3A),
          child: Text(
            number,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12.5, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBankingTipsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shield_outlined, color: Color(0xFF60A5FA), size: 22),
                SizedBox(width: 8),
                Text(
                  'Google Pay & Banking Apps',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'UPI and banking apps (such as Google Pay, PhonePe, Paytm) check for active Accessibility Services on sideloaded apps as a fraud-prevention measure.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155), width: 1),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🔒 Built-in Privacy & Security Guarantees:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF93C5FD)),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• Scoped to Instagram only: ScrollLock is strictly restricted to Instagram packages (com.instagram.android). It can never observe, access, or read payment screens, UPI PINs, or banking details.\n'
                    '• Overlays removed outside Instagram: Lock and floating overlays are immediately cleared when leaving Instagram, preventing touch obscuring.\n'
                    '• 100% Local: No remote databases or cloud servers.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1), height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'If Google Pay restricts payments during testing:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFE5E7EB)),
            ),
            const SizedBox(height: 4),
            const Text(
              '1. Tap below to temporarily turn off the Accessibility Service before making a transaction.\n'
              '2. If Google Pay paused UPI, restart your phone or refresh your UPI PIN inside GPay.\n'
              '3. In production, Play Store certification (Play Protect) verifies the app signature so sideload warnings do not apply.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openAccessibilitySettings,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Open Accessibility Settings to Pause'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF60A5FA),
                  side: const BorderSide(color: Color(0xFF3B82F6)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
