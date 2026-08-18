import 'package:flutter/material.dart';

import '../services/atlas_project_port.dart';

class ProjectsScreen extends StatefulWidget {
  final ProjectCatalogController controller;
  final String? canonicalProfileId;
  final String? conversationId;
  final ValueChanged<HermesProject>? onProjectSelected;

  const ProjectsScreen({
    required this.controller,
    this.canonicalProfileId,
    this.conversationId,
    this.onProjectSelected,
    super.key,
  });

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _search = TextEditingController();
  List<HermesProject> _projects = const [];
  String? _error;
  String? _selectedProjectId;
  String? _bindingProjectId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.controller.list(
        canonicalProfileId: widget.canonicalProfileId,
        query: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _projects = result;
        _selectedProjectId = null;
        for (final project in result) {
          if (project.isActive) {
            _selectedProjectId = project.hermesProjectId;
            break;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Projects are unavailable for this profile.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(HermesProject project) async {
    if (_bindingProjectId != null) return;
    final conversationId = widget.conversationId;
    setState(() {
      _bindingProjectId = project.hermesProjectId;
      _error = null;
    });
    try {
      await widget.controller.select(
        project: project,
        canonicalProfileId: widget.canonicalProfileId,
        conversationId: conversationId,
      );
      if (!mounted) return;
      setState(() => _selectedProjectId = project.hermesProjectId);
      widget.onProjectSelected?.call(project);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Project selection was not accepted.');
    } finally {
      if (mounted) setState(() => _bindingProjectId = null);
    }
  }

  Future<void> _showCreateProject() async {
    final created = await showDialog<HermesProject>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _CreateHermesProjectDialog(controller: widget.controller),
    );
    if (created == null || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created.isActive
              ? '${created.name} created and set active.'
              : '${created.name} created.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            key: const Key('new-hermes-project'),
            tooltip: 'New Hermes Project',
            onPressed: _bindingProjectId == null ? _showCreateProject : null,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              maxLength: 120,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: 'Search Hermes Projects',
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, key: const Key('projects-error')),
            ),
          if (!_loading && _error == null)
            Expanded(
              child: _projects.isEmpty
                  ? const Center(child: Text('No Hermes Projects available.'))
                  : ListView.builder(
                      itemCount: _projects.length,
                      itemBuilder: (context, index) {
                        final project = _projects[index];
                        final selected =
                            project.hermesProjectId == _selectedProjectId;
                        return ListTile(
                          key: Key('project-${project.hermesProjectId}'),
                          leading: const Icon(Icons.account_tree_outlined),
                          title: Text(project.name),
                          subtitle: Text(
                            project.atlasContext?.core?.currentFocus ??
                                project.atlasContext?.core?.objective ??
                                project.description ??
                                'Hermes Project',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: selected,
                          onTap: _bindingProjectId == null
                              ? () => _select(project)
                              : null,
                          trailing: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              if (_bindingProjectId == project.hermesProjectId)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    key: Key('project-binding'),
                                    strokeWidth: 2,
                                  ),
                                ),
                              if (project.atlasContext?.projection != null)
                                Chip(
                                  label: Text(
                                    project
                                        .atlasContext!
                                        .projection!
                                        .continuityStatus,
                                  ),
                                ),
                              if (selected)
                                const Icon(
                                  Icons.check_circle_outline,
                                  key: Key('project-selected'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _CreateHermesProjectDialog extends StatefulWidget {
  final ProjectCatalogController controller;

  const _CreateHermesProjectDialog({required this.controller});

  @override
  State<_CreateHermesProjectDialog> createState() =>
      _CreateHermesProjectDialogState();
}

class _CreateHermesProjectDialogState
    extends State<_CreateHermesProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _mainFolder = TextEditingController();
  bool _setActiveNow = true;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _mainFolder.dispose();
    super.dispose();
  }

  String? _requiredText(String? value, String label, int maxLength) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return '$label is required.';
    if (normalized.length > maxLength) return '$label is too long.';
    return null;
  }

  String? _mainFolderError(String? value) {
    final required = _requiredText(value, 'Main folder', 2048);
    if (required != null) return required;
    final path = value!.trim();
    final isAbsolute =
        path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
        RegExp(r'^\\\\[^\\]+\\[^\\]+').hasMatch(path);
    return isAbsolute ? null : 'Use an absolute Gateway folder path.';
  }

  Future<void> _create() async {
    if (_creating || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final project = await widget.controller.create(
        name: _name.text,
        description: _description.text,
        primaryPath: _mainFolder.text,
        setActiveNow: _setActiveNow,
      );
      if (!mounted) return;
      Navigator.of(context).pop(project);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message == 'Hermes Project name already exists'
            ? 'A Hermes Project with this name already exists.'
            : 'Project details or the Gateway response were invalid.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Project creation was not accepted.');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Hermes Project'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('project-name-field'),
                  controller: _name,
                  autofocus: true,
                  enabled: !_creating,
                  maxLength: 240,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) =>
                      _requiredText(value, 'Project name', 240),
                ),
                TextFormField(
                  key: const Key('project-description-field'),
                  controller: _description,
                  enabled: !_creating,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                TextFormField(
                  key: const Key('project-main-folder-field'),
                  controller: _mainFolder,
                  enabled: !_creating,
                  maxLength: 2048,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _create(),
                  decoration: const InputDecoration(
                    labelText: 'Main folder',
                    hintText: '/workspace/project',
                    helperText: 'Absolute path on the Hermes Gateway host',
                  ),
                  validator: _mainFolderError,
                ),
                SwitchListTile(
                  key: const Key('project-set-active-now'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set active now'),
                  subtitle: const Text(
                    'Changes only the active native Hermes Project.',
                  ),
                  value: _setActiveNow,
                  onChanged: _creating
                      ? null
                      : (value) => setState(() => _setActiveNow = value),
                ),
                if (_error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      key: const Key('project-create-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('create-hermes-project-submit'),
          onPressed: _creating ? null : _create,
          icon: _creating
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: const Text('Create Project'),
        ),
      ],
    );
  }
}
