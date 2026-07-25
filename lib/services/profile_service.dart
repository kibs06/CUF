import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'upload_service.dart';

class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();

  final ImagePicker _picker = ImagePicker();
  final UploadService _uploadService = UploadService();
  SupabaseClient get _client => Supabase.instance.client;

  Future<XFile?> pickAvatarImage() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
      maxHeight: 1000,
      imageQuality: 85,
    );
  }

  Future<String> uploadAvatar({
    required String userId,
    required String filePath,
  }) async {
    final publicUrl = await _uploadService.uploadFile(
      bucket: 'avatars',
      folder: userId,
      filePath: filePath,
      filename: 'avatar.jpg',
      upsert: true,
    );

    // Cache-bust: the Storage path is always {userId}/avatar.jpg (upsert),
    // so the raw public URL never changes between uploads. Appending a
    // timestamp query param forces Image widgets to treat it as a new
    // image instead of serving the stale cached one.
    final cacheBustedUrl =
        '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';

    await _client
        .from('profiles')
        .update({'avatar_url': cacheBustedUrl})
        .eq('id', userId);

    return cacheBustedUrl;
  }
}
