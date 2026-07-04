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

    await _client
        .from('profiles')
        .update({'avatar_url': publicUrl})
        .eq('id', userId);

    return publicUrl;
  }
}
