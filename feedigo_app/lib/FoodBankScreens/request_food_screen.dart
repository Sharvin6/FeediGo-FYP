import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

class RequestFoodScreen extends StatefulWidget {
  const RequestFoodScreen({super.key});

  @override
  State<RequestFoodScreen> createState() => _RequestFoodScreenState();
}

class _RequestFoodScreenState extends State<RequestFoodScreen> {
  final _formKey = GlobalKey<FormState>();

  final _qtyValueCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  static const List<String> _foodTypeOptions = [
    'Cooked Meals',
    'Fresh Produce',
    'Bakery',
    'Packaged / Canned',
    'Beverage',
    'Frozen / Chilled',
    'Dry Goods',
  ];
  String? _foodType;

  String _qtyUnit = 'kg';
  final List<String> _qtyUnits = const [
    'kg',
    'grams',
    'plates',
    'bottles',
    'boxes',
  ];

  final Map<String, double> _minBulkByUnit = const {
    'kg': 5,
    'grams': 500,
    'plates': 10,
    'bottles': 10,
    'boxes': 2,
  };

  bool _useSavedAddress = true;
  String? _savedAddress;
  double? _savedLat;
  double? _savedLng;
  bool _loadingSaved = true;

  double? _lat;
  double? _lng;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAddress();
  }

  @override
  void dispose() {
    _qtyValueCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddress() async {
    setState(() => _loadingSaved = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final u = snap.data() ?? {};

        final org = (u['organization'] as Map?) ?? {};
        final prof = (u['profile'] as Map?) ?? {};

        String? addr =
            (org['address'] as String?) ??
            (prof['address'] as String?) ??
            (u['address'] as String?);

        final latNum = (org['lat'] as num?) ?? (prof['lat'] as num?);
        final lngNum = (org['lng'] as num?) ?? (prof['lng'] as num?);

        addr = (addr ?? '').trim();
        _savedAddress = addr.isEmpty ? null : addr;
        _savedLat = latNum?.toDouble();
        _savedLng = lngNum?.toDouble();

        if (_useSavedAddress && _savedAddress != null) {
          _addressCtrl.text = _savedAddress!;
          _lat = _savedLat;
          _lng = _savedLng;
        }
      }
    } finally {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        title: const Text(
          'Request Food',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Text(
              'Food banks request food in bulk quantities.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠ Minimum bulk quantities apply to ensure efficient food distribution.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),

            _label('Food Type'),
            DropdownButtonFormField<String>(
              value: _foodType,
              items:
                  _foodTypeOptions
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
              onChanged: (v) => setState(() => _foodType = v),
              validator: (v) => v == null ? 'Please choose a food type' : null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),

            _label('Quantity Needed (Bulk)'),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _qtyValueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'e.g. 10',
                      border: OutlineInputBorder(),
                      isDense: true,
                      // ADD THIS LINE BELOW
                      errorMaxLines: 2,
                      // This allows the error text to wrap to a second line instead of clipping
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter quantity';
                      }
                      final n = double.tryParse(v.trim());
                      if (n == null || n <= 0) {
                        return 'Invalid number';
                      }
                      final min = _minBulkByUnit[_qtyUnit]!;
                      if (n < min) {
                        // Shortening the text slightly also helps prevent overflow
                        return 'Min. $min $_qtyUnit required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: _qtyUnit,
                    items:
                        _qtyUnits
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _qtyUnit = v!),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_loadingSaved)
              const LinearProgressIndicator(minHeight: 2)
            else
              SwitchListTile(
                value: _useSavedAddress,
                onChanged: (v) {
                  setState(() {
                    _useSavedAddress = v;
                    if (v && _savedAddress != null) {
                      _addressCtrl.text = _savedAddress!;
                      _lat = _savedLat;
                      _lng = _savedLng;
                    } else {
                      _addressCtrl.clear();
                      _lat = null;
                      _lng = null;
                    }
                  });
                },
                title: const Text('Use my saved address'),
                subtitle: Text(_savedAddress ?? 'No saved address'),
              ),

            _label('Pickup Location'),
            TextFormField(
              controller: _addressCtrl,
              readOnly: _useSavedAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

            // ✅ LAT / LNG DISPLAY (NEW)
            if (_lat != null && _lng != null) ...[
              const SizedBox(height: 6),
              Text(
                'Resolved: ${_lat!.toStringAsFixed(6)}, '
                '${_lng!.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],

            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.search),
                label: const Text('Submit Request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.white,
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

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  Future<(double, double)?> _geocode(String address) async {
    try {
      final list = await geocoding.locationFromAddress(address);
      if (list.isEmpty) return null;
      return (list.first.latitude, list.first.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);

    try {
      final qtyValue = double.parse(_qtyValueCtrl.text.trim());
      final address = _addressCtrl.text.trim();

      // 🔹 FORCE geocoding BEFORE navigation
      if ((_lat == null || _lng == null) && address.isNotEmpty) {
        final p = await _geocode(address);
        if (p != null) {
          setState(() {
            _lat = p.$1;
            _lng = p.$2;
          });
        }
      }

      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('matchDonations');

      final res = await callable.call({
        'requestedFoodType': _foodType,
        'qtyValue': qtyValue,
        'qtyUnit': _qtyUnit,
        'qtyNeed': '${_qtyValueCtrl.text.trim()} $_qtyUnit',
        'address': address,
        'lat': _lat,
        'lng': _lng,
        'isBulkRequest': true,
        'topK': 5,
      });

      final matches = (res.data['matches'] as List).cast<Map>();

      if (!mounted) return;

      // 🔹 delay so lat/lng is visible
      await Future.delayed(const Duration(milliseconds: 800));

      Navigator.pushNamed(
        context,
        '/match_results',
        arguments: {
          'query': {
            'foodType': _foodType,
            'qtyValue': qtyValue,
            'qtyUnit': _qtyUnit,
            'address': address,
          },
          'matches': matches,
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
