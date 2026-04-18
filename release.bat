@echo off
set VERSION=%1

gh release create v%VERSION% ^
  build\app\outputs\flutter-apk\app-arm64-v8a-release.apk ^
  build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk ^
  --repo masozin/exambro ^
  --title "Versi %VERSION%" ^
  --notes "Update versi %VERSION%"