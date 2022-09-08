#!/bin/bash
scriptDir=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

if [ ! -d $scriptDir/bigbluebutton ]; then
    echo "Place sbt_update_libs.sh in the same directory as 'bigbluebutton'"
    exit 1
fi

if [ $(whoami) == 'bigbluebutton' ]; then
	echo "Run sbt_update_libs.sh outside of the container"
	exit 1
fi

bbbRealease=$(head -n 1 $scriptDir/bigbluebutton/bigbluebutton-config/bigbluebutton-release)

if [[ $bbbRealease == BIGBLUEBUTTON_RELEASE\=2.5* ]] ; then
	echo "BBB 2.5 found"
	javaPath=$(ls -d /home/$(whoami)/.jdks/corretto-11.* | head -1)
elif [[ $bbbRealease == BIGBLUEBUTTON_RELEASE\=2.4* ]] ; then
	echo "BBB 2.4 found"
	javaPath=$(ls -d /home/$(whoami)/.jdks/corretto-1.8* | head -1)
elif [[ $bbbRealease == BIGBLUEBUTTON_RELEASE\=2.3* ]] ; then
	echo "BBB 2.3 found"
	javaPath=$(ls -d /home/$(whoami)/.jdks/corretto-1.8* | head -1)
else
	echo "BBB version is not compatible"
	exit 1
fi

if [ ! $javaPath ] ; then
	echo "Java $javaPath not found"
	exit 1
else
	echo "$javaPath found"
fi

export JAVA_HOME=$javaPath
export PATH="$JAVA_HOME/bin:$PATH"

buildOnly="${1:-all}"


cd $scriptDir/bigbluebutton/bbb-common-message; 
./deploy.sh;

if [ buildOnly != "akka" ] ; then
	cd $scriptDir/bigbluebutton/bbb-common-web;
	./deploy.sh;
fi;

cd $scriptDir/bigbluebutton/akka-bbb-apps;
sbt update
