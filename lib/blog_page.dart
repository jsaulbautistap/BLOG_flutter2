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
  final resenaController = TextEditingController();
  final respuestaControllers = <String, TextEditingController>{};
  File? selectedImage;
  Uint8List? imageBytes;
  String rol = 'visualizador';
  List<Map<String, dynamic>> posts = [];
  bool isLoading = true;
  Map<String, dynamic>? selectedPost; 

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
      // Validar tamaño máximo (5MB)
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La imagen debe ser menor o igual a 5MB')),
        );
        return;
      }
      setState(() {
        imageBytes = bytes;
        if (!kIsWeb) {
          selectedImage = File(pickedFile.path);
        }
      });
    }
  }

  Future<void> publicarPost() async {
    if (imageBytes == null || tituloController.text.isEmpty || resenaController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falta subir una imagen, título o reseña')),
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
        'reseña': resenaController.text,
        'respuestas': [],
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
    resenaController.clear();
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

  Future<void> responderResena(String postId) async {
    final respuesta = respuestaControllers[postId]?.text ?? '';
    if (respuesta.isEmpty) return;
    final post = posts.firstWhere((p) => p['id'] == postId);
    final respuestas = List<String>.from(post['respuestas'] ?? []);
    respuestas.add(respuesta);

    final respuestasPg = '{${respuestas.map((r) => '"$r"').join(',')}}';

    await supabase
        .from('posts')
        .update({'respuestas': respuestasPg})
        .eq('id', postId);

    respuestaControllers[postId]?.clear();
    await fetchPosts();
  }

  @override
  Widget build(BuildContext context) {
    final isPublicador = rol == 'publicador';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turismo Ciudadano', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[600],
        elevation: 2,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: rol,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo),
                    style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          rol = newValue;
                          selectedPost = null;
                        });
                      }
                    },
                    items: [
                      DropdownMenuItem(
                        value: 'publicador',
                        child: Row(
                          children: [
                            const Icon(Icons.edit, color: Colors.indigo),
                            const SizedBox(width: 6),
                            const Text('Publicador'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'visualizador',
                        child: Row(
                          children: [
                            const Icon(Icons.visibility, color: Colors.indigo),
                            const SizedBox(width: 6),
                            const Text('Visualizador'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                    Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      color: Colors.indigo[50],
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.add_location_alt, color: Colors.indigo, size: 32),
                                const SizedBox(width: 10),
                                const Text(
                                  'Publicar un nuevo lugar',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => pickImage(ImageSource.camera),
                                  icon: const Icon(Icons.camera_alt, size: 22),
                                  label: const Text('Cámara', style: TextStyle(fontSize: 16)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 3,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => pickImage(ImageSource.gallery),
                                  icon: const Icon(Icons.photo, size: 22),
                                  label: const Text('Galería', style: TextStyle(fontSize: 16)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 3,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                            if (imageBytes != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.memory(imageBytes!, height: 160, fit: BoxFit.cover),
                                ),
                              ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: tituloController,
                              decoration: InputDecoration(
                                labelText: 'Nombre del sitio turístico',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                prefixIcon: const Icon(Icons.place, color: Colors.indigo),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: resenaController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Reseña del sitio',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                prefixIcon: const Icon(Icons.rate_review, color: Colors.indigo),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: publicarPost,
                                icon: const Icon(Icons.publish, size: 22),
                                label: const Text('Publicar', style: TextStyle(fontSize: 17)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[600],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 32),
                  ],
                  if (rol == 'visualizador' && selectedPost == null) ...[
                    const Text('Lugares publicados',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ...posts.map((post) {
                      final postId = post['id'] as String;
                      respuestaControllers.putIfAbsent(postId, () => TextEditingController());
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedPost = post;
                          });
                        },
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                                child: Image.network(
                                  post['imagen_url'],
                                  fit: BoxFit.cover,
                                  height: 200,
                                  width: double.infinity,
                                  loadingBuilder: (context, child, progress) =>
                                    progress == null ? child : Container(
                                      height: 200,
                                      alignment: Alignment.center,
                                      child: const CircularProgressIndicator(),
                                    ),
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    height: 200,
                                    color: Colors.grey[200],
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      post['titulo'],
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.rate_review, color: Colors.amber, size: 20),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            post['reseña'] ?? '',
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if ((post['respuestas'] ?? []).isNotEmpty)
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Respuestas:', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ...List<String>.from(post['respuestas'] ?? []).map((r) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.reply, color: Colors.blueAccent, size: 18),
                                                const SizedBox(width: 6),
                                                Expanded(child: Text(r)),
                                              ],
                                            ),
                                          )),
                                        ],
                                      ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: respuestaControllers[postId],
                                            decoration: InputDecoration(
                                              hintText: 'Responder a la reseña...',
                                              filled: true,
                                              fillColor: Colors.grey[100],
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: () => responderResena(postId),
                                          child: const Icon(Icons.send, size: 20),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blueAccent,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            padding: const EdgeInsets.all(12),
                                            minimumSize: const Size(40, 40),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  if (rol == 'visualizador' && selectedPost != null) ...[
                    Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                            child: Image.network(
                              selectedPost!['imagen_url'],
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: 220,
                              loadingBuilder: (context, child, progress) =>
                                progress == null ? child : Container(
                                  height: 220,
                                  alignment: Alignment.center,
                                  child: const CircularProgressIndicator(),
                                ),
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 220,
                              color: Colors.grey[200],
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                            ),
                          ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedPost!['titulo'],
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.rate_review, color: Colors.amber, size: 20),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        selectedPost!['reseña'] ?? '',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text('Respuestas:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ...List<String>.from(selectedPost!['respuestas'] ?? []).map((r) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.reply, color: Colors.blueAccent, size: 18),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(r)),
                                    ],
                                  ),
                                )),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: respuestaControllers[selectedPost!['id']],
                                        decoration: InputDecoration(
                                          hintText: 'Responder a la reseña...',
                                          filled: true,
                                          fillColor: Colors.grey[100],
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () async {
                                        await responderResena(selectedPost!['id']);
                                        final refreshedPost = posts.firstWhere((p) => p['id'] == selectedPost!['id']);
                                        setState(() {
                                          selectedPost = refreshedPost;
                                        });
                                      },
                                      child: const Icon(Icons.send, size: 20),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.all(12),
                                        minimumSize: const Size(40, 40),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Center(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        selectedPost = null;
                                      });
                                    },
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('Regresar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey[300],
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: logout,
                      icon: const Icon(Icons.logout, size: 22),
                      label: const Text('Cerrar sesión', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
