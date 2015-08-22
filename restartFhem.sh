#!/bin/bash

echo Stoppe Fhem-Server...
./fhem.pl localhost:7072 shutdown
echo Fertig.

echo Start Fhem-Server...
./fhem.pl ./fhem.cfg
echo Fertig.
