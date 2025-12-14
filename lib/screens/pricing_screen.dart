import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen> {
  bool _trialActive = false;
  DateTime? _trialExpires;
  int _trialCredits = 0;
  bool _trialUsed = false;

  static const _kTrialDays = 14;
  static const _kTrialCredits = 50;

  @override
  void initState() {
    super.initState();
    _loadTrialState();
  }

  Future<void> _loadTrialState() async {
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getBool('trial_used') ?? false;
    final expiresMs = prefs.getInt('trial_expires');
    final credits = prefs.getInt('trial_credits') ?? 0;
    if (expiresMs != null) {
      final expires = DateTime.fromMillisecondsSinceEpoch(expiresMs);
      final now = DateTime.now();
      if (expires.isAfter(now)) {
        setState(() {
          _trialActive = true;
          _trialExpires = expires;
          _trialCredits = credits;
          _trialUsed = used;
        });
        return;
      }
    }
    setState(() {
      _trialActive = false;
      _trialExpires = null;
      _trialCredits = 0;
      _trialUsed = used;
    });
  }

  Future<void> _startTrial() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool('trial_used') ?? false) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Trial already used')));
      return;
    }
    final expires = DateTime.now().add(const Duration(days: _kTrialDays));
    await prefs.setBool('trial_used', true);
    await prefs.setInt('trial_expires', expires.millisecondsSinceEpoch);
    await prefs.setInt('trial_credits', _kTrialCredits);
    if (!mounted) return;
    setState(() {
      _trialUsed = true;
      _trialActive = true;
      _trialExpires = expires;
      _trialCredits = _kTrialCredits;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Free trial started — enjoy 14 days and 50 credits!'),
        ),
      );
    }
  }

  String _trialRemainingText() {
    if (!_trialActive || _trialExpires == null) return 'No active trial';
    final days = _trialExpires!.difference(DateTime.now()).inDays;
    if (days <= 0) return 'Expires today';
    return '$days day${days > 1 ? 's' : ''} left • $_trialCredits credits';
  }

  Future<void> _consumeTrialCredits(int amount) async {
    if (!_trialActive) return;
    final prefs = await SharedPreferences.getInstance();
    final remaining = (prefs.getInt('trial_credits') ?? _trialCredits) - amount;
    final newRemaining = remaining.clamp(0, 99999);
    await prefs.setInt('trial_credits', newRemaining);
    if (newRemaining <= 0) {
      // expire trial early when credits exhausted
      await prefs.remove('trial_expires');
      if (!mounted) return;
      setState(() {
        _trialActive = false;
        _trialExpires = null;
        _trialCredits = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trial credits exhausted')),
        );
      }
      return;
    }
    setState(() {
      _trialCredits = newRemaining;
    });
  }

  Widget _buildTier({
    required String title,
    required String price,
    required String subtitle,
    required List<String> bullets,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    price,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            ...bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Choose', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditsRow(
    BuildContext context,
    String label,
    String price,
    VoidCallback onTap,
  ) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        elevation: 2,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Text(price, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans & Credits'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Pricing Screen',
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).appBarTheme.foregroundColor ??
                    Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Simple Pricing',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Easy. Affordable. Try before you buy.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),

              if (_trialActive) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade100),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.celebration, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Free trial active — ${_trialRemainingText()}',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Trial info')),
                            ),
                        child: const Text('Details'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                if (!_trialUsed)
                  Card(
                    color: Colors.yellow.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Start a 14‑day free trial and get 50 credits — one time only',
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _startTrial,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                            child: const Text('Start Free Trial'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],

              // Free tier
              _buildTier(
                title: 'Free',
                price: 'Free',
                subtitle: 'Basic on‑device organization and preview tags',
                bullets: [
                  'Auto preview tags (on‑device)',
                  'Auto clustering and basic search',
                  'Local face enrollment (private)',
                ],
                color: Colors.blueAccent,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('You are on Free plan')),
                ),
              ),
              const SizedBox(height: 12),

              // Pro one-time
              _buildTier(
                title: 'Pro (one‑time)',
                price: r'$9.99',
                subtitle: 'Unlock advanced tools + 50 starter credits',
                bullets: [
                  'Batch actions & advanced tools',
                  '50 starter credits for enhanced scans',
                  'Keep Pro forever (fair‑use applies)',
                ],
                color: Colors.deepPurple,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pro unlock simulated')),
                ),
              ),
              const SizedBox(height: 12),

              // Subscription
              _buildTier(
                title: 'Premium (monthly)',
                price: r'$4.99/mo',
                subtitle:
                    'For frequent users who want priority and large quota',
                bullets: [
                  '2,000 enhanced scans per month',
                  'Priority processing and discounts on extra credits',
                  'Cancel anytime',
                ],
                color: Colors.teal,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Subscription flow simulated')),
                ),
              ),

              const SizedBox(height: 18),
              const Text(
                'Credits',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              _buildCreditsRow(context, '10 credits', r'$1.99', () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                if (_trialActive && _trialCredits >= 10) {
                  final use = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Use trial credits?'),
                      content: Text(
                        'You have $_trialCredits trial credits. Use 10 of them for this action?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Use'),
                        ),
                      ],
                    ),
                  );
                  if (!mounted) return;
                  if (use == true) {
                    await _consumeTrialCredits(10);
                    return;
                  }
                }
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Bought 10 credits (simulated)'),
                  ),
                );
              }),
              const SizedBox(height: 8),
              _buildCreditsRow(
                context,
                '50 credits (+bundle)',
                r'$7.99',
                () async {
                  if (_trialActive && _trialCredits >= 50) {
                    await _consumeTrialCredits(50);
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Bought 50 credits (simulated)'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildCreditsRow(
                context,
                '200 credits (best value)',
                r'$24.99',
                () async {
                  if (_trialActive && _trialCredits >= 200) {
                    await _consumeTrialCredits(200);
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Bought 200 credits (simulated)'),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'How credits map to actions',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('• Common item/photo: 1 credit'),
                      Text(
                        '• Family member / pet: 1 credit (server enhancement)',
                      ),
                      Text('• Food / species / events: 2 credits'),
                      Text('• Small batch (up to 10 photos): 5 credits'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
