#!/bin/bash

step=20 #间隔的秒数，不能大于60

while [ 1 -eq 1 ] 
do
    git pull origin
    sleep $step
done

exit 0

