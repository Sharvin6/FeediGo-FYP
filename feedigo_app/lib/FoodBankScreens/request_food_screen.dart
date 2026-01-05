/*
  RequestFoodScreen: 

  Purpose:
  - Allows food banks to request bulk food donations.
  - Supports selecting food type, quantity, and pickup address.
  - Validates minimum bulk quantities and uses saved addresses from user profile.
  - Resolves address to coordinates (latitude/longitude) using geocoding.
  - Sends request to a Firebase Cloud Function for matching donations.

  Key Technical Points:
  1. StatefulWidget:- Maintains form state, user input, loading state, and resolved coordinates.
  2. FirebaseAuth:- Retrieves current user UID to fetch saved address and profile.
  3. FirebaseFirestore:- Retrieves user profile and organization info for saved address and lat/lng.
  4. Cloud Functions (FirebaseFunctions):- Calls 'matchDonations' HTTPS callable function to find matching food donations.
  5. Form Validation:- Validates selected food type, numeric quantity, and minimum bulk amounts per unit.
  6. Geocoding:- Converts textual addresses into latitude/longitude using geocoding package.
  7. UI Components:
     - TextFormField, DropdownButtonFormField, SwitchListTile, ElevatedButton.
     - Shows resolved coordinates if available.
     - Dynamically updates UI when switching between saved address and manual input.
  8. State Management:- Uses setState() to manage form, busy/loading states, and address updates.
  9. Async Handling:- Async loading of saved address, geocoding, and cloud function call with proper mounted checks.
  10. Bulk Quantities:- Minimum bulk quantities enforced via _minBulkByUnit Map.
*/

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
  // Form key to validate inputs
  final _formKey = GlobalKey<FormState>();

  // Controllers for quantity and address input
  final _qtyValueCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Food type options
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

  // Quantity unit selection
  String _qtyUnit = 'kg';
  final List<String> _qtyUnits = const [
    'kg',
    'grams',
    'plates',
    'bottles',
    'boxes',
  ];

  // Minimum bulk per unit
  final Map<String, double> _minBulkByUnit = const {
    'kg': 5,
    'grams': 500,
    'plates': 10,
    'bottles': 10,
    'boxes': 2,
  };

  // Saved address state
  bool _useSavedAddress = true;
  String? _savedAddress;
  double? _savedLat;
  double? _savedLng;
  bool _loadingSaved = true;

  // Current address coordinates
  double? _lat;
  double? _lng;

  // Busy state for submit button
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

  /// Loads saved address and coordinates from user profile
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

        // Populate form fields if using saved address
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

            // Minimum bulk warning
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

            // Food type selection
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

            // Quantity input
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
                      errorMaxLines: 2,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty)
                        return 'Enter quantity';
                      final n = double.tryParse(v.trim());
                      if (n == null || n <= 0) return 'Invalid number';
                      final min = _minBulkByUnit[_qtyUnit]!;
                      if (n < min) return 'Min. $min $_qtyUnit required';
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

            // Use saved address switch
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

            // Address input
            _label('Pickup Location'),
            TextFormField(
              controller: _addressCtrl,
              readOnly: _useSavedAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

            // Display resolved coordinates
            if (_lat != null && _lng != null) ...[
              const SizedBox(height: 6),
              Text(
                'Resolved: ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],

            const SizedBox(height: 18),

            // Submit button
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

  /// Convert address to latitude/longitude using geocoding package
  Future<(double, double)?> _geocode(String address) async {
    try {
      final list = await geocoding.locationFromAddress(address);
      if (list.isEmpty) return null;
      return (list.first.latitude, list.first.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Submit request to Cloud Function and navigate to match results
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);

    try {
      final qtyValue = double.parse(_qtyValueCtrl.text.trim());
      final address = _addressCtrl.text.trim();

      // Force geocoding if not resolved yet
      if ((_lat == null || _lng == null) && address.isNotEmpty) {
        final p = await _geocode(address);
        if (p != null) {
          setState(() {
            _lat = p.$1;
            _lng = p.$2;
          });
        }
      }

      // Call Firebase Cloud Function for donation matching
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

      await Future.delayed(
        const Duration(milliseconds: 800),
      ); // allow lat/lng display

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
