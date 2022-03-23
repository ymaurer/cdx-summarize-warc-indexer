# CDX-summarize-warc-indexer

A collection of SOLR queries to reproduce similar numbers to the ones produced by [cdx-summarize](https://github.com/ymaurer/cdx-summarize), but using a SOLR index that has been constructed using [warc-indexer](https://github.com/ukwa/webarchive-discovery/tree/master/warc-indexer) from the [UKWA webarchive-discovery](https://github.com/ukwa/webarchive-discovery) and using [V6 schema.xml](https://github.com/ukwa/webarchive-discovery/blob/master/warc-indexer/src/main/solr/solr/discovery/conf/schema.xml) or [V7 schema.xml](https://github.com/ukwa/webarchive-discovery/blob/master/warc-indexer/src/main/solr/solr7/discovery/conf/schema.xml).

## Usage of execute_solr_queries.sh

```
execute_solr_queries.sh --help

usage: execute_solr_queries.sh [queryfile]
  without arguments it runs all .q files in the current directoty
  queryfile : a single json formatted query file to run
```

## Constructing the .summary file
The output of the bash script is a collection of CSV files which do need to be combined into a single .summary file so that they are completely compatible with cdx-summarize. This remains a todo.

## Performance
This has only been tested on a small installation of the SOLR backend of a SOLRWayback. The queries can probably be optimized.

## MIME-Types
The same rationale to mime-type simplification as in [cdx-summarize](https://github.com/ymaurer/cdx-summarize#mime-type-short-intro) has been used, but here based off the mime-type that has been determined by warc-indexer (the field content_type) is used. In order to be completely the same as cdx-summarize, which operates on CDX(J) files and where the mime-type is the one reported by the server, you would need to use the field content_type_served. This is not done, since we do have the extra information reported by tika, droid et al. and it is more precise and more correct.

## Limit
Currently the scripts place a limit of 10 million second-level domains on the query. This may or may not be enough depending on the size of the web archive.

## Domains
The "domain" field in the warc-indexer, as used in the SOLRWayback, holds the private domain name as determined by having one more hierarchical level than the public suffix, as determined by Mozilla's [publicsuffix.org](https://publicsuffix.org/) list. This means that the subdomains of e.g. ".ac.uk" and ".co.uk" are separated into different "domain" values. This is currently not the same as for cdx-summarize which only takes the second-level domain.
