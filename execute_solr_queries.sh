#!/bin/bash

if [ "$1" == "--help" ]; then
	echo "usage: execute_solr_queries.sh [queryfile]"
	echo "  without arguments it runs all .q files in the current directoty"
	echo "  queryfile : a single json formatted query file to run"
	exit
fi

SERVER="localhost"
PORT="8983"
INDEX="netarchivebuilder"
URL="http://${SERVER}:${PORT}/solr/${INDEX}/select"
JQFILTER=".facets.domains.buckets[] | {\"domain\":.val,\"years\":.years[][]}"
JQCSV="[.domain, .years.val,.years.count,.years.sizes] | @csv"
CURL="curl -s"

if [ $# -gt 0 ]; then
	${CURL} "${URL}" -d @${1} | jq "${JQFILTER}"  | jq -r "${JQCSV}"
	exit
fi

for f in *.q
do
	OUTF="${f:6:${#f}-8}-result.csv"
	D=`date -Is`
	echo "$D - running ${f} into ${OUTF}"
	${CURL} "${URL}" -d @${f} | jq "${JQFILTER}"  | jq -r "${JQCSV}" > "${OUTF}"
done
