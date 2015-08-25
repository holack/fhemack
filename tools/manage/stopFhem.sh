#!/bin/bash

cd `dirname $0`

. setenv.sh

echo "Stoppe Fhem-Server..."
if [ -d $INSTANCE_HOME ]
then
	$INSTANCE_HOME/fhem.pl localhost:7072 shutdown
	echo "Fhem wurde gestoppt."
else
	echo "Fhem läuft im Moment nicht."
fi
