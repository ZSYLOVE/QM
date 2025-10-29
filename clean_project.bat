@echo off
echo 清理Flutter项目缓存...

echo 1. 清理Flutter缓存
flutter clean

echo 2. 清理Gradle缓存
cd android
gradlew clean
cd ..

echo 3. 清理pub缓存
flutter pub cache clean

echo 4. 重新获取依赖
flutter pub get

echo 5. 重新构建项目
flutter build apk --debug

echo 清理完成！
pause

