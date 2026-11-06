// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:limits = [
    id = phrase { payload = "limits" }
    title = phrase { payload = "Configure request limits and concurrency" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "Start with `Http:Limits:defaults`. Size limits count bytes; fields ending in `_ms` count milliseconds. Configure the record before creating the server. `new_on_with_limits` takes ownership even if server creation fails.

```recurloop
import http
let validate_limits = fn () -> i64 {
    let limits = Http:Limits:defaults()
    if !limits { return 1 }
    defer free(cast(u8*, limits))
    limits.body = 65536
    limits.header_timeout_ms = 2000
    limits.workers = 2
    limits.queue_capacity = 16
    return !limits.valid()
}
assert validate_limits() == 0
```

## Defaults and supported ranges

| Field | Default | Accepted range |
| --- | --- | --- |
| `request_line` | 16384 | 256–1048576 bytes |
| `headers_total` | 65536 | 1024–8388608 bytes |
| `header_count` | 100 | 1–4096 |
| `body` | 1048576 | 0–1073741824 bytes |
| `header_timeout_ms` | 10000 | 100–300000 ms |
| `body_timeout_ms` | 30000 | 100–300000 ms |
| `write_timeout_ms` | 30000 | 100–300000 ms |
| `workers` | 0 | 0–1024; 0 selects automatic sizing |
| `queue_capacity` | 0 | 0–65536; 0 selects automatic sizing |
| `listen_backlog` | 1024 | 1–65535 |
| `chunk_line` | 4096 | 64–65536 bytes |

The declarative `limits` clause uses `header_timeout`, `body_timeout` and `write_timeout`, with units such as `700ms` or `2s`. Sizes accept units such as `64KiB`. The record API instead uses plain integer byte/millisecond fields.

The worker pool and queue bound simultaneous work. A full queue can reject clients with `503`. Multiple handlers may run concurrently; synchronize shared mutable state. A large body allowance multiplied by concurrency can consume substantial memory."
    }
]
