{
  "query": "status_code:[200 TO 299] AND record_type:response AND (content_type:font/* OR content_type:application/vnd.ms-fontobject OR content_type:application/font* OR content_type:application/x-font*)",
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
