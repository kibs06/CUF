-- Add a bio text column to the profiles table for the Edit Profile screen.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio text;
