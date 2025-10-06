// lib/screens/request_food_screen.dart
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

  // controllers
  final _qtyValueCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Food type options — EXACTLY the same labels used when donors post
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

  // quantity
  String _qtyUnit = 'kg';
  final List<String> _qtyUnits = const [
    'kg',
    'grams',
    'plates',
    'bottles',
    'boxes',
  ];

  // saved address toggle
  bool _useSavedAddress = true;
  String? _savedAddress;
  double? _savedLat;
  double? _savedLng;
  bool _loadingSaved = true;

  // coords to send with the request (resolved from saved or typed address)
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

        // Try common locations in your schema
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

        // if toggle ON and we have saved address, pre-fill & set coords
        if (_useSavedAddress && _savedAddress != null) {
          _addressCtrl.text = _savedAddress!;
          _lat = _savedLat;
          _lng = _savedLng;
        }
      } else {
        _savedAddress = null;
        _savedLat = null;
        _savedLng = null;
      }
    } catch (_) {
      _savedAddress = null;
      _savedLat = null;
      _savedLng = null;
    } finally {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        title: const Text(
          'Request Food',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Text(
              'Fill out the details below to get the best matches.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),

            // Food type — matches donor labels
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

            // Quantity (number + unit)
            _label('Quantity Needed'),
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
                      hintText: 'e.g., 2.5',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty)
                        return 'Enter a quantity';
                      final n = double.tryParse(v.trim());
                      if (n == null || n <= 0) return 'Enter a valid number';
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
                    onChanged: (v) => setState(() => _qtyUnit = v ?? _qtyUnit),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Location choice
            if (_loadingSaved)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else
              SwitchListTile(
                value: _useSavedAddress,
                onChanged: (val) {
                  setState(() {
                    _useSavedAddress = val;
                    if (_useSavedAddress) {
                      if (_savedAddress != null) {
                        _addressCtrl.text = _savedAddress!;
                        _lat = _savedLat;
                        _lng = _savedLng;
                      } else {
                        _addressCtrl.clear();
                        _lat = null;
                        _lng = null;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No saved address found. Please enter one.',
                            ),
                          ),
                        );
                      }
                    } else {
                      _addressCtrl.clear();
                      _lat = null;
                      _lng = null;
                    }
                  });
                },
                title: const Text('Use my saved address'),
                subtitle: Text(
                  _savedAddress ?? 'No saved address',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            _label('Pickup Location'),
            TextFormField(
              controller: _addressCtrl,
              readOnly: _useSavedAddress,
              decoration: InputDecoration(
                hintText:
                    _useSavedAddress
                        ? 'Using your saved address'
                        : 'Enter pickup address (optional)',
                border: const OutlineInputBorder(),
                isDense: true,
                fillColor: _useSavedAddress ? const Color(0xFFEFF1F4) : null,
                filled: _useSavedAddress,
              ),
            ),
            if (_lat != null && _lng != null) ...[
              const SizedBox(height: 6),
              Text(
                'Resolved: ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
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

  // UI helpers
  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  /// Try to geocode the given [address]. Returns (lat, lng) or null.
  Future<(double, double)?> _geocode(String address) async {
    try {
      if (address.trim().isEmpty) return null;
      final list = await geocoding.locationFromAddress(address);
      if (list.isEmpty) return null;
      final loc = list.first;
      return (loc.latitude, loc.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_useSavedAddress && (_savedAddress == null || _savedAddress!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No saved address found—please type an address.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      // Ensure we have coordinates to send (better UX & reliable distance calc)
      String address = _addressCtrl.text.trim();
      double? lat = _lat;
      double? lng = _lng;

      if (_useSavedAddress) {
        if ((lat == null || lng == null) &&
            (_savedAddress?.isNotEmpty ?? false)) {
          final p = await _geocode(_savedAddress!);
          if (p != null) {
            lat = p.$1;
            lng = p.$2;
            setState(() {
              _lat = lat;
              _lng = lng;
            });
          }
        }
      } else {
        if ((lat == null || lng == null) && address.isNotEmpty) {
          final p = await _geocode(address);
          if (p != null) {
            lat = p.$1;
            lng = p.$2;
            setState(() {
              _lat = lat;
              _lng = lng;
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not locate that address—continuing without distance.',
                ),
              ),
            );
          }
        }
      }

      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('matchDonations');

      final qtyValue = double.parse(_qtyValueCtrl.text.trim());

      final payload = {
        'requestedFoodType': _foodType, // <-- exact label match with donations
        'qtyValue': qtyValue,
        'qtyUnit': _qtyUnit,
        'qtyNeed': '${_qtyValueCtrl.text.trim()} $_qtyUnit',
        'address': address, // server can geocode if needed
        'lat': lat,
        'lng': lng,
        'topK': 5,
      };

      final res = await callable.call(payload);
      final matches = (res.data['matches'] as List).cast<Map>().toList();

      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/match_results',
        arguments: {
          'query': {
            'foodType': _foodType,
            'qtyValue': qtyValue,
            'qtyUnit': _qtyUnit,
            'address': address,
            'needByDate': payload['needByDate'],
          },
          'matches': matches,
        },
      );
    } on FirebaseFunctionsException catch (e) {
      final msg = 'Code: ${e.code}  Message: ${e.message ?? ''}';
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to match: $msg')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to match: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
