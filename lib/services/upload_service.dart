import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class UploadService {
  final _storage = Supabase.instance.client.storage;

  Future<String> uploadFile({
    required String bucket,
    required String folder,
    required String filePath,
    String? filename,
    bool publicBucket = true,
    bool upsert = false,
  }) async {
    final file = File(filePath);
    final ext = filePath.split('.').last.toLowerCase();
    final name = filename ?? '${const Uuid().v4()}.$ext';
    final storagePath = '$folder/$name';

    await _storage
        .from(bucket)
        .upload(
          storagePath,
          file,
          fileOptions: FileOptions(cacheControl: '3600', upsert: upsert),
        );

    return publicBucket
        ? _storage.from(bucket).getPublicUrl(storagePath)
        : storagePath;
  }

  Future<void> deleteFile(String bucket, String storagePath) async {
    await _storage.from(bucket).remove([storagePath]);
  }

  String pathFromUrl(String publicUrl, String bucket) {
    final marker = '/object/public/$bucket/';
    final idx = publicUrl.indexOf(marker);
    if (idx == -1) return publicUrl;
    return publicUrl.substring(idx + marker.length);
  }
}
