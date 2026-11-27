import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'profile_controller.dart';
import 'profile_device.dart';
import '../../legal/presentation/consent_document_links.dart';
import '../../onboarding/application/consent_documents.dart';

class ProfileTextEditor extends StatefulWidget {
  const ProfileTextEditor({
    required this.profile,
    this.interestOnly = false,
    this.deleting = false,
    super.key,
  });
  final ProfileSummary profile;
  final bool interestOnly, deleting;
  @override
  State<ProfileTextEditor> createState() => _ProfileTextEditorState();
}

class _ProfileTextEditorState extends State<ProfileTextEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _alias, _bio, _height, _interest;
  @override
  void initState() {
    super.initState();
    _alias = TextEditingController(
      text: widget.deleting ? '' : widget.profile.alias,
    );
    _bio = TextEditingController(text: widget.profile.bio);
    _height = TextEditingController(
      text: widget.profile.heightCm?.toString() ?? '',
    );
    _interest = TextEditingController();
  }

  @override
  void dispose() {
    _alias.dispose();
    _bio.dispose();
    _height.dispose();
    _interest.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      widget.deleting
          ? <String, dynamic>{'delete': true}
          : widget.interestOnly
          ? <String, dynamic>{
              'interests': [...widget.profile.interests, _interest.text.trim()],
            }
          : <String, dynamic>{
              'alias': _alias.text.trim(),
              'bio': _bio.text.trim(),
              'height_cm': int.tryParse(_height.text),
            },
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.deleting
          ? 'Delete account and purge data?'
          : widget.interestOnly
          ? 'Add interest'
          : 'Edit profile',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.deleting) ...[
              const Text(
                'This permanently removes your profile, matches, media and safety data. Required financial records are retained separately.',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _alias,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                ),
                validator: (v) => v?.trim() == 'DELETE'
                    ? null
                    : 'Type DELETE exactly to confirm.',
              ),
            ] else if (widget.interestOnly)
              TextFormField(
                controller: _interest,
                autofocus: true,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'Interest',
                  hintText: 'e.g. Live music',
                ),
                validator: (v) => (v?.trim().length ?? 0) < 2
                    ? 'Enter 2–24 characters.'
                    : widget.profile.interests.length >= 10
                    ? 'You can add up to 10 interests.'
                    : widget.profile.interests.any(
                        (s) => s.toLowerCase() == v!.trim().toLowerCase(),
                      )
                    ? 'That interest is already added.'
                    : null,
              )
            else ...[
              TextFormField(
                controller: _alias,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Your alias'),
                validator: (v) => (v?.trim().length ?? 0) < 2
                    ? 'Enter at least 2 characters.'
                    : null,
              ),
              TextFormField(
                controller: _bio,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'About you'),
              ),
              TextFormField(
                controller: _height,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Height (optional)',
                  suffixText: 'cm',
                ),
                validator: (v) =>
                    v?.isEmpty != false ||
                        (int.tryParse(v!) != null &&
                            int.parse(v) >= 100 &&
                            int.parse(v) <= 250)
                    ? null
                    : 'Enter 100–250 cm.',
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _save,
        style: widget.deleting
            ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
            : null,
        child: Text(widget.deleting ? 'Delete permanently' : 'Save'),
      ),
    ],
  );
}

class ProfilePreferencesSheet extends StatefulWidget {
  const ProfilePreferencesSheet({required this.profile, super.key});
  final ProfileSummary profile;
  @override
  State<ProfilePreferencesSheet> createState() =>
      _ProfilePreferencesSheetState();
}

class _ProfilePreferencesSheetState extends State<ProfilePreferencesSheet> {
  late RangeValues _ages;
  late double _distance;
  late List<String> _genders;
  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _ages = RangeValues(
      p.minAgePref.clamp(18, 100).toDouble(),
      p.maxAgePref.clamp(p.minAgePref.clamp(18, 100), 100).toDouble(),
    );
    _distance = p.maxDistanceKm.clamp(1, 50).toDouble();
    _genders = [...p.targetGenders];
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Discovery preferences',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          const Text('Show me'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                {
                      'M': 'Men',
                      'W': 'Women',
                      'NB': 'Non-binary',
                      'ALL': 'Everyone',
                    }.entries
                    .map(
                      (e) => ChoiceChip(
                        label: Text(e.value),
                        selected: _genders.contains(e.key),
                        onSelected: (_) => setState(() {
                          if (e.key == 'ALL') {
                            _genders = ['ALL'];
                          } else {
                            _genders.remove('ALL');
                            _genders.contains(e.key)
                                ? _genders.remove(e.key)
                                : _genders.add(e.key);
                          }
                        }),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 16),
          Text('Age range: ${_ages.start.round()}–${_ages.end.round()}'),
          RangeSlider(
            values: _ages,
            min: 18,
            max: 100,
            divisions: 82,
            onChanged: (v) => setState(() => _ages = v),
          ),
          Text('Distance: ${_distance.round()} km'),
          Slider(
            value: _distance,
            min: 1,
            max: 50,
            divisions: 49,
            onChanged: (v) => setState(() => _distance = v),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _genders.isEmpty
                  ? null
                  : () => Navigator.pop(context, <String, dynamic>{
                      'target_genders': _genders,
                      'min_age_pref': _ages.start.round(),
                      'max_age_pref': _ages.end.round(),
                      'max_distance_km': _distance.round(),
                    }),
              child: const Text('Save preferences'),
            ),
          ),
        ],
      ),
    ),
  );
}

class ProfileConsentSheet extends ConsumerStatefulWidget {
  const ProfileConsentSheet({super.key});
  @override
  ConsumerState<ProfileConsentSheet> createState() =>
      _ProfileConsentSheetState();
}

class _ProfileConsentSheetState extends ConsumerState<ProfileConsentSheet> {
  List<ConsentSummary>? _items;
  String? _error, _saving;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiClientProvider).consents();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load your privacy choices.');
      }
    }
  }

  Future<void> _change(String type, bool value) async {
    if (_saving != null) return;
    if (!value) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Withdraw consent?'),
          content: Text(
            type == 'location'
                ? 'This removes your saved discovery location and any shared safety area. Nearby discovery will stop until you consent and update your location again.'
                : type == 'sensitive_data'
                ? 'This deletes who-you-want-to-meet preferences. Matching and revealing will stop until you consent and choose your preferences again.'
                : 'Your voice capsule will stop appearing to other people. You can also delete the recording from your profile.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep enabled'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Withdraw'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() => _saving = type);
    try {
      await ref
          .read(apiClientProvider)
          .recordConsent(
            type: type,
            version: ref.read(consentDocumentsProvider).version,
            granted: value,
          );
      await _load();
      if (mounted) await ref.read(profileProvider.notifier).afterMutation();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = profileError(e.code));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save your privacy choice.');
      }
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Privacy and consents',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const ConsentDocumentLinks(),
          const Divider(),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.coral)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
          if (_items == null && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_items != null) ...[
            for (final entry in {
              'location': 'Location',
              'sensitive_data': 'Matching details',
              'voice': 'Voice capsule',
            }.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                subtitle: Text(
                  entry.key == 'location'
                      ? 'Find people nearby using an approximate area.'
                      : entry.key == 'sensitive_data'
                      ? 'Use your gender and preferences privately for matching.'
                      : 'Allow people you appear to to hear your voice capsule.',
                ),
                value: _items!.any((c) => c.type == entry.key && c.granted),
                onChanged: _saving == null
                    ? (v) => _change(entry.key, v)
                    : null,
              ),
            const Divider(),
            for (final item in _items!.where(
              (c) => c.type == 'terms' || c.type == 'privacy',
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item.type == 'terms' ? 'Terms acceptance' : 'Privacy policy',
                ),
                subtitle: Text('Version ${item.version}'),
                trailing: Icon(
                  item.granted
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  color: item.granted ? AppColors.teal : AppColors.coral,
                ),
              ),
            const Text(
              'To stop using the service and withdraw your account, use Delete account and purge data.',
              style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}

class ProfileMediaSheet extends ConsumerStatefulWidget {
  const ProfileMediaSheet({required this.kind, super.key});
  final String kind;
  @override
  ConsumerState<ProfileMediaSheet> createState() => _ProfileMediaSheetState();
}

class _ProfileMediaSheetState extends ConsumerState<ProfileMediaSheet>
    with WidgetsBindingObserver {
  late final ProfileDevice _device;
  late final ProfilePlayer _previewPlayer;
  ProfileUpload? _draft;
  Uint8List? _photo;
  Timer? _timer;
  bool _busy = false, _recording = false, _disguise = true, _foreground = true;
  String? _error;
  int _seconds = 0;
  @override
  void initState() {
    super.initState();
    _device = ref.read(profileDeviceProvider)();
    _previewPlayer = ref.read(profilePlayerProvider)();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_device.dispose().catchError((Object _) {}));
    unawaited(_previewPlayer.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _recording) unawaited(_stop());
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await _device.pickPhoto(source);
      if (file == null || !mounted) return;
      if (await file.length() > 10485760) {
        throw const ApiException('media_too_large');
      }
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _photo = bytes;
          _draft = ProfileUpload(
            file: XFile.fromData(
              bytes,
              name: file.name,
              mimeType: file.mimeType,
            ),
            kind: 'avatar',
          );
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = profileError(e.code));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not access your photo. Check camera or photo permissions in phone settings.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _record() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _previewPlayer.pause();
      await _device.startRecording();
      if (!mounted) return;
      if (!_foreground) {
        await _device.stopRecording();
        return;
      }
      setState(() {
        _recording = true;
        _seconds = 0;
        _draft = null;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted) return;
        final elapsedSeconds = (timer.tick ~/ 10).clamp(0, 15);
        if (_seconds != elapsedSeconds) {
          setState(() => _seconds = elapsedSeconds);
        }
        if (timer.tick >= 150) {
          unawaited(_stop());
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = profileError(e.code));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not start recording. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _timer?.cancel();
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final file = await _device.stopRecording();
      if (file != null && mounted) {
        setState(() {
          _draft = ProfileUpload(
            file: file,
            kind: 'audio',
            disguise: _disguise,
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save this recording. Please re-record.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    if (_draft == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _previewPlayer.pause();
      final result = await _draft!.send(ref.read(apiClientProvider));
      if (result.status == 'rejected') throw ApiException(result.rejectionCode);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = profileError(e.code));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Upload failed. Your selection is still here; tap Upload to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.kind == 'avatar'
                      ? 'Your private photo'
                      : 'Your voice capsule',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.kind == 'avatar') ...[
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _photo == null
                    ? const ColoredBox(
                        color: AppColors.surfaceRaised,
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          size: 72,
                          color: AppColors.accentSoft,
                        ),
                      )
                    : Image.memory(
                        _photo!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Text('Choose a JPEG, PNG or WebP photo.'),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Only you see the original here. Others see a blurred version until you both agree to reveal.',
              style: TextStyle(color: AppColors.secondaryText),
            ),
            Wrap(
              spacing: 10,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Take photo'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose photo'),
                ),
              ],
            ),
          ] else ...[
            Text(
              '0:${_seconds.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w800),
            ),
            const Text(
              '15 seconds maximum. Say hi and tell people what you are like.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : _recording
                  ? _stop
                  : _record,
              icon: Icon(
                _recording ? Icons.stop_rounded : Icons.mic_none_rounded,
              ),
              label: Text(
                _recording
                    ? 'Stop recording'
                    : _draft == null
                    ? 'Record'
                    : 'Re-record',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Disguise my voice'),
              subtitle: const Text(
                'Pitch-shifts your capsule. A voice may still identify you.',
              ),
              value: _disguise,
              onChanged: _busy || _recording
                  ? null
                  : (v) => setState(() {
                      _disguise = v;
                      if (_draft != null) {
                        _draft = ProfileUpload(
                          file: _draft!.file,
                          kind: 'audio',
                          disguise: v,
                        );
                      }
                    }),
            ),
            if (_draft != null && !_recording)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          await _previewPlayer.play(
                            _draft!.file.path,
                            local: true,
                          );
                        } catch (_) {
                          if (mounted) {
                            setState(
                              () => _error = 'Could not preview the recording.',
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Preview original recording'),
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.coral),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy || _recording || _draft == null ? null : _upload,
              child: Text(
                _busy
                    ? 'Please wait…'
                    : widget.kind == 'avatar'
                    ? 'Upload photo'
                    : 'Upload capsule',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
