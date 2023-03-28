# Solr Cloud 7 extraction

This README collects notes from performing statistics extraction from the Solr Cloud 7 setup populated by [webarchive-discovery](https://github.com/ukwa/webarchive-discovery) used at the Royal Danish Library. This proved to be tricke due to an internal and non-overridable limit in Solr 7 resulting in timeouts.

Due to a hard timeout of 10 minutes, extraction was bisected both at shard level and at query level. bash snippets were used for this together with the general streaming oriented script `solr_stream_queries.sh`.

For someone else to 

## Initial setup and test

`solr_stream_queries.sh` requires either Solr server oriented arguments or a configuration file. The latter is recommended: Create a file `solr.conf` and state essential information there, e.g.:

```
: ${SERVER:="localhost"}
: ${PORT:="52300"}
: ${INDEX:="ns1"}
```

It can be used directly with 
```
./solr_stream_queries.sh solrq_font.q
```

If the file `font-result.csv` is produced and looks OK, everything is fine and the statistics extraction (at least for `font`) can be done without further tricks. Simply run the `solr_stream_queries.sh` for each `.q` file, then merge the CSVs with

```
java DomainStatJSON.java $(find -maxdepth 1 -iname "*-result.csv") > total.summary
```

The notes below is for setups where timeouts occur and where the overall collection consists of multiple sub-collection. The sections **Bisect 4** and **Bisect 8** are also relevant for setups without sub-collections.

## Extraction

Netarchive Search uses sub-collections named `ns1, ns2... ns143` served by 5 physical machines (25 sub-collections/machine). Normally they are queried using the alias `ns`, but the collections can also be queries individually.

Find out what the highest collection ID is (140 at the time of extraction) and run ~13 parallel jobs on each machine to saturate CPU power.

```
mkdir -p shard_results
for BASE in $(seq 1 2); do seq $BASE 2 140 | xargs -P 0 -I {} bash -c 'INDEX=ns{} OUTPUT_PREFIX=shard_results/{}_ ./solr_stream_queries.sh' ; done
```

Some of these extractions failed due to timeout, so time to handle problems.

For each query and for each sub-collection (aka shard), check if there is an output and if not, create a CSV file of size 0, signalling a need for bisection with the snippets under "Re-running and bisecting":
```
for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for SHARD in $(seq 1 140); do if [[ -z "$(find shard_results -maxdepth 1 -iname "${SHARD}_q_${QT}-result.csv" -o -iname "${SHARD}[a-z]_q_${QT}-result.csv")" ]]; then touch "shard_results/${SHARD}_q_${QT}-result.csv" ; fi ; done ; done
```

Move all successful results with `size > 0` to the folder `done`:

```
mkdir -p done ; for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for SHARD in $(seq 1 140); do if [[ -s shard_results/${SHARD}_q_${QT}-result.csv ]]; then mv "shard_results/${SHARD}_q_${QT}-result.csv" done/ ; fi ; done ; done
```

### Re-running and bisecting


The scripts skips tasks where a result is already present, so rerunning is safe.

In case of timeouts for the full queries, bisection of the exports are a possibility. Large queries such as `http`, `https`, `html` and `total` are prone to timeouts. The snippet below looks for missing results for all queries, then performs bisection into 4 parts for those.

Note: The hash uses base32 encoding with the characters `ABCDEFGHIJKLMNOPQRSTUVWXYZ234567`. Solr sorts those in order `234567ABCDEFGHIJKLMNOPQRSTUVWXYZ`.


#### Bisect 4

```
for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for BISECT in "a#[* TO sha1:C}" "b#[sha1:C TO sha1:K}" "c#[sha1:K TO sha1:S}" "d#[sha1:S TO *]"; do find shard_results/ -size 0 -iname "*q_${QT}-result.csv" | grep -o '[0-9]*' | sort -u | xargs -P 0 -I {} bash -c "FILTER=\"hash:${BISECT:2}\" INDEX=ns{} OUTPUT_PREFIX=shard_results/{}${BISECT:0:1}_ ./solr_stream_queries.sh solrq_${QT}.q" ; done ; done
```

After this, move all full results (all 4 bisections > size 0) to `4`:
```
mkdir -p 4 ; for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for SHARD in $(seq 1 140); do if [[ -s shard_results/${SHARD}a_q_${QT}-result.csv && -s shard_results/${SHARD}b_q_${QT}-result.csv && -s shard_results/${SHARD}c_q_${QT}-result.csv && -s shard_results/${SHARD}d_q_${QT}-result.csv ]]; then mv shard_results/${SHARD}_q_${QT}-result.csv shard_results/${SHARD}[a-d]_q_${QT}-result.csv 4/ ; fi ; done ; done
```

Merge the bisected files into a single file and move that to `done`. This assumes that if one bisection part is there, all 4 bisection parts are there.
```
mkdir -p done ; for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for SHARD in $(seq 1 140); do if [[ -s 4/${SHARD}a_q_${QT}-result.csv ]]; then echo "$QT $SHARD" ; java -Xmx8g DomainStatMerger.java 4/${SHARD}a_q_${QT}-result.csv 4/${SHARD}b_q_${QT}-result.csv 4/${SHARD}c_q_${QT}-result.csv 4/${SHARD}d_q_${QT}-result.csv > 4/${SHARD}_q_${QT}-result.csv ; mv -n 4/${SHARD}_q_${QT}-result.csv done/ ; fi ; done ; done
```

#### Bisect 8

In the case of timeouts exen with bisection, the answer is of course more bisection!

Start by locating problematic bisections (where only some parts were generated) from above:
```
> find shard_results/ -iname "*[a-d]_q_*.csv"
shard_results/93c_q_html-result.csv
shard_results/96d_q_html-result.csv
```
if that looks correct, delete **all** the 4 sections for the problematic bisections:

```
rm $(find shard_results/ -size 0 -iname "*[a-d]_q_*.csv" | sed 's/[a-d]_q_/[a-d]_q_/')
```

then perform a bisection in 8 parts:

```
for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for BISECT in "a#[* TO sha1:6}" "b#[sha1:6 TO sha1:C}" "c#[sha1:C TO sha1:G}" "d#[sha1:G TO sha1:K}" "e#[sha1:K TO sha1:O}" "f#[sha1:O TO sha1:S}" "g#[sha1:S TO sha1:W}" "h#[sha1:W TO *]"; do find shard_results/ -size 0 -iname "*q_${QT}-result.csv" | grep -o '[0-9]*' | sort -u | xargs -P 0 -I {} bash -c "FILTER=\"hash:${BISECT:2}\" INDEX=ns{} OUTPUT_PREFIX=shard_results/{}${BISECT:0:1}_ ./solr_stream_queries.sh solrq_${QT}.q" ; done ; done
```

After this, move all full results (all 8 bisections > size 0) to `8`:
```
mkdir -p 8 ; for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for SHARD in $(seq 1 140); do if [[ -s shard_results/${SHARD}a_q_${QT}-result.csv && -s shard_results/${SHARD}b_q_${QT}-result.csv && -s shard_results/${SHARD}c_q_${QT}-result.csv && -s shard_results/${SHARD}d_q_${QT}-result.csv && -s shard_results/${SHARD}e_q_${QT}-result.csv && -s shard_results/${SHARD}f_q_${QT}-result.csv && -s shard_results/${SHARD}g_q_${QT}-result.csv && -s shard_results/${SHARD}h_q_${QT}-result.csv ]]; then mv shard_results/${SHARD}_q_${QT}-result.csv shard_results/${SHARD}[a-h]_q_${QT}-result.csv 8/ ; fi ; done ; done
```

and merge to done:
```
mkdir -p done ; for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for SHARD in $(seq 1 140); do if [[ -s 8/${SHARD}a_q_${QT}-result.csv ]]; then echo "$QT $SHARD" ; java -Xmx8g DomainStatMerger.java 8/${SHARD}a_q_${QT}-result.csv 8/${SHARD}b_q_${QT}-result.csv 8/${SHARD}c_q_${QT}-result.csv 8/${SHARD}d_q_${QT}-result.csv 8/${SHARD}e_q_${QT}-result.csv 8/${SHARD}f_q_${QT}-result.csv 8/${SHARD}g_q_${QT}-result.csv 8/${SHARD}h_q_${QT}-result.csv > 8/${SHARD}_q_${QT}-result.csv ; mv -n 8/${SHARD}_q_${QT}-result.csv done/ ; fi ; done ; done
```

If anything is still missing, try re-running bisect 8 again and if that fails, break out bisect 16 or the ultimate bisect 32. Left as an exercise to the reader.

Check if anything is missing:
```
for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for SHARD in $(seq 1 140); do if [[ ! -s done/${SHARD}_q_${QT}-result.csv ]]; then echo "$QT $SHARD is missing" ; fi ; done ; done
```

### Hacks

For each query, check if there are any result (including bisected) for all shards:
```
for QT in $(find . -maxdepth 1 -iname "solrq_*.q" | sed 's/.*solrq_\(.*\).q/\1/'); do for SHARD in $(seq 1 140); do if [[ -z "$(find shard_results -maxdepth 1 -iname "${SHARD}_q_${QT}-result.csv" -o -iname "${SHARD}[a-z]_q_${QT}-result.csv")" ]]; then echo "Missing: $QT $SHARD" ; fi ; done ; done
```


## Merging

Merge results of the same type

```
find done/ -iname "*.csv" | sed 's/.*[0-9]*_q_//' | sort -u | while read -r M; do echo "Processing $M" ; java -Xmx4g DomainStatMerger.java done/*_q_$M > total_$M ; done
```

Merge results across types for the big summary

```
java DomainStatJSON.java $(find -maxdepth 1 -iname "total_*.csv") > total.summary
```

## Sanity checking

The sum of the statistics numbers for `http` and `https` should equal those of `total`:

Extract a sample of 1000 entries from the middle of the total summary, then verify that the number of `http+https` entries matches `total` and that the bytes from those entries also matches. Do note that the order of `http`, `https` and `total` matters in the input so if the order is different in the concrete `total.summary`, the snippet below must be adjusted accordingly. Yes, it is a quick hack.

```
head -n $( echo "$(wc -l < total.summary) / 2" | bc ) total.summary | tail -n 1000 > sample1000

cat sample1000 | sed -e 's/\({"[0-9][0-9][0-9]\)/\n\1/g' -e 's/, \("[0-9][0-9][0-9][0-9]"\)/\n{\1/g'  | grep "{" | while read -r LINE; do sed 's/.*n_http":\([0-9]\+\).*n_total":\([0-9]\+\).*n_https":\([0-9]\+\).*/\1+\3-\2/' <<< "$LINE" | bc ; sed 's/.*s_http":\([0-9]\+\).*s_total":\([0-9]\+\).*s_https":\([0-9]\+\).*/\1+\3-\2/' <<< "$LINE" | bc ; done | grep -v '^0$'
```
