import 'package:flutter/material.dart';
import '../../../core/models/group.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';

class GroupManageScreen extends StatefulWidget {
  const GroupManageScreen({super.key});

  @override
  State<GroupManageScreen> createState() => _GroupManageScreenState();
}

class _GroupManageScreenState extends State<GroupManageScreen> {
  final DatabaseService _db = DatabaseService();
  List<Group> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    await _db.initialize();
    final groups = await _db.getAllGroups();
    setState(() => _groups = groups);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);

    final content = _groups.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_open, size: 64, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                const Text('还没有分组', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                const Text('点击右下角按钮创建', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              ],
            ),
          )
        : ListView.builder(
            itemCount: _groups.length,
            itemBuilder: (context, index) {
              final group = _groups[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.folder, color: AppColors.primary),
                  ),
                  title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(group.description ?? '无描述'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _showEditDialog(group);
                      if (value == 'delete') _deleteGroup(group);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
              );
            },
          );

    return Scaffold(
      appBar: AppBar(title: const Text('分组管理')),
      body: isWide ? CenteredContent(maxWidth: 600, child: content) : content,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showEditDialog(Group? group) {
    final nameController = TextEditingController(text: group?.name ?? '');
    final descController = TextEditingController(text: group?.description ?? '');
    final isEditing = group != null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? '编辑分组' : '创建分组'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '分组名称 *',
                hintText: '例如：LLM、TTS、多模态',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: '描述',
                hintText: '可选描述',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final navigator = Navigator.of(context);
              if (isEditing) {
                final updated = Group(
                  id: group.id,
                  name: name,
                  description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
                  sortOrder: group.sortOrder,
                  createdAt: group.createdAt,
                );
                await _db.updateGroup(updated);
              } else {
                final newGroup = Group(
                  id: 'group_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
                  sortOrder: _groups.length,
                );
                await _db.insertGroup(newGroup);
              }

              navigator.pop();
              _loadGroups();
            },
            child: Text(isEditing ? '保存' : '创建'),
          ),
        ],
      ),
    );
  }

  void _deleteGroup(Group group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除分组 "${group.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await _db.deleteGroup(group.id);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              _loadGroups();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
