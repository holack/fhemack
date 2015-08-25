#!/bin/bash

cd `dirname $0`

SCRIPT_HOME=`pwd`
BUILD_DIR=$SCRIPT_HOME/../..
SVN_TARGET=$BUILD_DIR/fhem
MANAGE=$BUILD_DIR/tools/manage
INSTANCE_TARGET=$BUILD_DIR/instance

echo $SCRIPT_HOME
echo $BUILD_DIR
echo $SVN_TARGET

cd $SCRIPT_HOME
. build.cfg

cd $BUILD_DIR

svn co $SVNBASE $SVN_TARGET

$MANAGE/stopFhem.sh

echo $INSTANCE_TARGET

rm -rf $INSTANCE_TARGET
mkdir $INSTANCE_TARGET

cp -R "$SVN_TARGET/." "$INSTANCE_TARGET"
rm -rf $INSTANCE_TARGET/.svn
rm -f $INSTANCE_TARGET/fhem.cfg
rm -f $INSTANCE_TARGET/fhem.cfg

cp -R $BUILD_DIR/config $INSTANCE_TARGET
ln -s $INSTANCE_TARGET/config/fhem.cfg $INSTANCE_TARGET/fhem.cfg
