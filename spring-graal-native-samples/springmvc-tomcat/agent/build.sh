#!/usr/bin/env bash

APP=springmvc-tomcat
MAINCLASS=com.example.tomcat.TomcatApplication
VERSION=0.0.1-SNAPSHOT
FEATURE=`find ${PWD%/*spring-graal-native*/*}/spring-graal-native/target -name "spring-graal-native-*.jar"`

echo "================ BUILDING THE PROJECT AND UNPACKING THE FAT JAR =========="
cd ..
mvn clean package
cd agent
rm -rf unpack
unzip -q ../target/$APP-$VERSION.jar -d unpack
cd unpack/BOOT-INF/classes
cp -R ../../META-INF .
rm -rf graal
mkdir -p graal/META-INF/native-image

# Set the CP for the jars/code in the unpacked application, leaving us in the BOOT-INF/classes folder
export CP=`find ../../BOOT-INF/lib | tr "\n" ":"`

echo "============== RUNNING THE APPLICATION WITH THE AGENT TO POPULATE CONFIGURATION FILES ========="
echo "(for debug see agent-output.txt)"
echo "Running for 10 seconds"
java -cp .:$CP \
  -agentlib:native-image-agent=config-output-dir=graal/META-INF/native-image \
  $MAINCLASS > agent-output.txt 2>&1 &
PID=$!
sleep 10
../../../verify.sh
echo "Killing..."
kill ${PID}
KILLED=$?
if [[ $KILLED != 0 ]]
then
echo "Failed to kill it! (Process ${PID})"
exit 1
fi
sleep 3

# Run native image to compile the application
native-image \
  -Dspring.graal.mode=agent \
  --no-server \
  --no-fallback \
  -H:+TraceClassInitialization \
  -H:+ReportExceptionStackTraces \
  -H:Name=$APP-agent \
  -H:IncludeResourceBundles=javax.servlet.LocalStrings \
  -H:IncludeResourceBundles=javax.servlet.http.LocalStrings \
  -cp .:$CP:graal:../../../graal:$FEATURE \
  $MAINCLASS 2>&1 | tee output.txt

# Test the application
# The test script will look for it in the current folder
cp ../../../verify.sh .
${PWD%/*samples/*}/scripts/test.sh $APP-agent .
mkdir -p ../../../target/native-image/
mv summary.csv ../../../target/native-image/