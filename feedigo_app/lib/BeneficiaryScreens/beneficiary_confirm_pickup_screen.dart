// lib/screens/beneficiary_confirm_pickup_screen.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Beneficiary variant of ConfirmPickupScreen
class BeneficiaryConfirmPickupScreen extends StatefulWidget {
  const BeneficiaryConfirmPickupScreen({super.key});

  @override
  State<BeneficiaryConfirmPickupScreen> createState() =>
      _BeneficiaryConfirmPickupScreenState();
}

class _BeneficiaryConfirmPickupScreenState
    extends State<BeneficiaryConfirmPickupScreen> {
  late final String donationId;
  bool _gotArgs = false;
  bool _readOnly = false;

  final _noteCtrl = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _photos = []; // for new uploads (edit mode)
  List<String> _savedUrls = const []; // for viewing existing proofs
  bool _seededFromProof = false; // avoid re-seeding controller each build

  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gotArgs) return;

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map) {
      donationId = (args['donationId'] as String?) ?? '';
      _readOnly = (args['readOnly'] as bool?) ?? false;
    } else if (args is String) {
      donationId = args;
      _readOnly = false;
    } else {
      donationId = '';
      _readOnly = false;
    }

    _gotArgs = true;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);

    if (donationId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Invalid donation id')));
    }

    final donationRef =
        FirebaseFirestore.instance.collection('donations').doc(donationId);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: Text(_readOnly ? 'Pickup Proof' : 'Confirm Pickup'),
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: donationRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _center('Error: ${snap.error}');
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          // Read saved proof if any
          final data = snap.data!.data()!;
          final proof = (data['pickupProof'] as Map?)?.cast<String, dynamic>();
          final savedNote = (proof?['note'] as String?) ?? '';
          final savedUrls =
              (proof?['photos'] as List?)?.map((e) => e.toString()).toList() ??
                  const <String>[];

          // In read-only mode, seed UI once with saved data
          if (_readOnly && !_seededFromProof) {
            _noteCtrl.text = savedNote;
            _savedUrls = savedUrls;
            _seededFromProof = true;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const Text(
                'Add Proof of Pickup',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 8),

              if (_readOnly)
                const Text(
                  'Read-only view of the proof attached when the pickup was completed.',
                  style: TextStyle(color: Colors.black54),
                ),

              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                enabled: !_readOnly,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText:
                      'Optional note (e.g., who received it, condition)…',
                ),
              ),
              const SizedBox(height: 12),

              if (!_readOnly)
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Add Photos'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _pickFromCamera,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                    ),
                  ],
                ),

              const SizedBox(height: 12),

              // Photos section:
              if (_readOnly)
                _SavedProofGrid(urls: _savedUrls)
              else
                (_photos.isEmpty)
                    ? const Text(
                        'No photos selected. You can still complete without photos.',
                        style: TextStyle(color: Colors.black54),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _photos
                            .map(
                              (x) => Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(x.path),
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Material(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      onTap: _busy
                                          ? null
                                          : () => setState(() {
                                                _photos.remove(x);
                                              }),
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),

              const SizedBox(height: 24),

              if (!_readOnly)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : () => _markComplete(donationRef),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Mark Complete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // --------- pick/upload helpers ---------

  Future<void> _pickFromGallery() async {
    final result = await _picker.pickMultiImage(imageQuality: 85);
    if (result.isNotEmpty) {
      setState(() => _photos.addAll(result));
    }
  }

  Future<void> _pickFromCamera() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (x != null) setState(() => _photos.add(x));
  }

  Future<void> _markComplete(
    DocumentReference<Map<String, dynamic>> donationRef,
  ) async {
    setState(() => _busy = true);
    try {
      // 1) Upload photos (optional)
      final List<String> urls = [];
      if (_photos.isNotEmpty) {
        final storage = FirebaseStorage.instance;
        int i = 0;
        for (final x in _photos) {
          final path =
              'donations/$donationId/proofs/${DateTime.now().millisecondsSinceEpoch}_${i++}.jpg';
          final task = await storage.ref(path).putFile(File(x.path));
          final url = await task.ref.getDownloadURL();
          urls.add(url);
        }
      }

      // 2) Save proof + complete
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      batch.update(donationRef, {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'pickupProof': {
          'note': _noteCtrl.text.trim(),
          'photos': urls,
          'addedAt': FieldValue.serverTimestamp(),
          'by': FirebaseAuth.instance.currentUser?.uid,
        },
      });

      // Update my request status to completed (if present)
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final reqSnap = await db
            .collection('donation_requests')
            .where('donationId', isEqualTo: donationId)
            .where('recipientId', isEqualTo: uid)
            .limit(1)
            .get();
        if (reqSnap.docs.isNotEmpty) {
          batch.update(reqSnap.docs.first.reference, {
            'status': 'completed',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      if (!mounted) return;
      _toast('Pickup marked as completed!');
      Navigator.pop(context); // back to details
    } catch (e) {
      if (!mounted) return;
      _toast('Failed to complete: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------- small ui helpers ---------

  Widget _center(String t) =>
      Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(t)));

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

// Grid to show saved proof photos (read-only)
class _SavedProofGrid extends StatelessWidget {
  final List<String> urls;
  const _SavedProofGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const Text(
        'No photos attached for this pickup.',
        style: TextStyle(color: Colors.black54),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: urls.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (_, i) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(urls[i], fit: BoxFit.cover),
      ),
    );
  }
}
