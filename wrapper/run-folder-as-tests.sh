#!/bin/bash

set -x
set -e
set -o pipefail

## resolve folder of this script, following all symlinks,
## http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
readonly SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"

DIR=$1

if [ "x$DIR" == "x" ] ; then
 echo "dir with tests reqired"
fi

SUITE=`basename $DIR`

FAILED_TESTS=0
ALL_TESTS=0
PASSED_TESTS=0
SKIPPED_TESTS=0
tmpXmlBodyFile=$(mktemp)
TMPRESULTS=$SCRIPT_DIR/../results

rm -rf $SCRIPT_DIR/$SUITE
set -x
#mkdir $SCRIPT_DIR/$SUITE
mkdir $TMPRESULTS
rpm -qa | sort > $TMPRESULTS/rpms.txt
if [ "$?" -ne "0" ]; then
  let FAILED_TESTS=$FAILED_TESTS+1
fi

TESTS=`ls $DIR | grep "\\.sh$" | sort`
echo -n "" > ${TMPRESULTS}/results.txt

source $SCRIPT_DIR/jtreg-shell-xml.sh

function isIgnored() {
  cat $TMPRESULTS/$TEST-result/global-stdouterr.log | grep -e "^\!skipped!"
}

function failOrIgnore() {
  printXmlTest "$SUITE.test" "$TEST" "0.01" "$TMPRESULTS/$TEST-result/global-stdouterr.log" "../artifact/results/$TEST-result/global-stdouterr.log and ../artifact/results/$TEST-result/report.txt" >> $tmpXmlBodyFile
}

if [ "x$RFAT_RERUNS" == "x" ] ; then
  RFAT_RERUNS=5
fi

for TEST in $TESTS ; do
  cd $SCRIPT_DIR/
  TTDIR=$TMPRESULTS/$TEST-result
  set +e
  for x in `seq $RFAT_RERUNS` ; do
    if [ "x$x" = "x1" ] ; then
      echo  "--------ATTEMPT $x/$RFAT_RERUNS of $TEST ----------"
    else
      echo  "https://gitlab.cee.redhat.com/java-qa/TckScripts/-/merge_requests/88/"
      echo  "--------ATTEMPT $x/$RFAT_RERUNS of $TEST ----------"
    fi
    rm -rf $TTDIR
    mkdir $TTDIR
    bash $DIR/$TEST  --jdk=$ENFORCED_JDK --report-dir=$TTDIR   2>&1 | tee $TTDIR/global-stdouterr.log
    RES=$?
    if [ $RES -eq 0 ] ; then
      break
    fi
  done
  echo "Attempt: $x/$RFAT_RERUNS" >> $TMPRESULTS/$TEST-result/global-stdouterr.log
  set -e
  if [ ${RES} -eq 0 ]; then
    if isIgnored ; then
      SKIPPED_TESTS=$(($SKIPPED_TESTS+1))
      echo -n "Ignored" >> ${TMPRESULTS}/results.txt
      failOrIgnore
    else
      echo -n "Passed" >> ${TMPRESULTS}/results.txt
      PASSED_TESTS=$(($PASSED_TESTS + 1))
      printXmlTest $SUITE.test $TEST 0.01 >> $tmpXmlBodyFile
   fi
  else
    if isIgnored ; then
      SKIPPED_TESTS=$(($SKIPPED_TESTS+1))
      echo -n "Ignored" >> ${TMPRESULTS}/results.txt
      failOrIgnore
    else
      FAILED_TESTS=$(($FAILED_TESTS+1))
      echo -n "FAILED" >> ${TMPRESULTS}/results.txt
      failOrIgnore
    fi
  fi
  echo " $TEST" >> ${TMPRESULTS}/results.txt
  ALL_TESTS=$(($ALL_TESTS+1))
done

printXmlHeader $PASSED_TESTS $FAILED_TESTS $ALL_TESTS $SKIPPED_TESTS $SUITE >  $TMPRESULTS/$SUITE.jtr.xml
cat $tmpXmlBodyFile >>  $TMPRESULTS/$SUITE.jtr.xml
printXmlFooter >>  $TMPRESULTS/$SUITE.jtr.xml
rm $tmpXmlBodyFile
pushd $TMPRESULTS
  tar -czf  $SUITE.tar.gz $SUITE.jtr.xml
popd

echo "Failed: $FAILED_TESTS"

# returning 0 to allow unstable state
exit 0
