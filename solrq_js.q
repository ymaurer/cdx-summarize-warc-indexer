{
  "query": "status_code:[200 TO 299] AND record_type:response AND (content_type:application/javascript OR content_type:text/javascript OR content_type:application/x-javascript)",
  "facet": {
    "domains": {
      "type": "terms",
      "field": "domain",
      "limit": 10000000,
      "facet": {
        "years": {
          "type": "terms",
          "field": "crawl_year",
          "facet": {
            "sizes": {
              "type": "func",
              "func": "sum(content_length)",
              "limit": 10000000
            }
          }
        }
      }
    }
  }
}
