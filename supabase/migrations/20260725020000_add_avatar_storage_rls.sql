-- ══════════════════════════════════════════════════════════════════
-- Fix: Avatar Upload RLS — storage.objects policies for avatars bucket
-- Date: July 25, 2026
-- Bug: StorageException 403 "new row violates row-level security policy"
--      when uploading to the avatars bucket.
-- Root cause: No INSERT/UPDATE policies on storage.objects for the
--             avatars bucket. Supabase default RLS blocks all writes.
-- ══════════════════════════════════════════════════════════════════

-- Upload path convention (from ProfileService.uploadAvatar):
--   bucket: 'avatars', folder: userId, filename: 'avatar.jpg'
--   → storage path: {userId}/avatar.jpg
--   → storage.foldername(name)[1] = userId

-- 1. INSERT — authenticated users can upload into their own folder
CREATE POLICY "Users can upload their own avatar"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- 2. UPDATE — authenticated users can overwrite their own avatar (upsert)
CREATE POLICY "Users can update their own avatar"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- 3. SELECT — avatars are publicly readable in the UI
CREATE POLICY "Avatar images are publicly accessible"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'avatars');

-- 4. DELETE — users can delete their own avatar file
CREATE POLICY "Users can delete their own avatar"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );
