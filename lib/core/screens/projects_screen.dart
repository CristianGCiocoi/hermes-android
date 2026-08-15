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
      setState(() => _projects = result);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
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
