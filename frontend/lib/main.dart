import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
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
  final String _baseUrl = 'https://parkiz-app.onrender.com/api';
  final MapController _mapController = MapController();
  
  List<dynamic> _parks = [];
  bool _isLoading = true;
  bool _isFilterActive = false;
  LatLng? _currentPosition;

  // Kullanıcı Oturum Bilgileri
  String? _authToken;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _fetchParks();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
  }

  void _goToCurrentLocation() async {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, 15.0);
    } else {
      await _determinePosition();
      if (_currentPosition != null) {
        _mapController.move(_currentPosition!, 15.0);
      }
    }
  }

  Future<void> _fetchParks() async {
    setState(() {
      _isLoading = true;
      _isFilterActive = false;
    });
    try {
      final response = await http.get(Uri.parse('$_baseUrl/parks'));
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

  Future<void> _fetchNearbyParks() async {
    if (_currentPosition == null) {
      await _determinePosition();
      if (_currentPosition == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum bilgisi alınamadı!')),
          );
        }
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/parks/nearby'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "latitude": _currentPosition!.latitude,
          "longitude": _currentPosition!.longitude,
          "radius_km": 5.0,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _parks = json.decode(utf8.decode(response.bodyBytes));
          _isLoading = false;
          _isFilterActive = true;
        });
        _goToCurrentLocation();
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // Giriş Yap Dialog
  void _showLoginDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Veli Girişi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'E-posta')),
              TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showRegisterDialog();
              },
              child: const Text('Kayıt Ol'),
            ),
            ElevatedButton(
              onPressed: () async {
                final response = await http.post(
                  Uri.parse('$_baseUrl/auth/login'),
                  headers: {"Content-Type": "application/x-www-form-urlencoded"},
                  body: {
                    "username": emailController.text.trim(),
                    "password": passwordController.text.trim(),
                  },
                );

                if (response.statusCode == 200) {
                  final data = json.decode(utf8.decode(response.bodyBytes));
                  setState(() {
                    _authToken = data['access_token'];
                    _currentUserName = data['user']['full_name'];
                  });
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hoş geldiniz, $_currentUserName!')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Giriş başarısız. Bilgilerinizi kontrol edin.')),
                    );
                  }
                }
              },
              child: const Text('Giriş Yap'),
            ),
          ],
        );
      },
    );
  }

  // Kayıt Ol Dialog
  void _showRegisterDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Yeni Veli Kaydı'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Ad Soyad')),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'E-posta')),
              TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                final response = await http.post(
                  Uri.parse('$_baseUrl/auth/register'),
                  headers: {"Content-Type": "application/json"},
                  body: json.encode({
                    "full_name": nameController.text.trim(),
                    "email": emailController.text.trim(),
                    "password": passwordController.text.trim(),
                  }),
                );

                if (response.statusCode == 200) {
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kayıt başarılı! Şimdi giriş yapabilirsiniz.')),
                    );
                  }
                  _showLoginDialog();
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kayıt başarısız. E-posta adresi kullanımda olabilir.')),
                    );
                  }
                }
              },
              child: const Text('Kayıt Ol'),
            ),
          ],
        );
      },
    );
  }

  void _showImageUploadDialog(int parkId) {
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Park Fotoğrafı URL Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Parka ait fotoğrafın internet bağlantısını (URL) yapıştırın:'),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Fotoğraf URL',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                if (urlController.text.trim().isEmpty) return;

                final res = await http.post(
                  Uri.parse('$_baseUrl/parks/$parkId/upload-image'),
                  headers: {"Content-Type": "application/json"},
                  body: json.encode({"image_url": urlController.text.trim()}),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isFilterActive ? 'Yakındaki Parklar (5 km)' : 'Parkiz - Canlı Harita'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Giriş Yap / Profil Butonu
          IconButton(
            icon: Icon(_authToken != null ? Icons.account_circle : Icons.login),
            tooltip: _authToken != null ? _currentUserName : 'Giriş Yap / Kayıt Ol',
            onPressed: () {
              if (_authToken != null) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(_currentUserName ?? 'Kullanıcı'),
                    content: const Text('Oturum kapatılsın mı?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _authToken = null;
                            _currentUserName = null;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Çıkış Yap'),
                      ),
                    ],
                  ),
                );
              } else {
                _showLoginDialog();
              }
            },
          ),
          IconButton(
            icon: Icon(_isFilterActive ? Icons.clear_all : Icons.near_me),
            tooltip: _isFilterActive ? 'Tüm Parkları Göster' : 'Yakınımdakiler (5 km)',
            onPressed: _isFilterActive ? _fetchParks : _fetchNearbyParks,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchParks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition ??
                    (_parks.isNotEmpty
                        ? LatLng((_parks[0]['latitude'] as num).toDouble(), (_parks[0]['longitude'] as num).toDouble())
                        : const LatLng(40.9822, 29.0494)),
                initialZoom: 13.0,
                onTap: (tapPosition, point) {
                  _showAddParkDialog(context, initialPoint: point);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.parkiz.app',
                ),
                MarkerLayer(
                  markers: [
                    if (_currentPosition != null)
                      Marker(
                        point: _currentPosition!,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.blue, width: 2),
                          ),
                          child: const Center(
                            child: Icon(Icons.my_location, color: Colors.blue, size: 22),
                          ),
                        ),
                      ),
                    ..._parks.map((park) {
                      return Marker(
                        point: LatLng((park['latitude'] as num).toDouble(), (park['longitude'] as num).toDouble()),
                        width: 45,
                        height: 45,
                        child: GestureDetector(
                          onTap: () => _showParkDetails(context, park),
                          child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "btnGPS",
            onPressed: _goToCurrentLocation,
            backgroundColor: Colors.white,
            foregroundColor: Colors.blue,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: "btnAddPark",
            onPressed: () => _showAddParkDialog(context),
            icon: const Icon(Icons.add_location_alt),
            label: const Text('Yeni Park Ekle'),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }

  void _showParkDetails(BuildContext context, dynamic park) {
    final comments = park['comments'] as List<dynamic>? ?? [];
    final commentController = TextEditingController();
    final imageUrl = park['image_url'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            top: 16, left: 20, right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: imageUrl != null && imageUrl.toString().isNotEmpty
                            ? Image.network(
                                imageUrl,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  height: 110,
                                  color: Colors.grey.shade200,
                                  child: const Center(child: Text('Fotoğraf yüklenemedi')),
                                ),
                              )
                            : Container(
                                height: 110,
                                width: double.infinity,
                                color: Colors.grey.shade200,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.image_not_supported, color: Colors.grey, size: 36),
                                    const SizedBox(height: 6),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _showImageUploadDialog(park['id']);
                                      },
                                      icon: const Icon(Icons.add_a_photo, size: 16),
                                      label: const Text('Fotoğraf URL Ekle'),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              park['name'] ?? '',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_a_photo, color: Colors.teal),
                            tooltip: 'Fotoğrafı Değiştir',
                            onPressed: () {
                              Navigator.pop(context);
                              _showImageUploadDialog(park['id']);
                            },
                          ),
                        ],
                      ),
                      if (park['description'] != null && park['description'].toString().isNotEmpty)
                        Text(park['description'], style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 10),
                      
                      Row(
                        children: [
                          if (park['has_accessible_ramp'] == true)
                            Chip(
                              avatar: const Icon(Icons.accessible, size: 16, color: Colors.blue),
                              label: const Text('Engelli Rampası', style: TextStyle(fontSize: 11)),
                              backgroundColor: Colors.blue.shade50,
                            ),
                          if (park['has_accessible_ramp'] == true) const SizedBox(width: 8),
                          if (park['has_disabled_swing'] == true)
                            Chip(
                              avatar: const Icon(Icons.child_care, size: 16, color: Colors.purple),
                              label: const Text('Engelsiz Salıncak', style: TextStyle(fontSize: 11)),
                              backgroundColor: Colors.purple.shade50,
                            ),
                        ],
                      ),
                      const Divider(),
                      const Text('Ebeveyn Yorumları', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),

                      if (comments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'Henüz yorum yapılmamış. İlk yorumu siz yapın!',
                            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                          ),
                        )
                      else
                        ...comments.map((c) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 18)),
                              title: Text(c['author_name'] ?? 'Anonim Veli', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(c['text'] ?? ''),
                            )),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

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

                      Map<String, String> headers = {"Content-Type": "application/json"};
                      if (_authToken != null) {
                        headers["Authorization"] = "Bearer $_authToken";
                      }

                      final res = await http.post(
                        Uri.parse('$_baseUrl/parks/${park['id']}/comments'),
                        headers: headers,
                        body: json.encode({
                          "text": commentController.text,
                          "author_name": _currentUserName ?? "Veli"
                        }),
                      );

                      if (res.statusCode == 200) {
                        commentController.clear();
                        if (context.mounted) Navigator.pop(context);
                        _fetchParks();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddParkDialog(BuildContext context, {LatLng? initialPoint}) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final latController = TextEditingController(text: initialPoint?.latitude.toStringAsFixed(6) ?? '40.9850');
    final lngController = TextEditingController(text: initialPoint?.longitude.toStringAsFixed(6) ?? '29.0520');
    final imageController = TextEditingController();
    bool hasRamp = false;
    bool hasSwing = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(initialPoint != null ? 'Tıklanan Noktaya Park Ekle' : 'Yeni Park Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Park Adı')),
                    TextField(controller: descController, decoration: const InputDecoration(labelText: 'Açıklama')),
                    TextField(controller: imageController, decoration: const InputDecoration(labelText: 'Fotoğraf URL (Opsiyonel)')),
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
                    if (nameController.text.isEmpty) return;
                    
                    final newPark = {
                      "name": nameController.text,
                      "description": descController.text,
                      "image_url": imageController.text.isNotEmpty ? imageController.text : null,
                      "latitude": double.parse(latController.text),
                      "longitude": double.parse(lngController.text),
                      "rating": 5.0,
                      "has_accessible_ramp": hasRamp,
                      "has_disabled_swing": hasSwing,
                    };

                    final res = await http.post(
                      Uri.parse('$_baseUrl/parks'),
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