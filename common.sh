#!/bin/bash

JVMDIR=/usr/lib/jvm

#eg alternatives do not cognize /a/b//c as equals to /a/b/c
removeLinuxDoubleSlashes() {
  echo  "$1" | sed "s;/\\+;/;g" ;
}

createMainFakeAlternatives() {
    local target=${1}
    local rh_java_home=${JVMDIR}
    local priority=67899876  #should be ok up tojava 66, +1 or -1 should not harm it
    if [ ! "x${2}" == "x" ] ; then
      priority=${2}
    fi
    sudo alternatives --install /usr/bin/java java `removeLinuxDoubleSlashes $target/bin/java` ${priority} \
    --slave `removeLinuxDoubleSlashes $rh_java_home/jre` jre `removeLinuxDoubleSlashes $target/jre`
    sudo alternatives --install /usr/bin/javac javac `removeLinuxDoubleSlashes $target/bin/javac` ${priority} \
    --slave `removeLinuxDoubleSlashes $rh_java_home/java` java_sdk `removeLinuxDoubleSlashes $target`
}