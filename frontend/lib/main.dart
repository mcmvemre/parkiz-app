import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const ParkizApp());
}

class ParkizApp extends StatelessWidget {
  const ParkizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parkiz App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ParkMapScreen(),
    );
  }
}

class ParkMapScreen extends StatefulWidget {
  const ParkMapScreen({super.key});

  @override
  State<ParkMapScreen> createState() => _ParkMapScreenState();
}

class _ParkMapScreenState extends State<ParkMapScreen> {
  final String _backendUrl = 'https://parkiz-app.onrender.com/api/parks';
  
  List<dynamic> _parks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchParks();
  }

  Future<void> _fetchParks() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(_backendUrl));
      if (response.statusCode == 200) {
        setState(() {
          _parks = json.decode(utf8.decode(response.bodyBytes));
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parkiz - Canlı Harita'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchParks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              options: MapOptions(
                initialCenter: _parks.isNotEmpty
                    ? LatLng((_parks[0]['latitude'] as num).toDouble(), (_parks[0]['longitude'] as num).toDouble())
                    : const LatLng(40.9822, 29.0494),
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.parkiz.app',
                ),
                MarkerLayer(
                  markers: _parks.map((park) {
                    return Marker(
                      point: LatLng((park['latitude'] as num).toDouble(), (park['longitude'] as num).toDouble()),
                      width: 45,
                      height: 45,
                      child: GestureDetector(
                        onTap: () => _showParkDetails(context, park),
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddParkDialog(context),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Yeni Park Ekle'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _showParkDetails(BuildContext context, dynamic park) {
    final comments = park['comments'] as List<dynamic>? ?? [];
    final commentController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20, left: 20, right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(park['name'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(park['description'] ?? '', style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    
                    // Engelli Erişilebilirlik Etiketleri
                    Row(
                      children: [
                        if (park['has_accessible_ramp'] == true)
                          Chip(
                            avatar: const Icon(Icons.accessible, size: 18, color: Colors.blue),
                            label: const Text('Engelli Rampası', style: TextStyle(fontSize: 12)),
                            backgroundColor: Colors.blue.shade50,
                          ),
                        const SizedBox(width: 8),
                        if (park['has_disabled_swing'] == true)
                          Chip(
                            avatar: const Icon(Icons.child_care, size: 18, color: Colors.purple),
                            label: const Text('Engelsiz Salıncak', style: TextStyle(fontSize: 12)),
                            backgroundColor: Colors.purple.shade50,
                          ),
                      ],
                    ),
                    const Divider(),
                    const Text('Ebeveyn Yorumları', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    if (comments.isEmpty)
                      const Text('Henüz yorum yapılmamış. İlk yorumu siz yapın!', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
                    else
                      ...comments.map((c) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(c['author_name'] ?? 'Anonim Veli', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(c['text'] ?? ''),
                          )),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: commentController,
                            decoration: const InputDecoration(
                              hintText: 'Yorum yazın...',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.teal),
                          onPressed: () async {
                            if (commentController.text.trim().isEmpty) return;
                            final res = await http.post(
                              Uri.parse('$_backendUrl/${park['id']}/comments'),
                              headers: {"Content-Type": "application/json"},
                              body: json.encode({"text": commentController.text, "author_name": "Veli"}),
                            );

                            if (res.statusCode == 200) {
                              commentController.clear();
                              Navigator.pop(context);
                              _fetchParks();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddParkDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final latController = TextEditingController(text: '40.9850');
    final lngController = TextEditingController(text: '29.0520');
    bool hasRamp = false;
    bool hasSwing = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Yeni Park Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Park Adı')),
                    TextField(controller: descController, decoration: const InputDecoration(labelText: 'Açıklama')),
                    TextField(controller: latController, decoration: const InputDecoration(labelText: 'Enlem (Lat)')),
                    TextField(controller: lngController, decoration: const InputDecoration(labelText: 'Boylam (Lng)')),
                    CheckboxListTile(
                      title: const Text('Engelli Rampası Var'),
                      value: hasRamp,
                      onChanged: (val) => setDialogState(() => hasRamp = val!),
                    ),
                    CheckboxListTile(
                      title: const Text('Engelsiz Salıncak Var'),
                      value: hasSwing,
                      onChanged: (val) => setDialogState(() => hasSwing = val!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
                ElevatedButton(
                  onPressed: () async {
                    final newPark = {
                      "name": nameController.text,
                      "description": descController.text,
                      "latitude": double.parse(latController.text),
                      "longitude": double.parse(lngController.text),
                      "rating": 5.0,
                      "has_accessible_ramp": hasRamp,
                      "has_disabled_swing": hasSwing,
                    };

                    final res = await http.post(
                      Uri.parse(_backendUrl),
                      headers: {"Content-Type": "application/json"},
                      body: json.encode(newPark),
                    );

                    if (res.statusCode == 200) {
                      if (context.mounted) Navigator.pop(context);
                      _fetchParks();
                    }
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}