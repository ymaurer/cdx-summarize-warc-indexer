{
  "query": "status_code:[200 TO 299] AND record_type:response AND url:http\\://*",
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
