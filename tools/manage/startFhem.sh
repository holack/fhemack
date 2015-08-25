#!/bin/bash

cd `dirname $0`

. setenv.sh

if [ -d "$INSTANCE_HOME" ]
then
	echo "Starte Fhem-Server..."
	$INSTANCE_HOME/fhem.pl $INSTANCE_HOME/fhem.cfg
else
	echo "Fhem ist nicht installiert."
fi
