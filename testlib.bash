#!/bin/bash

# initial impl of: https://docs.google.com/document/d/1kNx69oxUKsQ3ZhhUIBiRBKWJlfouZ5ZVSdYGlBPjuAk/
# there are two very important control variables
# TTL - if empty or 0, it is considered to be manual run, otherwise it is amount of seconds to wait for gui app to start
# DISPLAY - linux only, if set, then it is used. If not, VNC server is installed and launched on hardcoded support

set -ex
set -o pipefail
#TODO, some ar intel only - eg non portable remote ITWs or eclipse
#TODO, move to system vnc, to enable non-intel runs anyway


## resolve folder of this script, following all symlinks,
## http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  LIB_SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$LIB_SCRIPT_DIR/$SCRIPT_SOURCE"
done
readonly LIB_SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"

SKIPPED_ITW20="!skipped! ITW 2.0 do not have binary releases !skipped!"
SKIPPED_MSI_LINUX="!skipped! no testing of msi on linux !skipped!"
SKIPPED_itw_jdk16="!skipped! itw 1.7 seems to support jdk11 but is.. well old !skipped!"
SKIPPED_jdk_needed="!skipped! this test requires jdk, you are most likely on jre(-headless) !skipped!"
SKIPPED_jdk11_sdk="!skipped! On JDK11+, netbeans requires JDK, this looks to be JRE !skipped!"
SKIPPED_jmc_decom_fedora="!skipped! jmc is no longer packed for fedora !skipped!"
SKIPPED_el9="!skipped! no op on el9 !skipped!"

function skipOnModularJre() {
  if [  "x$OTOOL_JDK_VERSION" == "x" ]  ; then
    local OTOOL_JDK_VERSION=6
  fi
  if [  $OTOOL_JDK_VERSION -ge 11 ]  ; then
    # shellcheck disable=SC2166
    if [  "$OTOOL_jresdk" ==  "jre" -o  "$OTOOL_jresdk" ==  "jre~headless" ]  ; then
      echo "$SKIPPED_jdk11_sdk"
      exit 0
    fi
  fi
}


DIFF="true"

source "${LIB_SCRIPT_DIR}/common.sh"

parseArguments() {
  for a in "$@"
  do
    case $a in
      --jdk=*)
        ARG_JDK="${a#*=}"
      ;;
      --report-dir=*)
        ARG_REPORT_DIR="${a#*=}"
      ;;
      *)
        echo "Unrecognized argument: '$a'" >&2
        exit 1
      ;;
    esac
  done
}


processArguments() {
  if [[ -z $ARG_JDK ]] ; then
    echo "JDK was not specified" >&2
    exit 1
  elif ! readlink -e "$ARG_JDK" >/dev/null
  then
    echo "JDK was not found" >&2
    exit 1
  else
    readonly JAVA_DIR="$( readlink -e "$ARG_JDK" )"
  fi

  if [[ -z $ARG_REPORT_DIR ]] ; then
    echo "Report dir was not specified" >&2
    exit 1
  else
    readonly REPORT_DIR="$( readlink -m "$ARG_REPORT_DIR" )"
    mkdir -p "$REPORT_DIR"
  fi

  readonly REPORT_FILE="$REPORT_DIR/report.txt"
}

futureVnc="none"
function setup() {
  installImageMagick;
  if [ ! "x$OTOOL_OS_NAME" = "xwin" ] ; then
    if [ "x$DISPLAY" == "x" ] ; then
      installVnc
      futureVnc=":954"
      if ps -aux | grep -v -e grep | grep -e "$futureVnc" ; then
        echo "special vncserver/vncsession seems to be running"
        $LOCAL_VNC -kill $futureVnc
      fi
      $LOCAL_VNC $futureVnc << HeredocDelimiter
123qwe
123qwe

HeredocDelimiter
      #the empty lien above is crucial
      # only one trap is allowed
      trap "  allTraps ;" EXIT
      sleep 10 # some time for X to settle down
      export DISPLAY="$futureVnc"
    fi
  fi
}

function dnfyum() {
  if which dnf ; then
    sudo dnf install -y "$@" || sudo dnf install -y "$@" --enablerepo epel
  elif which yum ; then
    sudo yum install -y "$@" || sudo yum install -y "$@" --enablerepo epel
  else
    return 1
  fi
  ls -l "$JVMDIR"
  resetAlternatives
  ls -l "$JVMDIR"
}

function resetAlternatives() {
  # from commons, as is JVMDIR
  createMainFakeAlternatives "${ORIGINAL_EXPANDED_JDK}"
}

function dednfyum() {
  # plain remove pulls in also weird javas
  # thus removing also the,
  # and restoring alternatives as in install rpms
  if which dnf ; then
    sudo  dnf history info 0 | grep "${1}"
    sudo  dnf history undo 0 -y --skip-broken
    sudo  dnf remove -y "$@" || true # to double check the evil...
  elif which yum ; then
    # shellcheck disable=SC2155
    local lastTrans=$(sudo yum history  | grep ID -A 2 | tail -n 1 | sed "s/|.*//" | sed "s/\s\+//")
    sudo  yum history info "$lastTrans" | grep "${1}"
    sudo  yum history undo "$lastTrans" -y --skip-broken
    sudo  yum remove -y "$@" || true # to double check the evil...
  else
    return 1
  fi
  ls -l "$JVMDIR"
  resetAlternatives
  ls -l "$JVMDIR"
}


function installImageMagick() {
  if which import ; then
    echo "ImageMagic already on path"
  else
    if dnfyum ImageMagick ; then
      echo "installed by dnf/yum"
    else
      # wget? cygwin? different screenshot?
      echo "windows now can not do screenshots"
    fi
  fi
}

LOCAL_VNC=unsetVnc
# shellcheck disable=SC2209
LOCAL_VNC_PASS=unset
function installVnc() {
  # I have failed to reasonably safely run non-systemd vncserver via vncsession
  # falling down to downloaded vncserver
  LOCAL_VNC_VERSION=tigervnc-1.10.0.x86_64
  VNC_FILE=$(mktemp)
  if [ ! -e $LOCAL_VNC_VERSION ] ; then
    if [ ! -e $LOCAL_VNC_VERSION.tar.gz ] ; then
      #wget https://bintray.com/tigervnc/stable/download_file?file_path=$LOCAL_VNC_VERSION.tar.gz -O $LOCAL_VNC_VERSION.tar.gz
      wget -O $LOCAL_VNC_VERSION.tar.gz "https://downloads.sourceforge.net/project/tigervnc/stable/1.10.0/$LOCAL_VNC_VERSION.tar.gz?ts=gAAAAABglBcKEWSyLE75oSpmmmN7DwfBOSv_DTHifkztvfQyfaZZ7JYNqLB5tdMZ8PGwxu-Z-4Cma8N78_G6aR6bXgF3uMOfXg%3D%3D&r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Ftigervnc%2Ffiles%2Fstable%2F1.10.0%2F$LOCAL_VNC_VERSION.tar.gz%2Fdownload%3Fuse_mirror%3Dkumisystems"
    fi
    tar -xf $LOCAL_VNC_VERSION.tar.gz
  fi
  LOCAL_VNC=$PWD/$LOCAL_VNC_VERSION/usr/bin/vncserver
  LOCAL_VNC_PASS=$PWD/$LOCAL_VNC_VERSION/usr/bin/vncpasswd
}

# shellcheck disable=SC2166
if [ "x$TTL" = "x" -o "x$TTL" = "x0"  ] ; then
  ITW_HEADLESS=
else
  ITW_HEADLESS=--headless
fi

function beforeBg() {
  name=$1
  # shellcheck disable=SC2166
  if [ "x$TTL" = "x" -o "x$TTL" = "x0"  ] ; then
    echo "manual mode!"
  else
    import  -window root "$REPORT_DIR"/diff-01.png
  fi
}

getDescendants() (
  dpids="$( pgrep -P "$1" )"
  echo "${dpids}"
  for dpid in $dpids ; do
    getDescendants "${dpid}"
  done
)

function resolveBg() {
  pid=$1
  name=$2
  cname="diff"
  sleep 1
  echo "If this fails, it means that process have not even started"
  ps | grep "$pid" # to die if process do nto start
  # shellcheck disable=SC2166
  if [ "x$TTL" = "x" -o "x$TTL" = "x0"  ] ; then
    wait "$pid"
  else
    sleep "$TTL"
    import  -window root "$REPORT_DIR"/$cname-02.png
    ps
    #pstree
    cpids="$( getDescendants "$pid" )"|| true  # gets pids of descendant processes
    echo "If this fails, it means that process have crashed (or have not started and grep above failed)"
    kill -9 "$pid"
    if [ ! "x$cpids" = "x" ] ; then
      for cpid in $cpids ; do kill -9 "$cpid" ; done
    fi
    sleep 1
    import  -window root "$REPORT_DIR"/$cname-03.png
    if [ "$DIFF" == "true" ] ; then
      d12=$(compareImagesSilently $cname 01 02)
      d23=$(compareImagesSilently $cname 02 03)
      d13=$(compareImagesSilently $cname 01 03 03-01)
      if [ "$d12" -gt 15 ] ; then
        echo "error! images 1+2 are same, should be not"
        exit 1
      fi
      if [ "$d23" -gt 15 ] ; then
        echo "error! images 2+3 are same, should be not"
        exit 1
      fi
      if [ "$d13" -le 15 ] ; then
        echo "warning! images 1+3 are different, should be not"
        # exit 1 # The difference between first and last stage is probably not relevant, and may cause false-negatives
      fi
    else
      sleep 1 # otherwise ps will list few <defunct> zombies
    fi
    ps
  fi
}

function saveVncServerLog() {
  cp "$HOME"/.vnc/*954.log "$REPORT_DIR"/vncserver || true
}

function compareImagesSilently() {
  local r=0
  local name=$1
  local id1=$2
  local id2=$3
  local idCompOverride=$4
  if [ "x$idCompOverride" == "x" ] ; then
    idCompOverride=$id1-$id2
  fi
  compare  -metric PSNR  "$REPORT_DIR"/"$name"-"$id1".png "$REPORT_DIR"/"$name"-"$id2".png "$REPORT_DIR"/"$name"-"$idCompOverride".png  2> "$REPORT_DIR"/res-"$idCompOverride" || r=$?
  echo "40+ same, 10- different" 1>&2
  # shellcheck disable=SC2155
  # shellcheck disable=SC2002
  local diff=$(cat "$REPORT_DIR"/res-"$idCompOverride" | sed "s;\\..*;;")
  if [ "$diff" == "inf" ] ; then
    local diff=50 #same
  fi
  echo $diff
}


ITW_17=icedtea-web-1.7.2
ITW_DIR=icedtea-web-image
# shellcheck disable=SC2209
ITW=unset
#skip on jdk 11+?
function installIcedTeaWeb_17_portableArchive() {
  unset ITW_LIBS
  rm -rf $ITW_DIR
  # shellcheck disable=SC2209
  ITW=unset
  if [ ! -e $ITW_17.portable.bin.zip ] ; then
    wget http://icedtea.wildebeest.org/download/icedtea-web-binaries/1.7.2/$ITW_17.portable.bin.zip
  fi
  unzip $ITW_17.portable.bin.zip
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
      ITW=$PWD/$ITW_DIR/bin/javaws.bat
  else
      ITW=$PWD/$ITW_DIR/bin/javaws.sh
  fi
}

#skip on jdk 11?
function installIcedTeaWeb_17_binaryArchive() {
#  if [  $OTOOL_JDK_VERSION -gt 8 ]  ; then
#    echo "$SKIPPED_itw7_jdk11"
#    exit 0
#  fi
  unset ITW_LIBS
  rm -rf $ITW_DIR
  # shellcheck disable=SC2209
  ITW=unset
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
    if [ ! -e $ITW_17.win.bin.zip ] ; then
      wget http://icedtea.wildebeest.org/download/icedtea-web-binaries/1.7.2/windows/$ITW_17.win.bin.zip
    fi
    unzip $ITW_17.win.bin.zip
    ITW=$PWD/$ITW_DIR/bin/javaws.bat
  else
    if [ ! -e $ITW_17.linux.bin.zip ] ; then
      wget http://icedtea.wildebeest.org/download/icedtea-web-binaries/1.7.2/linux/$ITW_17.linux.bin.zip
    fi
    unzip $ITW_17.linux.bin.zip
    ITW=$PWD/$ITW_DIR/bin/javaws.sh
  fi
}

ITW_18=icedtea-web-1.8.4
function installIcedTeaWeb_18_portableArchive() {
  unset ITW_LIBS
  rm -rf $ITW_DIR
  # shellcheck disable=SC2209
  ITW=unset
  if [ ! -e $ITW_18.portable.bin.zip ] ; then
    wget https://github.com/AdoptOpenJDK/IcedTea-Web/releases/download/$ITW_18/$ITW_18.portable.bin.zip
  fi
  unzip $ITW_18.portable.bin.zip
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
      ITW=$PWD/$ITW_DIR/bin/javaws.bat
  else
      ITW=$PWD/$ITW_DIR/bin/javaws.sh
  fi
}

function installIcedTeaWeb_18_binaryArchive() {
  unset ITW_LIBS
  rm -rf $ITW_DIR
  # shellcheck disable=SC2209
  ITW=unset
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
    if [ ! -e $ITW_18.win.bin.zip ] ; then
      wget https://github.com/AdoptOpenJDK/IcedTea-Web/releases/download/$ITW_18/$ITW_18.win.bin.zip
    fi
    unzip $ITW_18.win.bin.zip
    ITW=$PWD/$ITW_DIR/bin/javaws.exe
  else
    if [ ! -e $ITW_18.linux.bin.zip ] ; then
      wget https://github.com/AdoptOpenJDK/IcedTea-Web/releases/download/$ITW_18/$ITW_18.linux.bin.zip
    fi
    unzip $ITW_18.linux.bin.zip
    ITW=$PWD/$ITW_DIR/bin/javaws
  fi
}


function installIcedTeaWeb_20_archive() {
 echo "$SKIPPED_ITW20"
}

function installIcedTeaWeb_bundled() {
  if [ "x$OTOOL_OS_NAME" = "xel" ]  ; then
    if [ "0$OTOOL_OS_VERSION" -ge "9" ] ; then
      echo "$SKIPPED_el9"
      exit 0
    fi
  fi
  if dnfyum icedtea-web ; then
    echo "installed by dnf yum"
    trap " allTraps ; dednfyum icedtea-web" EXIT
  else
    echo "windows have to install from msi (jdk8) or ignore (jdk11)"
    exit 1
  fi
}

# skip on jre
function createTestClass() {
  # shellcheck disable=SC2155
  local tmpd=$(mktemp -d)
  "$JAVA_DIR"/bin/javac -d "$tmpd"  "${SCRIPT_DIR}/src/swinghello/org/jlink/swingdemo/SwingHello.java"
  echo "$tmpd"
}

# skip on jre
function createJar() {
  # shellcheck disable=SC2155
  # shellcheck disable=SC2006
  local jarDir=`mktemp -d`
  local jarFile="$jarDir/jar.jar"
  local dirWithClass=$1
  pushd "$dirWithClass"
    "$JAVA_DIR"/bin/jar -cf "$jarFile" $(find .)
  popd
  echo "$jarFile"
}

function createJnlp() {
  local main="$1"
  local jar="$2"
  local jnlpFile="$3"
  local sec="$4"
  if [ "x$sec" = "xtrue" ] ; then
    sec="<security><all-permissions/></security>"
  else
    sec=""
  fi
cat << End-of-message
<?xml version="1.0" encoding="utf-8"?>
<jnlp spec="1.0+" 
        codebase="."
        href="$jnlpFile">
    <information>
        <title>`date` app</title>
        <vendor>jvanek</vendor>
    </information>
    <resources>
      <jar href="$jar" />
    </resources>
    $sec
    <application-desc
         name="`date` app"
         main-class="$main">
    <argument>`date`</argument>
    </application-desc>
</jnlp>
End-of-message
}

function signJar() {
  local keystore=local_keystore.ks
  local tcaw=my_terrible_cert
  local pass=super_secret
  local jar=$1
  rm -vf $keystore
  "$JAVA_DIR"/bin/keytool -genkey -keyalg RSA -alias $tcaw -keystore $keystore -keypass $pass -storepass $pass -dname "cn=$tcaw, ou=$tcaw, o=$tcaw, c=$tcaw"
  "$JAVA_DIR"/bin/jarsigner -keystore $keystore -storepass $pass -keypass $pass  "$jar"  $tcaw
  #$JAVA_DIR/bin/jarsigner -verify -verbose -keystore $keystore $jar
  rm -vf $keystore

}

function exitOnJre() {
  if [ ! -e "$JAVA_DIR"/bin/javac ] ; then
    echo "$SKIPPED_jdk_needed"
    exit 0
  fi
}


function prepareLocalApp() {
  JNLP=none
  exitOnJre
  # shellcheck disable=SC2155
  local clazz=$(createTestClass )
  # shellcheck disable=SC2155
  local jar=$(createJar "$clazz" | tail -n 1)
  local main="org.jlink.swingdemo.SwingHello"
  # shellcheck disable=SC2155
  local dir=$(dirname "$jar")
  local jnlp="$dir/app.jnlp"
  # shellcheck disable=SC2094
  createJnlp $main $(basename "$jar") $(basename "$jnlp") "$1" > "$jnlp"
  if [ "x$1" = "xtrue" ] ; then
    signJar "$jar"
  fi
  JNLP=$jnlp
  echo "$jnlp"
}

function runRemoteAppFromPath() {
  runRemoteApp javaws RemoteAppFromPath
}

function runRemoteApp() {
  # todo fix SweetHome, was always working!
  # runITW $1 $2 https://www.sweethome3d.com/SweetHome3D.jnlp
  # packgz error solemn for 1.8 toto, check rhel rpms
  # runITW $1 $2 https://phetsims.colorado.edu/sims/circuit-construction-kit/circuit-construction-kit-dc_en.jnlp
  runITW "$1" "$2"  https://josm.openstreetmap.de/download/josm.jnlp
}


function runITW() {
  if [  $OTOOL_JDK_VERSION -ge 16 ]  ; then
    echo "$SKIPPED_itw_jdk16"
    return 0
  fi
  export JAVA_HOME=$JAVA_DIR
  JAVA_HOME=$JAVA_DIR $1 $ITW_HEADLESS -Xclearcache  2>&1 | tee "$REPORT_DIR"/itwCache
  beforeBg "$2"
  JAVA_HOME=$JAVA_DIR bgWithLog "$1" $ITW_HEADLESS -Xnofork "$3" # accepting certificate, accepting desktop icons, accepting missing permission attribute and one spare
  resolveBg "$PID" "$2"
}



JMC_DIR="to_get_resolved_jmc_dir"
JMC_VERSION=jmc-7.1.2
function installJMC_archive() {
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
    JMC_DIR=$JMC_VERSION"_windows-x64"
    if [ ! -d $JMC_DIR ] ; then
      if [ ! -e $JMC_DIR.win.zip ] ; then
        wget https://download.java.net/java/GA/jmc7/04/binaries/$JMC_DIR".zip"
      fi
      unzip $JMC_DIR".zip"
    fi
  else
    JMC_DIR=$JMC_VERSION"_linux-x64"
    if [ ! -d $JMC_DIR ] ; then
      if [ ! -e $JMC_DIR.tar.gz ] ; then
        wget https://download.java.net/java/GA/jmc7/04/binaries/$JMC_DIR".tar.gz"
      fi
      tar -xf $JMC_DIR".tar.gz"
    fi
  fi
}

function runJmcFromDir() {
    beforeBg jmcFromDir
    bgWithLog $JMC_DIR/bin/jmc  -vm  "$JAVA_DIR"/bin/java
    resolveBg "$PID" jmcFromDir
}

sclrepo="false"
function el7SclRepo() {
  # shellcheck disable=SC2155
  local a=$(mktemp)
  echo "[rhel-7-server-rhscl-rpms-guisuite]
name=RHSCL RPMS for RHEL 7 System
baseurl=http://rhsm-pulp.corp.redhat.com/content/dist/rhel/server/7/\$releasever/\$basearch/rhscl/1/os/
enabled=1
gpgcheck=0" > "$a"
  REPOFILE=/etc/yum.repos.d/rhel-7-server-rhscl-rpms-guisuite.repo
  sudo cp -v "$a" $REPOFILE
  sclrepo="true"
}

function installJMC_bundled() {
  #todo el7 - scl, el8,f32,f33 module, f34 - just jmc package, f35 dropped, el9 .. who knows
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
    echo "windows have to install bundled jmc from msi"
    exit 1
  elif [ "x$OTOOL_OS_NAME" = "xel" ]  ; then
    if [ "x$OTOOL_OS_VERSION" = "x7" ] ; then
      el7SclRepo
      dnfyum rh-jmc
      trap "allTraps ;dednfyum rh-jmc" EXIT
    else
      dnfyum jmc
      trap "allTraps ;dednfyum jmc" EXIT
    fi
  elif [ "x$OTOOL_OS_NAME" = "xf" ] ; then
    if [ "$OTOOL_OS_VERSION" -le "33" ] ; then
      sudo dnf module enable -y  jmc:latest
      dnfyum jmc
      trap "allTraps ;dednfyum jmc" EXIT
    else
      dnfyum jmc
      trap "allTraps ;dednfyum jmc" EXIT
    fi
  else
    echo "unknown os"
    exit 1
  fi
}

function runJmcOnPath() {
    beforeBg jmcOnPath
    # shellcheck disable=SC2166
    if [ "x$OTOOL_OS_NAME" = "xel" -a "x$OTOOL_OS_VERSION" = "x7" ] ; then
      bgWithLog scl enable rh-jmc -- jmc -vm "$JAVA_DIR"/bin/java
    else
      bgWithLog jmc -vm "$JAVA_DIR"/bin/java
    fi
    resolveBg "$PID" jmcOnPath
}


IDEA_DIR=idea-IC-202.7660.26
IDEA_ARCHIVE=ideaIC-2020.2.3
if [  $OTOOL_JDK_VERSION -gt 11 ]  ; then
  IDEA_DIR=idea-IC-231.9011.34
  IDEA_ARCHIVE=ideaIC-2023.1.2
fi

function installIdea_archive() {
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
    if [ ! -d $IDEA_DIR ] ; then
      if [ ! -e $IDEA_ARCHIVE.win.zip ] ; then
        wget https://download.jetbrains.com/idea/$IDEA_ARCHIVE.win.zip
      fi
      unzip $IDEA_ARCHIVE.win.zip
    fi
  else
    if [ ! -d $IDEA_DIR ] ; then
      if [ ! -e $IDEA_ARCHIVE.tar.gz ] ; then
        wget https://download.jetbrains.com/idea/$IDEA_ARCHIVE.tar.gz
      fi
      tar -xf $IDEA_ARCHIVE.tar.gz
    fi
  fi
}


function runIdea_archive() {
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
   local suffix="exe"
  else
   local suffix="sh"
  fi
  beforeBg idea
  # suffix-less should work also on windows
  export IDEA_JDK=$JAVA_DIR
  IDEA_JDK=$JAVA_DIR bgWithLog $IDEA_DIR/bin/idea.$suffix
  resolveBg "$PID" idea
}

NETBEANS_VERSION="12.3"
if [ $OTOOL_JDK_VERSION -gt 11 ]  ; then
  NETBEANS_VERSION=18    
fi
function installNetBeans_archive() {
  local archive="netbeans-$NETBEANS_VERSION-bin.zip"
  # we will need to cache this 400mb installer
  if [ ! -d netbeans ] ; then
    # shellcheck disable=SC2166
    if [ ! -e "$archive" -a -e "/mnt/shared/jdk-images/apache/$archive" ] ; then
      cp "/mnt/shared/jdk-images/apache/$archive" "$PWD" || echo "local copy exists, but failed to copy"
   fi
    if [ ! -e "$archive" ] ; then
      wget "https://archive.apache.org/dist/netbeans/netbeans/$NETBEANS_VERSION/$archive" #should be os-independent
   fi
   unzip "$archive"
 fi
}

function runNetBeans_archive() {
  beforeBg netbeans
  # suffix-less should work also on windows
  bgWithLog netbeans/bin/netbeans --jdkhome "$JAVA_DIR"
  resolveBg "$PID" netbeans
}


function msiGui() {
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
    beforeBg msi
    # shellcheck disable=SC2211
    rpms/*.msi
    resolveBg $! msi
  else
    echo "$SKIPPED_MSI_LINUX"
  fi
}

#all three remote apps linked in this file are signed, so is one half of local cases
function assertSigningHeadlessDialogue() {
  if [ "x$ITW_HEADLESS" = "x--headless" ] ; then
     set +x # otherwise we are grepping ourselves form report
     # shellcheck disable=SC2002
     cat "$REPORT_FILE" | grep "digital signature"
     set -x
  fi
}


if [  "0$OTOOL_JDK_VERSION" -gt "8" ]  ; then
    Eclipse_DATE=2020-09
else
    Eclipse_DATE=2019-12
fi

Eclipse_DIR="eclipse"
Eclipse_ARCHIVE="eclipse-java-$Eclipse_DATE-R"
Eclipse_URL="https://www.eclipse.org/downloads/download.php?file=/technology/epp/downloads/release/$Eclipse_DATE/R" #warning, tailing slashes counts
function installEclipse_archive() {
  rm -rf $Eclipse_DIR #to debug with different versions of jdk
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
    local archive="$Eclipse_ARCHIVE-win32-x86_64.zip"
  else
    local archive="$Eclipse_ARCHIVE-linux-gtk-x86_64.tar.gz"
  fi
  # shellcheck disable=SC2166
  if [ ! -e "$archive" -a -e "/mnt/shared/jdk-images/eclipse/$archive" ] ; then
      cp "/mnt/shared/jdk-images/eclipse/$archive" "$PWD" || echo "local copy not exists but failed to copy"
  fi
  if [ ! -d $Eclipse_DIR ] ; then
    if [ ! -e "$archive" ] ; then
      wget "$Eclipse_URL/$archive" -O "$archive"
    fi
    if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
      unzip "$archive"
    else
      tar -xf "$archive"
    fi
  fi
}


function runEclipse_archive() {
  if [ "x$OTOOL_OS_NAME" = "xwin" ] ; then
   local suffix=".exe"
  else
   local suffix=""
  fi
  beforeBg eclipse
  # suffix-less should work also on windows
  bgWithLog $Eclipse_DIR/eclipse"$suffix" -vm "$JAVA_DIR"/bin/java  -data "$ECLIPSE_LOGS"
  resolveBg "$PID" eclipse
}

function bgWithLog() {
  rm -rf pid > /dev/null 2>&1 ; sync
# the YES is for ITW, in other should be harmless  - accepting certificate, accepting desktop icons, accepting missing permission attribute and one spare
    (   echo "YES
YES
YES
YES
" | "$@" 2>&1 & echo $! >&3 ) 3>pid | tee "$REPORT_DIR"/app  & # may read stdin!
    sync #?
    PID=$(cat pid) ;   sync  ; rm -rf pid
}

ECLIPSE_PLATFORM=$HOME/.eclipse
JMC_LOGS=$HOME/.jmc
ECLIPSE_LOGS=$HOME/EclipseTmpWorkspace

postpre_eclipse="false"
function preEclipse() {
  rm -rf "$ECLIPSE_PLATFORM" || true
  mkdir "$ECLIPSE_PLATFORM"  || true
  rm -rf "$JMC_LOGS" || true
  mkdir "$JMC_LOGS"  || true
  rm -rf "$ECLIPSE_LOGS" || true
  mkdir "$ECLIPSE_LOGS"  || true
  postpre_eclipse="true"
}

function postEclipse() {
  if [ "x$postpre_eclipse" = "xtrue" ] ; then
    cp -r  "$ECLIPSE_PLATFORM"/ "$REPORT_DIR/eclipse"  || true
    cp -r  "$JMC_LOGS"/ "$REPORT_DIR/jmc"  || true
    cp -r  "$ECLIPSE_LOGS"/ "$REPORT_DIR/eclipse-data"  || true
  fi
}

function allTraps() {
  saveVncServerLog
  postEclipse
  if [ ! "x$futureVnc" = "xnone" ] ; then
    $LOCAL_VNC -kill $futureVnc || true
  fi
  if [ "x$sclrepo" = "xtrue" ] ; then
    sudo rm -fv $REPOFILE
  fi
}
