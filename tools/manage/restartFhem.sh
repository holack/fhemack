#!/bin/bash

cd `dirname $0`

. setenv.sh

$MANAGE/stopFhem.sh

$MANAGE/startFhem.sh
