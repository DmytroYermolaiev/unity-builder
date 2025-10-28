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

# 🧹 Replace Unity's built-in JDK 11 with Temurin 17
echo "☕ Overriding Unity built-in JDK with Temurin 17..."
rm -rf /opt/unity/Editor/Data/PlaybackEngines/AndroidPlayer/OpenJDK || true
mkdir -p /opt/unity/Editor/Data/PlaybackEngines/AndroidPlayer/OpenJDK
cp -r /usr/lib/jvm/temurin-17-jdk-amd64/* /opt/unity/Editor/Data/PlaybackEngines/AndroidPlayer/OpenJDK/
echo "✅ Unity JDK replaced with Temurin 17"

#
# 🧠 Force Unity to see correct JDK path
#
echo "💡 Forcing Unity to use external JDK 17..."
mkdir -p "$fullProjectPath/ProjectSettings"
if grep -q "androidJdkRoot:" "$fullProjectPath/ProjectSettings/EditorSettings.asset" 2>/dev/null; then
  sed -i 's|androidJdkRoot:.*|androidJdkRoot: /usr/lib/jvm/temurin-17-jdk-amd64|' "$fullProjectPath/ProjectSettings/EditorSettings.asset"
else
  echo "androidJdkRoot: /usr/lib/jvm/temurin-17-jdk-amd64" >> "$fullProjectPath/ProjectSettings/EditorSettings.asset"
fi

echo "🧠 Creating EditorPrefs.xml with correct paths..."
mkdir -p /root/.config/unity3d/Preferences
cat <<EOF > /root/.config/unity3d/Preferences/EditorPrefs.xml
<?xml version="1.0" encoding="UTF-8"?>
<unity_prefs version="1.0">
  <pref name="JdkPath" type="string">/opt/unity/Editor/Data/PlaybackEngines/AndroidPlayer/OpenJDK</pref>
  <pref name="SdkPath" type="string">/opt/unity/Editor/Data/PlaybackEngines/AndroidPlayer/SDK</pref>
  <pref name="NdkPath" type="string">/opt/unity/Editor/Data/PlaybackEngines/AndroidPlayer/NDK</pref>
  <pref name="GradlePath" type="string">/github/workspace/gradle-local/gradle-8.11</pref>
  <pref name="kPreferAndroidStudio" type="int">0</pref>
</unity_prefs>
EOF
echo "✅ EditorPrefs.xml created successfully."

#
# 🧠 Fix GameCI HOME redirection (Unity reads from /github/home)
#
echo "🧠 Ensuring Unity sees correct HOME and preferences..."
mkdir -p /github/home/.config/unity3d/Preferences
cp -f /root/.config/unity3d/Preferences/EditorPrefs.xml /github/home/.config/unity3d/Preferences/EditorPrefs.xml
export HOME="/github/home"
echo "✅ Copied EditorPrefs.xml to /github/home and set HOME=$HOME"

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
# 🚀 Run Unity build
#
echo "🚀 Starting Unity build..."
source /steps/runsteps.sh

exit $?
