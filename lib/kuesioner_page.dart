import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class KuesionerPage extends StatefulWidget {
  const KuesionerPage({super.key});

  @override
  State<KuesionerPage> createState() => _KuesionerPageState();
}

class _KuesionerPageState extends State<KuesionerPage> {
  final List<String> _defaultQuestions = [
    "Apakah pasien dalam kondisi kritis yang membahayakan nyawa?",
    "Apakah pasien membutuhkan darah dalam waktu kurang dari 24 jam?",
    "Apakah pasien akan segera menjalani operasi besar?",
    "Apakah pasien mengalami pendarahan berat atau trauma parah?",
    "Apakah hemoglobin (Hb) pasien berada di bawah 7 g/dL?",
    "Apakah ini kebutuhan mendesak untuk kasus gawat darurat (ICU/UGD)?",
    "Apakah golongan darah pasien termasuk golongan darah langka (Rhesus negatif)?",
    "Apakah pasien memiliki penyakit anemia berat yang mengancam jiwa?",
    "Apakah dokter menyatakan kebutuhan darah sangat mendesak?",
    "Apakah ketersediaan darah di rumah sakit atau PMI sedang kosong?"
  ];

  List<Map<String, dynamic>> _questions = [];
  List<bool?> _answers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('kuesioner_syarat').orderBy('order').get();
      if (snapshot.docs.isEmpty) {
        // Seed database dengan kategori default: Lolos
        final batch = FirebaseFirestore.instance.batch();
        for (var i = 0; i < _defaultQuestions.length; i++) {
          final docRef = FirebaseFirestore.instance.collection('kuesioner_syarat').doc('q${i + 1}');
          batch.set(docRef, {'text': _defaultQuestions[i], 'order': i, 'category': 'Lolos'});
        }
        await batch.commit();
        
        if (mounted) {
          setState(() {
            _questions = _defaultQuestions.map((q) => {'text': q, 'category': 'Lolos'}).toList();
            _answers = List.filled(_questions.length, null);
            _isLoading = false;
          });
        }
      } else {
        final docs = snapshot.docs;
        if (mounted) {
          setState(() {
            _questions = docs.map((d) => {
              'text': d.data()['text']?.toString() ?? "Pertanyaan",
              'category': d.data()['category']?.toString() ?? "Lolos",
            }).toList();
            _answers = List.filled(_questions.length, null);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _questions = _defaultQuestions.map((q) => {'text': q, 'category': 'Lolos'}).toList();
          _answers = List.filled(_questions.length, null);
          _isLoading = false;
        });
      }
    }
  }

  String _evaluateResult(String category, bool answer) {
    if (category == 'Lolos') return answer ? 'Lolos' : 'Tunda';
    if (category == 'Tunda') return answer ? 'Tunda' : 'Lolos';
    if (category == 'Ditolak') return answer ? 'Ditolak' : 'Lolos';
    return 'Lolos';
  }

  void _submit() {
    if (_answers.contains(null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Harap jawab semua pertanyaan.")),
      );
      return;
    }

    final List<Map<String, String>> jawabanLengkap = [];
    int lolosCount = 0;
    int tundaCount = 0;
    int tolakCount = 0;

    for (int i = 0; i < _questions.length; i++) {
      final String category = _questions[i]['category'];
      final bool answer = _answers[i]!;
      final String result = _evaluateResult(category, answer);

      if (result == 'Lolos') lolosCount++;
      if (result == 'Tunda') tundaCount++;
      if (result == 'Ditolak') tolakCount++;

      jawabanLengkap.add({
        'pertanyaan': _questions[i]['text'],
        'kategori': category,
        'jawaban': answer ? 'Ya' : 'Tidak',
        'hasil': result,
      });
    }

    // Penentuan Status Akhir
    String statusAkhir = "Lolos";
    if (tolakCount > 0) {
      statusAkhir = "Ditolak";
    } else if (tundaCount > 0) {
      statusAkhir = "Tunda";
    }

    Navigator.pop(context, {
      'status': statusAkhir,
      'lolosCount': lolosCount,
      'tundaCount': tundaCount,
      'tolakCount': tolakCount,
      'jawaban': jawabanLengkap,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kuesioner Kelayakan"),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF6F6F6),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.red.shade50,
                  width: double.infinity,
                  child: const Text(
                    "Jawablah pertanyaan berikut dengan jujur untuk menilai kelayakan donor darah.",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _questions.length,
                    itemBuilder: (context, index) {
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${index + 1}. ${_questions[index]['text']}",
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              const SizedBox(height: 8),
                              RadioGroup<bool>(
                                groupValue: _answers[index],
                                onChanged: (val) => setState(() => _answers[index] = val),
                                child: const Row(
                                  children: [
                                    Expanded(
                                      child: RadioListTile<bool>(
                                        title: Text("Iya"),
                                        value: true,
                                        activeColor: Colors.red,
                                      ),
                                    ),
                                    Expanded(
                                      child: RadioListTile<bool>(
                                        title: Text("Tidak"),
                                        value: false,
                                        activeColor: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _answers.contains(null) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade400,
                        disabledForegroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Selesai & Simpan", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
