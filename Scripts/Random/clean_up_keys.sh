#!/bin/bash
CLUSTER=nuc
CLUSTER=rancher
FILE=${HOME}/.ssh/known_hosts

for NODE in 1 2 3
do
  case $(uname) in 
    Linux)  ssh-keygen -R ${CLUSTER}-0${NODE} -f /home/mansible/.ssh/known_hosts;; 
    Darwin) sed -i "/${CLUSTER}-0${NODE}/d" $FILE;;
  esac
done



