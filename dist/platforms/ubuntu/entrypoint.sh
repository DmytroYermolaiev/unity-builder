#!/usr/bin/env bash

# Ensure machine ID is randomized for personal license activation
if [[ "$UNITY_SERIAL" = F* ]]; then
  echo "Randomizing machine ID for personal license activation"
  dbus-uuidgen > /etc/machine-id && mkdir -p /var/lib/dbus/ && ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi

#
# Prepare Android SDK, if needed
# We do this here to ensure it has root permissions
#

fullProjectPath="$GITHUB_WORKSPACE/$PROJECT_PATH"

if [[ "$BUILD_TARGET" == "Android" ]]; then
  # ✅ Prefer external JDK 17 over Unity embedded JDK
  if [ -d "/usr/lib/jvm/temurin-17-jdk-amd64" ]; then
    echo "☕ Using external Temurin JDK 17"
    export JAVA_HOME="/usr/lib/jvm/temurin-17-jdk-amd64"
    export ANDROID_JAVA_HOME="$JAVA_HOME"
    export UNITY_JAVA_HOME="$JAVA_HOME"
    export UNITY_JDK=$JAVA_HOME
    export UNITY_JAVA_EXECUTABLE="$JAVA_HOME/bin/java"
    export PATH="$JAVA_HOME/bin:$PATH"
    rm -rf /opt/unity/Editor/Data/PlaybackEngines/AndroidPlayer/OpenJDK || true

    echo "✅ Java 17 detected at: $JAVA_HOME"
    $JAVA_HOME/bin/java -version
  else
    echo "❌ ERROR: External Temurin JDK 17 not found at /usr/lib/jvm/temurin-17-jdk-amd64"
    echo "💡 Please copy it before build using this step in your workflow:"
    echo "    sudo mkdir -p /usr/lib/jvm/temurin-17-jdk-amd64 && sudo cp -r \$JAVA_HOME/* /usr/lib/jvm/temurin-17-jdk-amd64/"
    exit 1
  fi

  # ✅ Prefer external ANDROID_HOME if present
  if [ -d "$ANDROID_HOME" ]; then
    ANDROID_HOME_DIRECTORY="$ANDROID_HOME"
  else
    ANDROID_HOME_DIRECTORY="$(awk -F'=' '/ANDROID_HOME=/{print $2}' /usr/bin/unity-editor.d/*)"
  fi

  echo "📦 Using Android SDK from: $ANDROID_HOME_DIRECTORY"
  SDKMANAGER=$(find $ANDROID_HOME_DIRECTORY/cmdline-tools -name sdkmanager || true)
  if [ -z "${SDKMANAGER}" ]; then
    SDKMANAGER=$(find $ANDROID_HOME_DIRECTORY/tools/bin -name sdkmanager || true)
    if [ -z "${SDKMANAGER}" ]; then
      echo "❌ No sdkmanager found in $ANDROID_HOME_DIRECTORY"
      exit 1
    fi
  fi

  if [[ -n "$ANDROID_SDK_MANAGER_PARAMETERS" ]]; then
    echo "Updating Android SDK with parameters: $ANDROID_SDK_MANAGER_PARAMETERS"
    $SDKMANAGER "$ANDROID_SDK_MANAGER_PARAMETERS"
  else
    echo "Updating Android SDK with auto detected target API version"
    # Read the line containing AndroidTargetSdkVersion from the file
    targetAPILine=$(grep 'AndroidTargetSdkVersion' "$fullProjectPath/ProjectSettings/ProjectSettings.asset")

    # Extract the number after the semicolon
    targetAPI=$(echo "$targetAPILine" | cut -d':' -f2 | tr -d '[:space:]')

    $SDKMANAGER "platforms;android-$targetAPI"
  fi

  echo "Updated Android SDK."
else
  echo "Not updating Android SDK."
fi

if [[ "$RUN_AS_HOST_USER" == "true" ]]; then
  echo "Running as host user"

  # Stop on error if we can't set up the user
  set -e

  # Get host user/group info so we create files with the correct ownership
  USERNAME=$(stat -c '%U' "$fullProjectPath")
  USERID=$(stat -c '%u' "$fullProjectPath")
  GROUPNAME=$(stat -c '%G' "$fullProjectPath")
  GROUPID=$(stat -c '%g' "$fullProjectPath")

  groupadd -g $GROUPID $GROUPNAME
  useradd -u $USERID -g $GROUPID $USERNAME
  usermod -aG $GROUPNAME $USERNAME
  mkdir -p "/home/$USERNAME"
  chown $USERNAME:$GROUPNAME "/home/$USERNAME"

  # Normally need root permissions to access when using su
  chmod 777 /dev/stdout
  chmod 777 /dev/stderr

  # Don't stop on error when running our scripts as error handling is baked in
  set +e

  # Switch to the host user so we can create files with the correct ownership
  su $USERNAME -c "$SHELL -c 'source /steps/runsteps.sh'"
else
  echo "Running as root"

  # Run as root
  source /steps/runsteps.sh
fi

exit $?
