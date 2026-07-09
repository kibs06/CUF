@echo off
REM Run release build with permanent dart-defines
flutter build apk --dart-define-from-file=dart_defines.json