{
  "query": "status_code:[200 TO 299] AND record_type:response AND (content_type:text/html OR content_type:application/xhtml+xml OR content_type:text/plain)",
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
