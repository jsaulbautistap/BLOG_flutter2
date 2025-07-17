import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class BlogPage extends StatefulWidget {
  const BlogPage({super.key});

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  final supabase = Supabase.instance.client;
  final picker = ImagePicker();
  final tituloController = TextEditingController();
  File? selectedImage;
  Uint8List? imageBytes;
  String rol = 'visualizador';
  List<Map<String, dynamic>> posts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPosts();
  }

  Future<void> fetchPosts() async {
    final response = await supabase
        .from('posts')
        .select()
        .order('created_at', ascending: false);

    setState(() {
      posts = List<Map<String, dynamic>>.from(response);
      isLoading = false;
    });
  }

  Future<void> pickImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source, maxWidth: 800, maxHeight: 800);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        imageBytes = bytes;
        if (!kIsWeb) {
          selectedImage = File(pickedFile.path);
        }
      });
    }
  }

  Future<void> publicarPost() async {
    if (imageBytes == null || tituloController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falta subir una imagen o título')),
      );
      return;
    }

    final userId = supabase.auth.currentUser?.id;
    final uuid = const Uuid().v4();

    final fileExt = kIsWeb
        ? 'jpg' 
        : selectedImage!.path.split('.').last;

    final fileName = '$uuid.$fileExt';
    final filePath = 'posts/$fileName';
    

    try {
      await supabase.storage
          .from('imagenes')
          .uploadBinary(filePath, imageBytes!, fileOptions: const FileOptions(upsert: true));
    } catch (e) {
      print('Error al subir la imagen: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir la imagen: $e')),
      );
      return;
    }

    final imageUrl = supabase.storage.from('imagenes').getPublicUrl(filePath);

    try {
      await supabase.from('posts').insert({
        'id': uuid,
        'user_id': userId,
        'titulo': tituloController.text,
        'imagen_url': imageUrl,
      });
    } catch (e) {
      print('Error al guardar el post: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar el post: $e')),
      );
      return;
    }

    tituloController.clear();
    selectedImage = null;
    imageBytes = null;
    await fetchPosts();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Publicación creada')),
    );
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final isPublicador = rol == 'publicador';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turismo Ciudadano'),
        automaticallyImplyLeading: false,
        actions: [
          DropdownButton<String>(
            value: rol,
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  rol = newValue;
                });
              }
            },
            dropdownColor: Colors.white,
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            items: ['publicador', 'visualizador']
                .map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text('Rol: $value'),
              );
            }).toList(),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchPosts,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isPublicador) ...[
                    const Text('Publicar un nuevo lugar',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Cámara'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo),
                          label: const Text('Galería'),
                        ),
                      ],
                    ),
                    if (imageBytes != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Image.memory(imageBytes!, height: 200),
                      ),
                    TextField(
                      controller: tituloController,
                      decoration: const InputDecoration(labelText: 'Nombre del sitio turístico'),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: publicarPost,
                      icon: const Icon(Icons.publish),
                      label: const Text('Publicar'),
                    ),
                    const Divider(height: 32),
                  ],
                  const Text('Lugares publicados',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ...posts.map((post) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Image.network(post['imagen_url'], fit: BoxFit.cover),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                post['titulo'],
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 32),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar sesión'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
