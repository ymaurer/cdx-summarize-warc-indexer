#!/bin/bash

#
# Stream-oriented version of execute_solr_queries.sh
#
# Based on a query from a given file, a CSV file is generated with
# domain, year, hit count for domain & year and total bytes for domain & year
#
# This script expects a Solr collection reasonably compatible with
# https://github.com/ukwa/webarchive-discovery
# The field names are configurable, but the index must contain fields for
# domain, year and content-size in bytes.
#
# This script piggy backs on the queries used by the execute_solr_queries.sh,
# using only the 'query' part from the JSON structure.
#
# Solr streaming expressions
# https://solr.apache.org/guide/8_11/streaming-expressions.html
# scales indefinitely with corpus size and should be used for large collections,
# where "large" means "millions of unique domains" and "10+ shards" or something
# to that effect.
#
# Important: Solr streaming requires a Solr running in cloud mode.
#
# Created 2022 by Toke Eskildsen, toes@kb.dk
# License: CC0: https://creativecommons.org/share-your-work/public-domain/cc0/
#

###############################################################################
# CONFIG
###############################################################################

#
# The script can be used as-is by adjusting the relevant parameters below, e.g.
# PORT=8080 INDEX=netarchive ./solr_stream_queries.sh solrq_http.q solrq_https.q
# It can also be configured by copy-pasting relevant ": ${..." lines below to
# a file named "solr.conf" and adjusting to the local setup.
#

pushd ${BASH_SOURCE%/*} > /dev/null
if [[ -s "solr.conf" ]]; then
    source "solr.conf" # Optional config
fi
: ${QFILES:="$@"}
: ${QFILES:=$(find . -iname '*.q')}

: ${PROTOCOL:="http"}
: ${SERVER:="localhost"}
: ${PORT:="8983"}
: ${INDEX:="netarchivebuilder"}

# Solr fields
: ${DOMAIN:="domain"}
: ${YEAR:="crawl_year"}
: ${SIZE_BYTES:="content_length"}

: ${STREAM_URL="${PROTOCOL}://${SERVER}:${PORT}/solr/${INDEX}/stream"}
: ${JQEXP:=".\"result-set\"[][] | [.\"${DOMAIN}\", .\"${YEAR}\", .\"count(*)\", .\"sum(${SIZE_BYTES})\"] | @csv"}

: ${CURL="curl -s"}
popd > /dev/null

usage() {
    echo "Usage: solr_stream_queries.sh [queryfile]"
    echo "  Without arguments it runs all .q files in the current directory"
    echo "  queryfile: one or more json formatted query files to run"
    exit $1
}

check_parameters() {
    if [[ "$QFILES" == "--help" ]]; then
        usage
    fi
    if [[ -z "$QFILES" ]]; then
        >&2 echo "Error: No query files given and none could be located"
        echo "Try running the script from the script folder, where the default query files are located"
        echo ""
        usage 2
    fi
}

################################################################################
# FUNCTIONS
################################################################################

# Generate stats for a given query
# Input: solr_query output_file
query_job() {
    # Escape embedded quotes
    local QUERY="$(sed 's/"/\\"/g' <<< "$1")"
    local OUTPUT="$2"
    local STREAM="expr=\
                    rollup(\
                      search(${INDEX}, q=\"$QUERY\", \
                             sort=\"${DOMAIN} asc, ${YEAR} asc, ${SIZE_BYTES} asc\",\
                             fl=\"${DOMAIN}, ${YEAR}, ${SIZE_BYTES}\",\
                             qt=\"/export\"\
                      ),\
                     over=\"${DOMAIN}, ${YEAR}\",\
                     count(*),\
                     sum(${SIZE_BYTES})\
                   )"

    echo "$(date -Is) - Generating ${OUTPUT} (this will probably take a while)"
    # The grep at the end is a hack to avoid a non-value last line in the CVS due to Solr stream terminator
    ${CURL} "$STREAM_URL" -d "$STREAM" | jq -r "${JQEXP}" | grep -v ,,, > "$OUTPUT"
}

# Extract query from a given file and produce stats from the query
# Input: query_file
file_job() {
    local INPUT="$1"
    local OUTPUT="${INPUT:6:${#INPUT}-8}-result.csv"
    
    if [[ ! -s "$INPUT" ]]; then
        >&2 echo "Error: Query file '$INPUT' could not be read"
        return
    fi

    local QUERY="$(jq -r .query < "$INPUT")"
    if [[ -z "$QUERY" ]]; then
        >&2 echo "Error: Unable to extract query from file '$INPUT'"
        return
    fi

    query_job "$QUERY" "$OUTPUT"
}

# Iterate all query_files and call file_job for each query_file
all_file_jobs() {
    for QFILE in $QFILES; do
        file_job "$QFILE"
    done
}


###############################################################################
# CODE
###############################################################################

check_parameters "$@"

all_file_jobs

echo "$(date -Is) - All done"
