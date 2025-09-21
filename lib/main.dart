import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const TCGDocumentLockApp());
}

class TCGDocumentLockApp extends StatelessWidget {
  const TCGDocumentLockApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TCG Document Lock',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        brightness: Brightness.dark,
        cardTheme: const CardTheme(
          elevation: 4,
          margin: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const PasswordScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Password screen for unlocking the app.
/// Password is stored hashed in a local file.
/// First launch, user sets password.
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({Key? key}) : super(key: key);

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _passwordController = TextEditingController();
  bool _isFirstTime = false;
  String? _storedHash;
  String _errorText = '';

  @override
  void initState() {
    super.initState();
    _loadPasswordHash();
  }

  Future<File> get _passwordFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/password.hash');
  }

  Future<void> _loadPasswordHash() async {
    try {
      final file = await _passwordFile;
      if (await file.exists()) {
        final stored = await file.readAsString();
        setState(() {
          _storedHash = stored;
          _isFirstTime = false;
        });
      } else {
        setState(() {
          _isFirstTime = true;
        });
      }
    } catch (_) {
      setState(() {
        _isFirstTime = true;
      });
    }
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _savePasswordHash(String hash) async {
    final file = await _passwordFile;
    await file.writeAsString(hash);
  }

  void _onSubmit() async {
    final entered = _passwordController.text.trim();
    if (entered.isEmpty) {
      setState(() {
        _errorText = 'Password cannot be empty';
      });
      return;
    }
    if (_isFirstTime) {
      // Save password hash
      final hash = _hashPassword(entered);
      await _savePasswordHash(hash);
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      // Check password
      final hash = _hashPassword(entered);
      if (hash == _storedHash) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()));
      } else {
        setState(() {
          _errorText = 'Incorrect password';
        });
      }
    }
    _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isFirstTime
        ? 'Set Password for TCG Document Lock'
        : 'Enter Password to Unlock';
    final buttonText = _isFirstTime ? 'Set Password' : 'Unlock';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  onSubmitted: (_) => _onSubmit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    errorText: _errorText.isEmpty ? null : _errorText,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _onSubmit,
                  child: Text(buttonText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Data model for a stored item.
class StoredItem {
  final String id;
  final String title;
  final ItemCategory category;
  final String content; // Could be text, path to file, URL, or password text
  final DateTime storedDate;

  StoredItem({
    required this.id,
    required this.title,
    required this.category,
    required this.content,
    required this.storedDate,
  });

  factory StoredItem.fromJson(Map<String, dynamic> json) => StoredItem(
        id: json['id'],
        title: json['title'],
        category: ItemCategory.values[json['category']],
        content: json['content'],
        storedDate: DateTime.parse(json['storedDate']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category.index,
        'content': content,
        'storedDate': storedDate.toIso8601String(),
      };
}

enum ItemCategory { photo, document, text, website, password }

extension ItemCategoryExtension on ItemCategory {
  String get displayName {
    switch (this) {
      case ItemCategory.photo:
        return 'Photo';
      case ItemCategory.document:
        return 'Document';
      case ItemCategory.text:
        return 'Text Note';
      case ItemCategory.website:
        return 'Website';
      case ItemCategory.password:
        return 'Password';
    }
  }

  IconData get iconData {
    switch (this) {
      case ItemCategory.photo:
        return Icons.photo;
      case ItemCategory.document:
        return Icons.description;
      case ItemCategory.text:
        return Icons.notes;
      case ItemCategory.website:
        return Icons.link;
      case ItemCategory.password:
        return Icons.vpn_key;
    }
  }
}

/// Home screen showing list of stored items, search, add new item, summary.
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<StoredItem> _items = [];
  List<StoredItem> _filteredItems = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadStoredItems();
  }

  Future<File> get _dataFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/stored_items.json');
  }

  Future<void> _loadStoredItems() async {
    try {
      final file = await _dataFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final jsonList = jsonDecode(content) as List;
        final loadedItems =
            jsonList.map((e) => StoredItem.fromJson(e)).toList();
        setState(() {
          _items = loadedItems;
          _applySearch(_searchQuery);
        });
      }
    } catch (_) {
      // Ignore errors, start with empty list
      setState(() {
        _items = [];
        _filteredItems = [];
      });
    }
  }

  Future<void> _saveStoredItems() async {
    final file = await _dataFile;
    final jsonList = _items.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  void _applySearch(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredItems = List.from(_items);
      } else {
        _filteredItems = _items.where((item) {
          final lower = query.toLowerCase();
          return item.title.toLowerCase().contains(lower) ||
              item.content.toLowerCase().contains(lower) ||
              item.category.displayName.toLowerCase().contains(lower);
        }).toList();
      }
    });
  }

  void _addNewItem(StoredItem newItem) {
    setState(() {
      _items.insert(0, newItem);
      _applySearch(_searchQuery);
    });
    _saveStoredItems();
  }

  void _deleteItem(StoredItem item) {
    setState(() {
      _items.removeWhere((element) => element.id == item.id);
      _applySearch(_searchQuery);
    });
    _saveStoredItems();
  }

  void _showSummaryDialog() {
    // Count items by category
    final Map<ItemCategory, int> counts = {};
    for (var cat in ItemCategory.values) {
      counts[cat] = 0;
    }
    for (var item in _items) {
      counts[item.category] = (counts[item.category] ?? 0) + 1;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Summary of Stored Items'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: counts.entries
                .map(
                  (e) => ListTile(
                    leading: Icon(e.key.iconData),
                    title: Text('${e.key.displayName}:'),
                    trailing: Text(e.value.toString()),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(StoredItem item) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (res == true) {
      _deleteItem(item);
    }
  }

  void _openItemDetail(StoredItem item) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)));
  }

  void _navigateToAddNew() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AddItemScreen()))
        .then((result) {
      if (result is StoredItem) {
        _addNewItem(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Scaffold(
      appBar: AppBar(
        title: const Text('TCG Document Lock'),
        actions: [
          IconButton(
            tooltip: 'Summary',
            onPressed: _showSummaryDialog,
            icon: const Icon(Icons.list_alt),
          ),
          IconButton(
            tooltip: 'Add New Item',
            onPressed: _navigateToAddNew,
            icon: const Icon(Icons.add),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search stored items...',
                filled: true,
                fillColor: Colors.blueGrey.shade700,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _applySearch,
            ),
          ),
        ),
      ),
      body: _filteredItems.isEmpty
          ? Center(
              child: Text(
                _searchQuery.isEmpty
                    ? 'No items stored yet.\nTap + to add.'
                    : 'No items match your search.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: _filteredItems.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                return Card(
                  child: ListTile(
                    leading: Icon(item.category.iconData, size: 36),
                    title: Text(item.title),
                    subtitle: Text(
                        '${item.category.displayName} · Stored: ${dateFormat.format(item.storedDate)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(item),
                    ),
                    onTap: () => _openItemDetail(item),
                  ),
                );
              },
            ),
    );
  }
}

/// Screen to add a new item with category selection and input.
class AddItemScreen extends StatefulWidget {
  AddItemScreen({Key? key}) : super(key: key);

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  ItemCategory? _selectedCategory;
  String? _filePath;
  bool _loadingFile = false;

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_selectedCategory == null) return;
    setState(() {
      _loadingFile = true;
    });
    try {
      FilePickerResult? result;
      if (_selectedCategory == ItemCategory.photo) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
      } else if (_selectedCategory == ItemCategory.document) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
        );
      }
      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.single;
        // Copy file to app local directory for persistence
        final appDir = await getApplicationDocumentsDirectory();
        final savedPath = '${appDir.path}/${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
        final file = File(pickedFile.path!);
        await file.copy(savedPath);
        setState(() {
          _filePath = savedPath;
          _contentController.text = savedPath;
        });
      }
    } catch (e) {
      // Ignore, show snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick file: $e')),
      );
    }
    setState(() {
      _loadingFile = false;
    });
  }

  Widget _buildContentInput() {
    if (_selectedCategory == null) {
      return const SizedBox.shrink();
    }
    switch (_selectedCategory!) {
      case ItemCategory.photo:
      case ItemCategory.document:
        return Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _contentController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Selected File Path',
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) {
                    return 'Please select a file';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            _loadingFile
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ElevatedButton.icon(
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Pick File'),
                    onPressed: _pickFile,
                  ),
          ],
        );
      case ItemCategory.text:
        return TextFormField(
          controller: _contentController,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Text content',
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter text content';
            }
            return null;
          },
        );
      case ItemCategory.website:
        return TextFormField(
          controller: _contentController,
          decoration: const InputDecoration(
            labelText: 'Website URL',
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter website address';
            }
            final urlPattern = r'^https?:\/\/[\w\-]+(\.[\w\-]+)+[/#?]?.*$';
            final regex = RegExp(urlPattern);
            if (!regex.hasMatch(val.trim())) {
              return 'Please enter a valid URL (starting with http or https)';
            }
            return null;
          },
        );
      case ItemCategory.password:
        return TextFormField(
          controller: _contentController,
          decoration: const InputDecoration(
            labelText: 'Password',
          ),
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter a password';
            }
            return null;
          },
        );
    }
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a category')));
      return;
    }
    final newItem = StoredItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      category: _selectedCategory!,
      content: _contentController.text.trim(),
      storedDate: DateTime.now(),
    );
    Navigator.of(context).pop(newItem);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Item'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                DropdownButtonFormField<ItemCategory>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Select Category',
                  ),
                  items: ItemCategory.values
                      .map((cat) => DropdownMenuItem(
                            value: cat,
                            child: Text(cat.displayName),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedCategory = val;
                      _contentController.clear();
                      _filePath = null;
                      _loadingFile = false;
                    });
                  },
                  validator: (val) =>
                      val == null ? 'Please select a category' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildContentInput(),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _onSave,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Item'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Detail view of a stored item.
/// Shows content and allows download if applicable.
class ItemDetailScreen extends StatelessWidget {
  final StoredItem item;

  const ItemDetailScreen({Key? key, required this.item}) : super(key: key);

  Widget _buildContentView(BuildContext context) {
    switch (item.category) {
      case ItemCategory.photo:
        final file = File(item.content);
        if (!file.existsSync()) {
          return const Text('Photo file not found.');
        }
        return InteractiveViewer(
          child: Image.file(file),
        );
      case ItemCategory.document:
        final file = File(item.content);
        if (!file.existsSync()) {
          return const Text('Document file not found.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Document path:\n${item.content}',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                // Open file using system viewer if possible
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('File open not implemented')));
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Document'),
            ),
          ],
        );
      case ItemCategory.text:
        return SelectableText(
          item.content,
          style: const TextStyle(fontSize: 16),
        );
      case ItemCategory.website:
        return InkWell(
          child: Text(
            item.content,
            style: const TextStyle(
                fontSize: 16, color: Colors.lightBlueAccent, decoration: TextDecoration.underline),
          ),
          onTap: () {
            // Launch URL
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Open website not implemented')));
          },
        );
      case ItemCategory.password:
        return SelectableText(
          item.content,
          style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            ListTile(
              leading: Icon(item.category.iconData, size: 40),
              title: Text(item.category.displayName,
                  style: Theme.of(context).textTheme.titleLarge),
              subtitle: Text('Stored on ${dateFormat.format(item.storedDate)}'),
            ),
            const Divider(height: 32),
            _buildContentView(context),
          ],
        ),
      ),
    );
  }
}
