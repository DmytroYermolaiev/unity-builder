#!/usr/bin/env bash

# Ensure machine ID is randomized for personal license activation
if [[ "$UNITY_SERIAL" = F* ]]; then
  echo "Randomizing machine ID for personal license activation"
  dbus-uuidgen > /etc/machine-id && mkdir -p /var/lib/dbus/ && ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi

fullProjectPath="$GITHUB_WORKSPACE/$PROJECT_PATH"

#
# 🧩 Install and configure Temurin 17 JDK inside the container
#
echo "☕ Checking for Temurin 17..."
if [ ! -d "/usr/lib/jvm/temurin-17-jdk-amd64" ]; then
  echo "📦 Installing Temurin 17 (apt-get)..."
  apt-get update -qq && apt-get install -y --no-install-recommends temurin-17-jdk
fi

if [ ! -d "/usr/lib/jvm/temurin-17-jdk-amd64" ]; then
  echo "❌ Failed to install Temurin 17 JDK. Exiting."
  exit 1
fi

# ✅ Force Unity and Gradle to use JDK17
export JAVA_HOME="/usr/lib/jvm/temurin-17-jdk-amd64"
export ANDROID_JAVA_HOME="$JAVA_HOME"
export UNITY_JAVA_HOME="$JAVA_HOME"
export UNITY_JDK="$JAVA_HOME"
export UNITY_JAVA_EXECUTABLE="$JAVA_HOME/bin/java"
export PATH="$JAVA_HOME/bin:$PATH"

# Remove old Unity JDK 11
rm -rf /opt/unity/Editor/Data/PlaybackEngines/AndroidPlayer/OpenJDK || true

echo "✅ Using Java from: $JAVA_HOME"
$JAVA_HOME/bin/java -version || { echo "❌ Java not working."; exit 1; }

JAVA_VER=$($JAVA_HOME/bin/java -version 2>&1 | grep 'version' | grep '17' || true)
if [ -z "$JAVA_VER" ]; then
  echo "❌ ERROR: Java 17 not active! Build will stop."
  exit 1
fi

#
# 🧩 Prepare Android SDK if needed
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

  if [[ -n "$ANDROID_SDK_MANAGER_PARAMETERS" ]]; then
    echo "Updating Android SDK with parameters: $ANDROID_SDK_MANAGER_PARAMETERS"
    $SDKMANAGER "$ANDROID_SDK_MANAGER_PARAMETERS"
  else
    targetAPILine=$(grep 'AndroidTargetSdkVersion' "$fullProjectPath/ProjectSettings/ProjectSettings.asset" || true)
    targetAPI=$(echo "$targetAPILine" | cut -d':' -f2 | tr -d '[:space:]')
    if [ -n "$targetAPI" ]; then
      $SDKMANAGER "platforms;android-$targetAPI"
    else
      echo "⚠️ Could not detect AndroidTargetSdkVersion — skipping SDK update"
    fi
  fi

  echo "✅ Android SDK ready."
else
  echo "Not updating Android SDK."
fi

#
# 🧩 Continue standard GameCI workflow
#
if [[ "$RUN_AS_HOST_USER" == "true" ]]; then
  echo "Running as host user"

  set -e
  USERNAME=$(stat -c '%U' "$fullProjectPath")
  USERID=$(stat -c '%u' "$fullProjectPath")
  GROUPNAME=$(stat -c '%G' "$fullProjectPath")
  GROUPID=$(stat -c '%g' "$fullProjectPath")

  groupadd -g $GROUPID $GROUPNAME
  useradd -u $USERID -g $GROUPID $USERNAME
  usermod -aG $GROUPNAME $USERNAME
  mkdir -p "/home/$USERNAME"
  chown $USERNAME:$GROUPNAME "/home/$USERNAME"

  chmod 777 /dev/stdout /dev/stderr
  set +e

  su $USERNAME -c "$SHELL -c 'source /steps/runsteps.sh'"
else
  echo "Running as root"
  source /steps/runsteps.sh
fi

exit $?
