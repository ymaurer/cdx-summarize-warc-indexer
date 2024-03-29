#!/bin/bash

if [ "$1" == "--help" ]; then
	echo "usage: execute_solr_queries.sh [queryfile]"
	echo "  without arguments it runs all .q files in the current directoty"
	echo "  queryfile : a single json formatted query file to run"
	exit
fi

pushd ${BASH_SOURCE%/*} > /dev/null
if [[ -s "solr.conf" ]]; then
    source "solr.conf" # Optional config
fi
popd > /dev/null
: ${SERVER:="localhost"}
: ${PORT:="8983"}
: ${INDEX:="netarchivebuilder"}

: ${URL:="http://${SERVER}:${PORT}/solr/${INDEX}/query"}

: ${JQFILTER:=".facets.domains.buckets[] | {\"domain\":.val,\"years\":.years[][]}"}
: ${JQCSV:="[.domain, .years.val,.years.count,.years.sizes] | @csv"}
: ${CURL:="curl -s"}

if [ $# -gt 0 ]; then
        echo "${CURL} \"${URL}\" -d @${1} | jq \"${JQFILTER}\"  | jq -r \"${JQCSV}\""
#	${CURL} "${URL}" -d @${1} | jq "${JQFILTER}"  | jq -r "${JQCSV}"
	exit
fi

for f in *.q
do
	OUTF="${f:6:${#f}-8}-result.csv"
	D=`date -Is`
	echo "$D - running ${f} into ${OUTF}"
	${CURL} "${URL}" -d @${f} | jq "${JQFILTER}"  | jq -r "${JQCSV}" > "${OUTF}"
done
