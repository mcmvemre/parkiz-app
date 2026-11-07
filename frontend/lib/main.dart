import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const ParkIzApp());
}

class ParkIzApp extends StatelessWidget {
  const ParkIzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parkİz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  LatLng _currentPosition = const LatLng(40.9930, 28.6430);
  final bool _isLoading = false;

  List<dynamic> _allParks = [
    {
      'id': '1',
      'name': 'Beylikdüzü Yaşam Vadisi Çocuk Parkı',
      'description': '⭐ 4.9 - Büyük Kaydırak, Kauçuk Zemin, Engelsiz',
      'latitude': 40.9930,
      'longitude': 28.6430,
      'rating': 4.9,
      'distance_meters': 350.0,
      'reviews': [
        {
          'id': 1,
          'user_name': 'Ahmet Y.',
          'comment': 'Çocuklar kaydıraklara bayıldı, zemin gayet yumuşak.',
          'rating': 5.0
        },
        {
          'id': 2,
          'user_name': 'Selin K.',
          'comment': 'Temiz ve düzenli bir alan, akşamları biraz kalabalık oluyor.',
          'rating': 4.5
        }
      ]
    },
    {
      'id': '2',
      'name': 'Gürpınar Sahil Oyun Alanı',
      'description': '⭐ 4.7 - Salıncak, Kum Havuzu, Ahşap Donanım',
      'latitude': 40.9850,
      'longitude': 28.6250,
      'rating': 4.7,
      'distance_meters': 1200.0,
      'reviews': [
        {
          'id': 3,
          'user_name': 'Emre K.',
          'comment': 'Gürpınar sahilde harika bir oyun alanı, çocuklar çok eğlendi.',
          'rating': 5.0
        }
      ]
    }
  ];

  Set<Marker> _markers = {};
  Marker? _tempMarker;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'Tümü';

  final String _backendUrl = 'http://10.0.2.2:8000/api/parks';

  @override
  void initState() {
    super.initState();
    _applyFilters();
    _getUserLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _toTurkishLowerCase(String input) {
    return input
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ç', 'ç')
        .toLowerCase();
  }

  Future<void> _launchDirections(double destLat, double destLng) async {
    final Uri googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=driving',
    );

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Harita uygulaması açılamadı.')),
        );
      }
    }
  }

  Future<void> _fetchParksFromBackend() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_backendUrl?lat=${_currentPosition.latitude}&lng=${_currentPosition.longitude}'),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List<dynamic> parksData = json.decode(response.body);
        if (parksData.isNotEmpty) {
          _allParks = parksData;
          _applyFilters();
        }
      }
    } catch (e) {
      debugPrint('Backend hatası: $e');
      _applyFilters();
    }
  }

  void _applyFilters() {
    List<dynamic> filtered = _allParks.where((park) {
      final name = _toTurkishLowerCase(park['name'] ?? '');
      final description = _toTurkishLowerCase(park['description'] ?? '');
      final query = _toTurkishLowerCase(_searchQuery);

      bool matchesSearch = query.isEmpty || name.contains(query) || description.contains(query);

      bool matchesCategory = true;
      if (_selectedFilter == 'Kauçuk Zemin') {
        matchesCategory = description.contains('kauçuk');
      } else if (_selectedFilter == 'Engelsiz') {
        matchesCategory = description.contains('engelsiz');
      } else if (_selectedFilter == 'Tırmanma') {
        matchesCategory = description.contains('tırmanma');
      }

      return matchesSearch && matchesCategory;
    }).toList();

    final Set<Marker> generatedMarkers = filtered.map((park) {
      final double lat = (park['latitude'] as num).toDouble();
      final double lng = (park['longitude'] as num).toDouble();
      return Marker(
        markerId: MarkerId(park['id'].toString()),
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(title: park['name'] ?? ''),
        onTap: () {
          _showParkDetailBottomSheet(park as Map<String, dynamic>);
        },
      );
    }).toSet();

    if (_tempMarker != null) {
      generatedMarkers.add(_tempMarker!);
    }

    if (mounted) {
      setState(() {
        _markers = generatedMarkers;
      });
    }
  }

  void _onMapLongPress(LatLng point) {
    setState(() {
      _tempMarker = Marker(
        markerId: const MarkerId('temp_park'),
        position: point,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(title: 'Yeni Park Konumu'),
      );
    });
    _applyFilters();
    _showAddParkDialog(point);
  }

  void _showAddParkDialog(LatLng position) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Yeni Park Ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Park Adı',
                    hintText: 'Örn: Manolya Çocuk Parkı',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama / Özellikler',
                    hintText: 'Örn: Kauçuk zemin, salıncak, engelsiz',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _tempMarker = null;
                });
                _applyFilters();
                Navigator.pop(dialogContext);
              },
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    final res = await http.post(
                      Uri.parse(_backendUrl),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({
                        'name': nameController.text,
                        'description': descController.text,
                        'latitude': position.latitude,
                        'longitude': position.longitude,
                      }),
                    );
                    if (res.statusCode == 200 && mounted) {
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() {
                        _tempMarker = null;
                      });
                      Navigator.pop(dialogContext);
                      await _fetchParksFromBackend();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Yeni park başarıyla kaydedildi!')),
                      );
                    }
                  } catch (e) {
                    debugPrint('Park ekleme hatası: $e');
                  }
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  void _showReviewOptions(int reviewId, String userName) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bottomContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.orange),
                title: const Text('Yorumu Bildir'),
                onTap: () {
                  Navigator.pop(bottomContext);
                  _reportReview(reviewId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: Text('$userName İsimli Kullanıcıyı Engelle'),
                onTap: () {
                  Navigator.pop(bottomContext);
                  _blockUser(userName);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _reportReview(int reviewId) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final reasonController = TextEditingController();
        return AlertDialog(
          title: const Text('Yorumu Bildir'),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              labelText: 'Bildirim Nedeni',
              hintText: 'Örn: Uygunsuz dil / Yanıltıcı içerik',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonController.text.isNotEmpty) {
                  try {
                    final res = await http.post(
                      Uri.parse('http://10.0.2.2:8000/api/reviews/$reviewId/report'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({'reason': reasonController.text}),
                    );
                    if (res.statusCode == 200 && mounted) {
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(dialogContext);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Bildiriminiz alındı. Teşekkürler!')),
                      );
                    }
                  } catch (e) {
                    debugPrint('Bildirim hatası: $e');
                  }
                }
              },
              child: const Text('Gönder'),
            ),
          ],
        );
      },
    );
  }

  void _blockUser(String userName) async {
    try {
      final res = await http.post(
        Uri.parse('http://10.0.2.2:8000/api/users/block'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_name': userName}),
      );
      if (res.statusCode == 200 && mounted) {
        final messenger = ScaffoldMessenger.of(context);
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        await _fetchParksFromBackend();
        messenger.showSnackBar(
          SnackBar(content: Text('$userName engellendi ve yorumları gizlendi.')),
        );
      }
    } catch (e) {
      debugPrint('Engelleme hatası: $e');
    }
  }

  void _showAddReviewDialog(String parkId) {
    final nameController = TextEditingController();
    final commentController = TextEditingController();
    double rating = 5.0;
    bool acceptedEula = false;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Yorum & Puan Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Adınız'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: commentController,
                      decoration: const InputDecoration(labelText: 'Yorumunuz'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          icon: Icon(
                            index < rating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              rating = index + 1.0;
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: acceptedEula,
                            onChanged: (val) {
                              setDialogState(() {
                                acceptedEula = val ?? false;
                              });
                            },
                          ),
                          const Expanded(
                            child: Text(
                              'Kullanım Şartlarını (EULA) ve Topluluk Kurallarını kabul ediyorum. Uygunsuz içerik yayınlanamaz.',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: acceptedEula
                      ? () async {
                          if (nameController.text.isNotEmpty && commentController.text.isNotEmpty) {
                            try {
                              final res = await http.post(
                                Uri.parse('$_backendUrl/$parkId/reviews'),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode({
                                  'user_name': nameController.text,
                                  'comment': commentController.text,
                                  'rating': rating,
                                }),
                              );
                              if (res.statusCode == 200 && mounted) {
                                final messenger = ScaffoldMessenger.of(context);
                                Navigator.pop(dialogContext);
                                if (Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                }
                                _fetchParksFromBackend();
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Yorumunuz başarıyla eklendi!')),
                                );
                              }
                            } catch (e) {
                              debugPrint('Yorum ekleme hatası: $e');
                            }
                          }
                        }
                      : null,
                  child: const Text('Gönder'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showParkDetailBottomSheet(Map<String, dynamic> park) {
    final distanceText = park['distance_meters'] != null
        ? '${park['distance_meters']} m'
        : 'Mesafe hesaplanamadı';

    final List<dynamic> reviews = park['reviews'] ?? [];
    final double parkLat = (park['latitude'] as num).toDouble();
    final double parkLng = (park['longitude'] as num).toDouble();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            park['name'] ?? 'Park',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                '${park['rating'] ?? 4.5}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.near_me, size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          'Mesafe: $distanceText',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      park['description'] ?? '',
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Özellikler & Donanım',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFeatureChip(Icons.child_care, 'Kauçuk Zemin'),
                        _buildFeatureChip(Icons.shield, 'Güvenlik Çiti'),
                        _buildFeatureChip(Icons.attractions, 'Kaydırak & Salıncak'),
                        _buildFeatureChip(Icons.accessible, 'Engelsiz Erişim'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Kullanıcı Yorumları (${reviews.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        TextButton.icon(
                          onPressed: () => _showAddReviewDialog(park['id'].toString()),
                          icon: const Icon(Icons.rate_review, size: 18),
                          label: const Text('Yorum Yap'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (reviews.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text('Henüz yorum yapılmamış. İlk yorumu siz yapın!'),
                      )
                    else
                      Column(
                        children: reviews.map((r) {
                          final userName = r['user_name'] ?? 'Kullanıcı';
                          final reviewId = r['id'] as int;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 14),
                                      Text('${r['rating']}'),
                                    ],
                                  ),
                                ],
                              ),
                              subtitle: Text(r['comment'] ?? ''),
                              trailing: IconButton(
                                icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                                tooltip: 'Seçenekler',
                                onPressed: () => _showReviewOptions(reviewId, userName),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _launchDirections(parkLat, parkLng),
                  icon: const Icon(Icons.directions),
                  label: const Text('Yol Tarifi Al'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeatureChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.green[700]),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.green[50],
      side: BorderSide.none,
    );
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _fetchParksFromBackend();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _fetchParksFromBackend();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _fetchParksFromBackend();
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      LatLng userLatLng = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _currentPosition = userLatLng;
        });
        await _fetchParksFromBackend();
      }

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(userLatLng, 14.5),
      );
    } catch (e) {
      _fetchParksFromBackend();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parkİz - Oyun Alanları'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchParksFromBackend,
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getUserLocation,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition,
                    zoom: 14.0,
                  ),
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(_currentPosition, 14.0),
                    );
                    _fetchParksFromBackend();
                  },
                  onLongPress: _onMapLongPress,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  markers: _markers,
                ),
                Positioned(
                  top: 10,
                  left: 15,
                  right: 15,
                  child: Column(
                    children: [
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            _searchQuery = value;
                            _applyFilters();
                          },
                          decoration: InputDecoration(
                            hintText: 'Park adı veya özellik ara...',
                            prefixIcon: const Icon(Icons.search, color: Colors.green),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                      _applyFilters();
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            'Tümü',
                            'Kauçuk Zemin',
                            'Engelsiz',
                            'Tırmanma'
                          ].map((filterName) {
                            final isSelected = _selectedFilter == filterName;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: FilterChip(
                                label: Text(filterName),
                                selected: isSelected,
                                selectedColor: Colors.green[200],
                                checkmarkColor: Colors.green[900],
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedFilter = filterName;
                                  });
                                  _applyFilters();
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}