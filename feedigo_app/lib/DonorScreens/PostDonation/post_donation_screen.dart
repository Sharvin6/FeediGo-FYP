import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

class PostDonationScreen extends StatefulWidget {
  const PostDonationScreen({super.key});

  @override
  State<PostDonationScreen> createState() => _PostDonationScreenState();
}

class _PostDonationScreenState extends State<PostDonationScreen> {
  final _formKey = GlobalKey<FormState>();

  // controllers
  final _foodNameCtrl = TextEditingController();
  final _qtyNumberCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  DateTime? _expiryDate;
  bool _saving = false;
  File? _imageFile;

  // resolved coords for the address
  double? _lat;
  double? _lng;

  // -------- Food Type (labels exactly match Request screen) --------
  final List<Map<String, String>> _foodTypes = const [
    {'key': 'cooked', 'label': 'Cooked Meals'},
    {'key': 'produce', 'label': 'Fresh Produce'},
    {'key': 'bakery', 'label': 'Bakery'},
    {'key': 'packaged', 'label': 'Packaged / Canned'},
    {'key': 'beverage', 'label': 'Beverage'},
    {'key': 'frozen', 'label': 'Frozen / Chilled'},
    {'key': 'dry', 'label': 'Dry Goods'},
  ];
  String? _selectedFoodTypeKey;

  // Units (match Request screen)
  final List<String> _units = ['kg', 'grams', 'plates', 'bottles', 'boxes'];
  String? _selectedUnit;

  // “Use my saved address”
  bool _useProfileAddress = false;
  String? _profileAddress;
  double? _profileLat;
  double? _profileLng;

  @override
  void initState() {
    super.initState();
    _loadProfileAddress();
  }

  @override
  void dispose() {
    _foodNameCtrl.dispose();
    _qtyNumberCtrl.dispose();
    _locationCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfileAddress() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final u = snap.data() ?? {};

      // Adjust to your schema
      final isOrg = u['isOrganization'] == true;
      final addr =
          isOrg
              ? (u['organization']?['address'] as String?) ?? ''
              : (u['profile']?['address'] as String?) ?? '';

      final lat =
          isOrg
              ? (u['organization']?['lat'] as num?)
              : (u['profile']?['lat'] as num?);
      final lng =
          isOrg
              ? (u['organization']?['lng'] as num?)
              : (u['profile']?['lng'] as num?);

      if (addr.trim().isNotEmpty) {
        setState(() {
          _profileAddress = addr.trim();
          _profileLat = lat?.toDouble();
          _profileLng = lng?.toDouble();
        });
      }
    } catch (_) {
      // ignore; checkbox remains disabled
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _pickImage() async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Select Image Source'),
              content: const Text('Choose where to pick the photo from.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, ImageSource.camera),
                  child: const Text('Camera'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, ImageSource.gallery),
                  child: const Text('Gallery'),
                ),
              ],
            ),
      );

      if (source == null) return;

      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (x != null && mounted) setState(() => _imageFile = File(x.path));

      final lost = await picker.retrieveLostData();
      if (!lost.isEmpty && lost.file != null && mounted) {
        setState(() => _imageFile = File(lost.file!.path));
      }
    } catch (_) {
      _snack('Could not pick image. Please try again.');
    }
  }

  Future<String?> _uploadPhoto(String donationId) async {
    if (_imageFile == null) return null;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseStorage.instance
        .ref()
        .child('donations')
        .child(uid)
        .child('$donationId.jpg');
    final task = await ref.putFile(_imageFile!);
    return await task.ref.getDownloadURL();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFoodTypeKey == null) {
      _snack('Please select a food type.');
      return;
    }
    if (_selectedUnit == null) {
      _snack('Please select a unit.');
      return;
    }
    if (_expiryDate == null) {
      _snack('Please select an expiry date.');
      return;
    }

    setState(() => _saving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Decide the address to save & geocode
      String address = _locationCtrl.text.trim();
      double? lat;
      double? lng;

      if (_useProfileAddress && (_profileAddress?.isNotEmpty ?? false)) {
        address = _profileAddress!;
        lat = _profileLat;
        lng = _profileLng;

        // If profile has no coords, geocode now
        if (lat == null || lng == null) {
          final coords = await _geocodeAddress(address);
          lat = coords?.$1;
          lng = coords?.$2;
        }
      } else {
        // Free-typed address -> geocode
        final coords = await _geocodeAddress(address);
        lat = coords?.$1;
        lng = coords?.$2;
      }

      final doc = FirebaseFirestore.instance.collection('donations').doc();

      final foodTypeLabel =
          _foodTypes.firstWhere(
            (t) => t['key'] == _selectedFoodTypeKey,
          )['label'];

      final payload = {
        'id': doc.id, // string
        'donorId': uid, // string
        'foodName': _foodNameCtrl.text.trim(), // string
        'quantity':
            '${_qtyNumberCtrl.text.trim()} ${_selectedUnit ?? ''}', // string "N unit"
        'status': 'pending', // string
        'expiryAt': Timestamp.fromDate(
          // Firestore Timestamp (end of day)
          DateTime(
            _expiryDate!.year,
            _expiryDate!.month,
            _expiryDate!.day,
            23,
            59,
          ),
        ),
        'pickupInfo': {
          'address': address, // string
          if (lat != null) 'lat': lat.toDouble(), // double
          if (lng != null) 'lng': lng.toDouble(), // double
        },
        'description':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'photoUrl': null, // string|null
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'category': _selectedFoodTypeKey, // string key (e.g., "cooked")
        'foodTypeLabel':
            foodTypeLabel, // string label (exactly matches request screen)
      };

      await doc.set(payload);

      final url = await _uploadPhoto(doc.id);
      if (url != null) {
        await doc.update({
          'photoUrl': url,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      _snack('Donation posted successfully!');
      Navigator.pushReplacementNamed(
        context,
        '/donation_details',
        arguments: doc.id,
      );
    } catch (e) {
      _snack('Failed to post donation. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Try Cloud Function (LocationIQ). Fallback to local geocoding plugin.
  Future<(double, double)?> _geocodeAddress(String address) async {
    if (address.isEmpty) return null;

    // 1) Cloud Function (recommended — hides API key)
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('geocodeAddress');
      final res = await callable.call({'address': address});
      final map = Map<String, dynamic>.from(res.data as Map);
      final lat = (map['lat'] as num).toDouble();
      final lng = (map['lng'] as num).toDouble();
      setState(() {
        _lat = lat;
        _lng = lng;
      });
      return (lat, lng);
    } catch (_) {
      // proceed to fallback
    }

    // 2) Fallback: device geocoding
    try {
      final list = await geocoding.locationFromAddress(address);
      if (list.isNotEmpty) {
        final loc = list.first;
        setState(() {
          _lat = loc.latitude;
          _lng = loc.longitude;
        });
        return (loc.latitude, loc.longitude);
      }
    } catch (_) {
      // swallow
    }

    _snack('Could not locate that address—saved without coordinates.');
    return null;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: const Text(
          'Post Donation',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _card(
                  title: 'Food Details',
                  children: [
                    _textField(
                      label: 'Food Name *',
                      controller: _foodNameCtrl,
                      validator:
                          (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedFoodTypeKey,
                      items:
                          _foodTypes
                              .map(
                                (t) => DropdownMenuItem<String>(
                                  value: t['key']!,
                                  child: Text(t['label']!),
                                ),
                              )
                              .toList(),
                      onChanged:
                          (v) => setState(() => _selectedFoodTypeKey = v),
                      validator:
                          (v) => v == null ? 'Please select a food type' : null,
                      decoration: _inputDecoration('Food Type *'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _textField(
                            label: 'Quantity *',
                            hint: 'e.g., 5',
                            controller: _qtyNumberCtrl,
                            validator:
                                (v) =>
                                    v == null || v.trim().isEmpty
                                        ? 'Required'
                                        : null,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: _selectedUnit,
                            items:
                                _units
                                    .map(
                                      (unit) => DropdownMenuItem<String>(
                                        value: unit,
                                        child: Text(unit),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) => setState(() => _selectedUnit = v),
                            validator: (v) => v == null ? 'Select unit' : null,
                            decoration: _inputDecoration('Unit *'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _pickerField(
                      label: 'Expiry Date *',
                      value:
                          _expiryDate == null
                              ? 'Select expiry date'
                              : '${_expiryDate!.day.toString().padLeft(2, '0')}/${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year}',
                      icon: Icons.calendar_today_rounded,
                      onTap: _pickDate,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _card(
                  title: 'Pickup Information',
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _useProfileAddress,
                          onChanged:
                              (_profileAddress == null)
                                  ? null
                                  : (v) {
                                    setState(() {
                                      _useProfileAddress = v ?? false;
                                      if (_useProfileAddress) {
                                        _locationCtrl.text =
                                            _profileAddress ?? '';
                                        _lat = _profileLat;
                                        _lng = _profileLng;
                                      } else {
                                        _locationCtrl.clear();
                                        _lat = null;
                                        _lng = null;
                                      }
                                    });
                                  },
                        ),
                        Expanded(
                          child: Text(
                            _profileAddress == null
                                ? 'No saved address in your profile'
                                : 'Use my saved address',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    _textField(
                      label: 'Pickup Location *',
                      controller: _locationCtrl,
                      validator:
                          (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    if (_lat != null && _lng != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Resolved: $_lat, $_lng',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 14),
                _card(
                  title: 'Additional Information',
                  children: [
                    _textField(
                      label: 'Description (Optional)',
                      controller: _descCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    _photoPicker(onTap: _pickImage, image: _imageFile),
                  ],
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child:
                        _saving
                            ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Text('Post Donation'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- UI helpers ----
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE26A2C),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _textField({
    required String label,
    String? hint,
    int maxLines = 1,
    TextEditingController? controller,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _inputDecoration(label).copyWith(hintText: hint),
    );
  }

  Widget _pickerField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: _inputDecoration(label),
        child: Row(
          children: [
            Expanded(
              child: Text(value, style: const TextStyle(color: Colors.black87)),
            ),
            Icon(icon, color: Colors.black54),
          ],
        ),
      ),
    );
  }

  Widget _photoPicker({required VoidCallback onTap, File? image}) {
    final hasImage = image != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child:
              hasImage
                  ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      image!,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.add_a_photo_outlined,
                        color: Color(0xFFE26A2C),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Tap to upload photo',
                        style: TextStyle(color: Colors.black54),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Optional but recommended',
                        style: TextStyle(color: Colors.black38, fontSize: 12),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}
