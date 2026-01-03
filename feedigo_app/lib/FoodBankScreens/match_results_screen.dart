import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MatchResultsScreen extends StatelessWidget {
  const MatchResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final query = (args['query'] as Map?) ?? {};
    final matches = ((args['matches'] as List?) ?? []).cast<Map>();

    const orange = Color.fromARGB(255, 255, 109, 36);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        title: const Text(
          'Match Results',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _queryCard(query),
          const SizedBox(height: 12),
          if (matches.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No good matches right now. Try adjusting filters.',
                ),
              ),
            )
          else
            ...matches.map((m) => _matchTile(context, m)).toList(),
        ],
      ),
    );
  }

  Widget _queryCard(Map q) {
    final qtyValue = (q['qtyValue'] ?? '').toString();
    final qtyUnit = (q['qtyUnit'] ?? '').toString();
    final needByIso = (q['needByDate'] ?? '').toString();
    final needBy = needByIso.isNotEmpty ? DateTime.tryParse(needByIso) : null;

    return Container(
      padding: const EdgeInsets.all(14),
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
          const Text(
            'Your Request',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('Food type: ${q['foodType'] ?? '-'}'),
          Text(
            'Quantity: ${qtyValue.isEmpty ? '-' : '$qtyValue ${qtyUnit.isEmpty ? '' : qtyUnit}'}',
          ),
          if ((q['address'] ?? '').toString().isNotEmpty)
            Text('Pickup: ${q['address']}'),
          if (needBy != null) Text('Need by: ${_ddmmyyyy(needBy)}'),
        ],
      ),
    );
  }

  Widget _matchTile(BuildContext context, Map m) {
    final donationId = (m['donationId'] ?? '').toString();
    final title = (m['title'] ?? 'Donation') as String;
    final foodType = (m['foodType'] ?? '') as String;
    final qtyOffer = (m['qtyOffer'] ?? '').toString();
    final distanceKm = (m['distanceKm']);
    final expiryIso = (m['expiryDate'] ?? '') as String;
    final needByIso = (m['needByDate'] ?? '') as String;
    final expVsNeed = (m['expiryVsNeedDays'] as num?)?.toInt();
    final address = (m['address'] ?? '') as String;
    final score = ((m['score'] ?? 0.0) as num).toDouble();

    final distanceStr =
        (distanceKm is num)
            ? '${(distanceKm as num).toDouble().toStringAsFixed(1)} km away'
            : 'distance unknown';

    final expiry = expiryIso.isNotEmpty ? DateTime.tryParse(expiryIso) : null;
    final needBy = needByIso.isNotEmpty ? DateTime.tryParse(needByIso) : null;

    String expiryLine;
    if (expiry != null && needBy != null && expVsNeed != null) {
      String note;
      if (expVsNeed == 0)
        note = '— same day as your need-by';
      else if (expVsNeed > 0)
        note = '— ${expVsNeed.abs()} day(s) after your need-by';
      else
        note = '— ${expVsNeed.abs()} day(s) before your need-by';
      final daysLeft = expiry.difference(DateTime.now()).inDays;
      expiryLine =
          'Expires on ${_ddmmyyyy(expiry)} (${daysLeft.abs()} day${daysLeft.abs() == 1 ? '' : 's'} left $note)';
    } else if (expiry != null) {
      final daysLeft = expiry.difference(DateTime.now()).inDays;
      expiryLine =
          'Expires on ${_ddmmyyyy(expiry)} (${daysLeft.abs()} day${daysLeft.abs() == 1 ? '' : 's'} left)';
    } else {
      expiryLine = 'Expiry unknown';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Score ${(score * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Color(0xFF0277BD),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (foodType.isNotEmpty)
                Text(foodType, style: const TextStyle(color: Colors.black54)),
              if (qtyOffer.isNotEmpty)
                Text(
                  'Offer: $qtyOffer',
                  style: const TextStyle(color: Colors.black54),
                ),
              Text(distanceStr, style: const TextStyle(color: Colors.black54)),
              Text(expiryLine, style: const TextStyle(color: Colors.black54)),
            ],
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(address, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: address.isEmpty ? null : () => _openMaps(address),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('View Map'),
              ),
              OutlinedButton(
                onPressed:
                    () => Navigator.pushNamed(
                      context,
                      '/fb_donation_details',
                      arguments: donationId,
                    ),
                child: const Text('View Details'),
              ),
              ElevatedButton(
                onPressed:
                    () => Navigator.pushNamed(
                      context,
                      '/fb_donation_details',
                      arguments: donationId,
                    ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE26A2C),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Request'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _ddmmyyyy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _openMaps(String address) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
