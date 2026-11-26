import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/legal_document.dart';

class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({required this.document, super.key});

  final LegalDocumentKind document;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  final _scroll = ScrollController();
  final _sectionKeys = <String, GlobalKey>{};
  AssetBundle? _bundle;
  Future<LegalDocumentContent>? _document;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (!identical(_bundle, bundle)) {
      _bundle = bundle;
      _document = _load();
    }
  }

  @override
  void didUpdateWidget(covariant LegalDocumentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _sectionKeys.clear();
      _document = _load();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  Future<LegalDocumentContent> _load() async => LegalDocumentContent.parse(
    widget.document,
    await _bundle!.loadString(widget.document.assetPath),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      GoRouter.maybeOf(context)?.go('/auth');
    }
  }

  Future<void> _contents(LegalDocumentContent document) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Contents',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              for (final section in document.sections)
                ListTile(
                  title: Text(section.text),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, section.text),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final target = _sectionKeys[selected]?.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        alignment: .05,
      );
    }
  }

  Widget _body(LegalDocumentContent document) => Scrollbar(
    controller: _scroll,
    child: SingleChildScrollView(
      key: const Key('legal-scroll'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SelectionArea(
            child: Column(
              key: const Key('legal-body'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  document.officialTitle,
                  style: const TextStyle(
                    color: AppColors.accentSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.document.title,
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                for (final date in document.dates)
                  Text(
                    date,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                const SizedBox(height: 24),
                const Divider(),
                for (final block in document.blocks)
                  Padding(
                    key: block.style == LegalBlockStyle.section
                        ? _sectionKeys.putIfAbsent(
                            block.text,
                            () => GlobalKey(),
                          )
                        : null,
                    padding: EdgeInsets.only(
                      top: block.style == LegalBlockStyle.section ? 24 : 8,
                      bottom: block.style == LegalBlockStyle.paragraph ? 4 : 8,
                    ),
                    child: Semantics(
                      header: block.style != LegalBlockStyle.paragraph,
                      child: Text(
                        block.text,
                        style: TextStyle(
                          fontSize: block.style == LegalBlockStyle.section
                              ? 20
                              : 15,
                          height: block.style == LegalBlockStyle.section
                              ? 1.4
                              : 1.65,
                          fontWeight: block.style == LegalBlockStyle.paragraph
                              ? FontWeight.w400
                              : FontWeight.w700,
                          color: block.style == LegalBlockStyle.paragraph
                              ? AppColors.secondaryText
                              : AppColors.text,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<LegalDocumentContent>(
    future: _document,
    builder: (context, snapshot) => Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('legal-back'),
          tooltip: 'Back',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          widget.document.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (snapshot.hasData)
            IconButton(
              key: const Key('legal-contents'),
              tooltip: 'Contents',
              onPressed: () => _contents(snapshot.data!),
              icon: const Icon(Icons.format_list_bulleted_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: snapshot.hasData
            ? _body(snapshot.data!)
            : snapshot.hasError
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        color: AppColors.muted,
                        size: 36,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Could not load this document. Try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _document = _load();
                        }),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading document',
                ),
              ),
      ),
    ),
  );
}
