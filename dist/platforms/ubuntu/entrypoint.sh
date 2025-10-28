#!/usr/bin/env bash
set -e

# 🧠 Randomize machine ID for Unity personal license activation
if [[ "$UNITY_SERIAL" = F* ]]; then
  echo "🔑 Randomizing machine ID for personal license activation..."
  dbus-uuidgen > /etc/machine-id && mkdir -p /var/lib/dbus/ && ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi

fullProjectPath="$GITHUB_WORKSPACE/$PROJECT_PATH"

#
# ☕ Install Temurin 17 JDK if missing
#
echo "☕ Checking for Temurin 17..."
if [ ! -d "/usr/lib/jvm/temurin-17-jdk-amd64" ]; then
  echo "📦 Installing Temurin 17 JDK..."
  apt-get update -qq && apt-get install -y wget apt-transport-https gnupg
  wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg
  echo "deb [arch=amd64] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print $2}' /etc/os-release) main" \
    > /etc/apt/sources.list.d/adoptium.list
  apt-get update -qq
  apt-get install -y temurin-17-jdk || { echo "❌ Failed to install Temurin 17 JDK. Exiting."; exit 1; }
fi

# ✅ Verify installation
if [ ! -x "/usr/lib/jvm/temurin-17-jdk-amd64/bin/java" ]; then
  echo "❌ Temurin 17 installation failed or missing binaries!"
  exit 1
fi

echo "✅ Using Java from: /usr/lib/jvm/temurin-17-jdk-amd64"
export JAVA_HOME="/usr/lib/jvm/temurin-17-jdk-amd64"
export UNITY_JAVA_HOME="$JAVA_HOME"
export UNITY_JAVA_EXECUTABLE="$JAVA_HOME/bin/java"
export UNITY_JDK="$JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
$JAVA_HOME/bin/java -version

# 🧹 Remove old Unity JDK 11
rm -rf /opt/unity/Editor/Data/PlaybackEngines/AndroidPlayer/OpenJDK || true

#
# 🧠 Force Unity to see correct JDK path
#
echo "💡 Forcing Unity to use external JDK 17..."
# Update Unity Editor settings
mkdir -p "$fullProjectPath/ProjectSettings"
if grep -q "androidJdkRoot:" "$fullProjectPath/ProjectSettings/EditorSettings.asset" 2>/dev/null; then
  sed -i 's|androidJdkRoot:.*|androidJdkRoot: /usr/lib/jvm/temurin-17-jdk-amd64|' "$fullProjectPath/ProjectSettings/EditorSettings.asset"
else
  echo "androidJdkRoot: /usr/lib/jvm/temurin-17-jdk-amd64" >> "$fullProjectPath/ProjectSettings/EditorSettings.asset"
fi

# Also create Unity prefs for external tools
mkdir -p /root/.local/share/unity3d/Unity/Editor
echo "jdkPath=/usr/lib/jvm/temurin-17-jdk-amd64" > /root/.local/share/unity3d/Unity/Editor/Preferences.plist

echo "✅ JDK path applied to Unity settings."

#
# 🧩 Prepare Android SDK (optional)
#
if [[ "$BUILD_TARGET" == "Android" ]]; then
  if [ -d "$ANDROID_HOME" ]; then
    ANDROID_HOME_DIRECTORY="$ANDROID_HOME"
  else
    ANDROID_HOME_DIRECTORY="$(awk -F'=' '/ANDROID_HOME=/{print $2}' /usr/bin/unity-editor.d/*)"
  fi

  echo "📦 Using Android SDK from: $ANDROID_HOME_DIRECTORY"
  SDKMANAGER=$(find "$ANDROID_HOME_DIRECTORY"/cmdline-tools -name sdkmanager 2>/dev/null || true)
  if [ -z "${SDKMANAGER}" ]; then
    SDKMANAGER=$(find "$ANDROID_HOME_DIRECTORY"/tools/bin -name sdkmanager 2>/dev/null || true)
    if [ -z "${SDKMANAGER}" ]; then
      echo "❌ No sdkmanager found in $ANDROID_HOME_DIRECTORY"
      exit 1
    fi
  fi

  targetAPILine=$(grep 'AndroidTargetSdkVersion' "$fullProjectPath/ProjectSettings/ProjectSettings.asset" || true)
  targetAPI=$(echo "$targetAPILine" | cut -d':' -f2 | tr -d '[:space:]')
  if [ -n "$targetAPI" ]; then
    echo "📥 Ensuring Android API $targetAPI installed..."
    $SDKMANAGER "platforms;android-$targetAPI" || true
  else
    echo "⚠️ Could not detect AndroidTargetSdkVersion — skipping SDK update."
  fi
  echo "✅ Android SDK ready."
else
  echo "🏁 Non-Android build — skipping SDK setup."
fi

#
# 🚀 Run Unity build as root (GameCI default)
#
echo "🚀 Starting Unity build..."
source /steps/runsteps.sh

exit $?
