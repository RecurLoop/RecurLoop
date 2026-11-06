// Markdown is compiled into a small safe block tree, never executable HTML.
let Docs:trim_line = fn (line:u8*) -> u8* {
    while line[0] == 32 || line[0] == 9 || line[0] == 13 { line = &line[1] }
    var size = cast(i64, strlen(line))
    while size > 0 && (line[size - 1] == 32 || line[size - 1] == 9 || line[size - 1] == 13) { size -= 1 }
    line[size] = 0; return line
}
let Docs:heading_level = fn (line:u8*) -> i64 {
    var i = 0
    while line[i] == 35 && i < 7 { i += 1 }
    if i > 0 && i <= 6 && line[i] == 32 { return i }; return 0
}
let Docs:list_prefix = fn (line:u8*) -> i64 {
    if (line[0] == 45 || line[0] == 42 || line[0] == 43) && line[1] == 32 { return 2 }
    var i = 0
    while line[i] >= 48 && line[i] <= 57 { i += 1 }
    if i > 0 && line[i] == 46 && line[i + 1] == 32 { return i + 2 }; return 0
}
let Docs:fence = fn (line:u8*) -> i64 {
    if line[0] != 96 && line[0] != 126 { return 0 }
    var i = 0
    while line[i] == line[0] { i += 1 }; if i >= 3 { return i }; return 0
}
let Docs:rule = fn (line:u8*) -> i64 {
    if line[0] != 45 && line[0] != 42 && line[0] != 95 { return 0 }
    var i = 0
    while line[i] == line[0] { i += 1 }; return i >= 3 && line[i] == 0
}
let Docs:table_separator = fn (line:u8*) -> i64 {
    if !line { return 0 }
    var dashes = 0; var i = 0
    while line[i] != 0 {
        let ch = line[i]
        if ch == 45 { dashes += 1 }
        else if ch != 32 && ch != 9 && ch != 58 && ch != 124 { return 0 }
        i += 1
    }
    return dashes >= 3
}
let Docs:special_line = fn (line:u8*) -> i64 {
    return Docs:empty(line) || Docs:heading_level(line) || Docs:fence(line) || Docs:list_prefix(line) || line[0] == 62 || Docs:rule(line)
}
let Docs:cells = fn (out:LanguageKit:Text*, line:u8*) -> void {
    out.append("[")
    var start = 0; if line[0] == 124 { start = 1 }
    var at = start; var count = 0
    while line[at] != 0 {
        if line[at] == 124 && (at == 0 || line[at - 1] != 92) {
            let cell = LanguageKit:copy_bytes(&line[start], at - start)
            if count { out.append(",") }; Docs:json(out, Docs:trim_line(cell)); free(cell)
            count += 1; start = at + 1
        }; at += 1
    }
    if at > start { let cell = LanguageKit:copy_bytes(&line[start], at - start); if count { out.append(",") }; Docs:json(out, Docs:trim_line(cell)); free(cell) }
    out.append("]")
}
let Docs:slug = fn (text:u8*) -> u8* {
    let out = LanguageKit:Text:new(); defer out.destroy()
    var at = 0; var separator = 0
    while text[at] != 0 {
        let ch = Docs:lower(text[at])
        if (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch >= 128 {
            if separator && out.length { out.append("-") }; separator = 0; out.append_byte(ch)
        } else if ch == 32 || ch == 9 || ch == 45 { separator = 1 }
        at += 1
    }
    if !out.length { out.append("section") }; return out.take()
}
let Docs:blocks = fn (body:u8*, title:u8*, out:LanguageKit:Text*, toc:LanguageKit:Text*) -> i64 {
    let copy = Docs:copy(body)
    if !copy { return 0 }; defer free(copy)
    var count = 1; var at = 0
    while copy[at] != 0 { if copy[at] == 10 { count += 1 }; at += 1 }
    let lines = cast(u8**, calloc(cast(u64, count + 1), sizeof(u8*)))
    if !lines { return 0 }; defer free(cast(u8*, lines))
    lines[0] = copy; var n = 1; at = 0
    while copy[at] != 0 { if copy[at] == 10 { copy[at] = 0; lines[n] = &copy[at + 1]; n += 1 }; at += 1 }
    let used = LanguageKit:Text:new(); defer used.destroy()
    var i = 0; var emitted = 0
    out.append("["); toc.append("[")
    var toc_count = 0
    while i < n {
        let raw = lines[i]
        let line = Docs:trim_line(raw)
        if Docs:empty(line) { i += 1; continue }
        let level = Docs:heading_level(line)
        if level {
            let text = Docs:trim_line(&line[level + 1])
            var size = cast(i64, strlen(text))
            while size > 0 && text[size - 1] == 35 { size -= 1 }; text[size] = 0; Docs:trim_line(text)
            if emitted == 0 && level == 1 && strcmp(text, title) == 0 { i += 1; continue }
            let base = Docs:slug(text)
            var id = Docs:copy(base); var occurrence = 0
            let marker = LanguageKit:Text:new()
            while 1 {
                marker.length = 0; if marker.data { marker.data[0] = 0 }
                marker.append("\n"); marker.append(id); marker.append("\n")
                if !used.data || !strstr(used.data, marker.data) { break }
                occurrence += 1; free(id)
                id = malloc(strlen(base) + 32); snprintf(id, strlen(base) + 32, "%s-%ld", base, occurrence)
            }
            used.append(marker.data); marker.destroy(); free(base)
            if emitted { out.append(",") }
            out.append("{\"type\":\"heading\",\"level\":"); let number = malloc(32); snprintf(number, 32, "%ld", level); out.append(number); free(number)
            out.append(",\"text\":"); Docs:json(out, text); out.append(",\"id\":"); Docs:json(out, id); out.append("}")
            if level > 1 && level < 4 {
                if toc_count { toc.append(",") }; toc.append("{\"id\":"); Docs:json(toc, id); toc.append(",\"text\":"); Docs:json(toc, text)
                if level == 2 { toc.append(",\"level\":2}") } else { toc.append(",\"level\":3}") }; toc_count += 1
            }
            free(id); emitted += 1; i += 1; continue
        }
        if emitted { out.append(",") }; emitted += 1
        let fence = Docs:fence(line)
        if fence {
            let language = Docs:copy(Docs:trim_line(&line[fence])); let marker = line[0]
            let text = LanguageKit:Text:new(); i += 1; var code_lines = 0
            while i < n {
                var test = lines[i]
                while test[0] == 32 || test[0] == 9 { test = &test[1] }
                if test[0] == marker && Docs:fence(test) >= fence { break }
                if code_lines { text.append("\n") }; text.append(lines[i]); code_lines += 1; i += 1
            }
            out.append("{\"type\":\"code\",\"language\":"); Docs:json(out, language); out.append(",\"text\":"); Docs:json(out, text.data); out.append("}")
            text.destroy(); free(language); if i < n { i += 1 }; continue
        }
        if Docs:rule(line) { out.append("{\"type\":\"rule\"}"); i += 1; continue }
        if i + 1 < n && strstr(line, "|") && Docs:table_separator(lines[i + 1]) {
            out.append("{\"type\":\"table\",\"headers\":"); Docs:cells(out, line); out.append(",\"rows\":["); i += 2; var rows = 0
            while i < n && !Docs:empty(lines[i]) && strstr(lines[i], "|") { if rows { out.append(",") }; Docs:cells(out, Docs:trim_line(lines[i])); rows += 1; i += 1 }
            out.append("]}"); continue
        }
        if Docs:list_prefix(line) {
            out.append("{\"type\":\"list\",\"ordered\":")
            if line[0] >= 48 && line[0] <= 57 { out.append("true") } else { out.append("false") }
            out.append(",\"items\":["); var items = 0
            while i < n {
                let item = Docs:trim_line(lines[i]); let prefix = Docs:list_prefix(item)
                if !prefix { break }; if items { out.append(",") }; Docs:json(out, &item[prefix]); items += 1; i += 1
            }; out.append("]}"); continue
        }
        let text = LanguageKit:Text:new()
        if line[0] == 62 {
            out.append("{\"type\":\"quote\",\"text\":")
            var quote_lines = 0
            while i < n {
                let quote = Docs:trim_line(lines[i]); if quote[0] != 62 { break }
                if quote_lines { text.append("\n") }; text.append(Docs:trim_line(&quote[1])); quote_lines += 1; i += 1
            }
        } else {
            out.append("{\"type\":\"paragraph\",\"text\":"); text.append(line); i += 1
            while i < n {
                let next = Docs:trim_line(lines[i])
                if Docs:special_line(next) || (i + 1 < n && strstr(next, "|") && Docs:table_separator(lines[i + 1])) { break }
                text.append("\n"); text.append(next); i += 1
            }
        }
        Docs:json(out, text.data); out.append("}"); text.destroy()
    }
    out.append("]"); toc.append("]"); return 1
}
let Docs:href = fn (out:LanguageKit:Text*, base:u8*, id:u8*) -> void {
    let text = LanguageKit:Text:new(); text.append(base)
    if !Docs:empty(base) && strcmp(base, "doc:") != 0 { text.append("/") }
    text.append(id); Docs:json(out, text.data); text.destroy()
}
// Qualify portable IDs by package; combined catalogs can contain many overview pages.
let Docs:entry_id = fn (entry:Docs:Entry*, base:u8*) -> u8* {
    if strcmp(base, "doc:") != 0 { return Docs:copy(entry.id) }
    let prefix = Docs:page_id(entry.scope)
    let out = LanguageKit:Text:new(); out.append(&prefix[4]); out.append("-"); out.append(entry.id)
    free(prefix); let id = out.take(); out.destroy(); return id
}
let Docs:link = fn (out:LanguageKit:Text*, entry:Docs:Entry*, base:u8*) -> void {
    if !entry { out.append("null"); return }
    let export_id = Docs:entry_id(entry, base); defer free(export_id)
    out.append("{\"id\":"); Docs:json(out, export_id); out.append(",\"key\":"); Docs:json(out, entry.id); out.append(",\"symbol\":"); Docs:json(out, entry.symbol); out.append(",\"title\":"); Docs:json(out, entry.title)
    out.append(",\"href\":"); Docs:href(out, base, export_id); out.append("}")
}
let Docs:source_url = fn (out:LanguageKit:Text*, entry:Docs:Entry*, revision:u8*) -> void {
    if Docs:empty(revision) && !Docs:empty(entry.source_url) { Docs:json(out, entry.source_url); return }
    if Docs:empty(entry.repository) || Docs:empty(entry.source_path) || entry.source_path[0] == 47 { out.append("null"); return }
    let url = LanguageKit:Text:new(); defer url.destroy()
    url.append(entry.repository); url.append("/blob/")
    if Docs:empty(revision) { url.append("main") } else { url.append(revision) }
    url.append("/"); url.append(entry.source_path); Docs:json(out, url.data)
}
let Docs:summary_json = fn (out:LanguageKit:Text*, entry:Docs:Entry*, base:u8*) -> void {
    let export_id = Docs:entry_id(entry, base); defer free(export_id)
    out.append("{\"id\":"); Docs:json(out, export_id); out.append(",\"key\":"); Docs:json(out, entry.id); out.append(",\"symbol\":"); Docs:json(out, entry.symbol); out.append(",\"title\":"); Docs:json(out, entry.title)
    out.append(",\"section\":"); Docs:json(out, entry.section); out.append(",\"scope\":"); Docs:json(out, entry.scope)
    out.append(",\"href\":"); Docs:href(out, base, export_id)
    out.append(",\"source_path\":"); Docs:json(out, entry.source_path); out.append(",\"origin_path\":"); Docs:json(out, entry.origin_path)
    out.append(",\"search_text\":")
    let excerpt = LanguageKit:Text:new(); excerpt.append(entry.title); excerpt.append("\n"); excerpt.append(entry.inline_docs); excerpt.append("\n"); excerpt.append(entry.body)
    if excerpt.length > 240 { var end = 240; while end > 0 && excerpt.data[end] >= 128 && excerpt.data[end] < 192 { end -= 1 }; excerpt.data[end] = 0 }
    Docs:json(out, excerpt.data); excerpt.destroy(); out.append("}")
}
let Docs:page_json = fn (out:LanguageKit:Text*, entry:Docs:Entry*, base:u8*, revision:u8*) -> i64 {
    let export_id = Docs:entry_id(entry, base); defer free(export_id)
    out.append("{\"id\":"); Docs:json(out, export_id); out.append(",\"key\":"); Docs:json(out, entry.id); out.append(",\"symbol\":"); Docs:json(out, entry.symbol); out.append(",\"title\":"); Docs:json(out, entry.title)
    out.append(",\"section\":"); Docs:json(out, entry.section); out.append(",\"scope\":"); Docs:json(out, entry.scope)
    out.append(",\"href\":"); Docs:href(out, base, export_id)
    out.append(",\"source_path\":"); Docs:json(out, entry.source_path); out.append(",\"origin_path\":"); Docs:json(out, entry.origin_path)
    out.append(",\"package_version\":"); Docs:json(out, entry.version)
    out.append(",\"repository_url\":"); Docs:json(out, entry.repository)
    out.append(",\"source_url\":"); Docs:source_url(out, entry, revision)
    out.append(",\"body\":"); Docs:json(out, entry.body); out.append(",\"inline_docs\":"); Docs:json(out, entry.inline_docs)
    let blocks = LanguageKit:Text:new(); let toc = LanguageKit:Text:new()
    let success = Docs:blocks(entry.body, entry.title, blocks, toc)
    out.append(",\"blocks\":"); out.append(blocks.data); out.append(",\"toc\":"); out.append(toc.data)
    blocks.destroy(); toc.destroy()
    out.append(",\"previous\":"); Docs:link(out, entry.previous, base); out.append(",\"next\":"); Docs:link(out, entry.next, base); out.append("}")
    return success
}
let Docs:navigation_json = fn (out:LanguageKit:Text*, store:Docs:Store*, base:u8*) -> void {
    out.append("["); let used = LanguageKit:Text:new(); defer used.destroy()
    var entry = store.first; var count = 0
    while entry {
        let key = LanguageKit:Text:new(); key.append("\n"); key.append(entry.scope); key.append(":"); key.append(entry.section); key.append("\n")
        if !used.data || !strstr(used.data, key.data) {
            used.append(key.data)
            if count { out.append(",") }; count += 1
            out.append("{\"label\":"); Docs:json(out, entry.section); out.append(",\"scope\":"); Docs:json(out, entry.scope)
            out.append(",\"expanded\":")
            if strcmp(entry.section, "API") == 0 { out.append("false") } else { out.append("true") }
            out.append(",\"pages\":["); var page = store.first; var pages = 0
            while page {
                if strcmp(page.section, entry.section) == 0 && strcmp(page.scope, entry.scope) == 0 {
                    if pages { out.append(",") }; Docs:link(out, page, base); pages += 1
                }; page = page.next
            }; out.append("]}")
        }
        key.destroy(); entry = entry.next
    }; out.append("]")
}
let Docs:index_json = fn (out:LanguageKit:Text*, store:Docs:Store*, base:u8*) -> i64 {
    if !Docs:build_index(store) { return 0 }
    out.append("{\"schema_version\":1,\"normalization\":\"ascii-word-prefix-v1\",\"terms\":{")
    var bucket = 0; var words = 0
    while bucket < 4096 {
        var term = store.terms[bucket]
        while term {
            if words { out.append(",") }; Docs:json(out, term.word); out.append(":[")
            var posting = term.first; var count = 0
            while posting {
                if count { out.append(",") }
                if strcmp(base, "site:") == 0 {
                    let path = Docs:join("/docs", posting.entry.scope); Docs:href(out, path, posting.entry.id); free(path)
                } else { let id = Docs:entry_id(posting.entry, base); Docs:json(out, id); free(id) }
                count += 1; posting = posting.next
            }
            out.append("]"); words += 1; term = term.next
        }; bucket += 1
    }
    out.append("}}"); return 1
}
let Docs:as_json = fn (store:Docs:Store*, base:u8*, revision:u8*) -> u8* {
    if !store || store.error || !store.first || !Docs:build_index(store) { return cast(u8*, 0) }
    Docs:sort(store)
    if Docs:empty(revision) { revision = store.revision }
    let out = LanguageKit:Text:new(); defer out.destroy()
    out.append("{\"schema_version\":3,\"package\":{\"name\":"); Docs:json(out, store.name)
    out.append(",\"version\":"); Docs:json(out, store.version)
    if !Docs:empty(store.repository) { out.append(",\"repository_url\":"); Docs:json(out, store.repository) }
    out.append("}")
    if !Docs:empty(revision) { out.append(",\"source_revision\":"); Docs:json(out, revision) }
    out.append(",\"default_page\":"); let default_id = Docs:entry_id(store.first, base); Docs:json(out, default_id); free(default_id)
    out.append(",\"navigation\":"); Docs:navigation_json(out, store, base)
    out.append(",\"pages\":[\n"); var entry = store.first; var count = 0
    while entry { if count { out.append(",\n") }; if !Docs:page_json(out, entry, base, revision) { return cast(u8*, 0) }; count += 1; entry = entry.next }
    out.append("\n],\"search\":[\n"); entry = store.first; count = 0
    while entry { if count { out.append(",\n") }; Docs:summary_json(out, entry, base); count += 1; entry = entry.next }
    out.append("\n],\"index\":"); if !Docs:index_json(out, store, base) { return cast(u8*, 0) }; out.append("}\n"); return out.take()
}
let Docs:export_file = fn (store:Docs:Store*, path:u8*) -> i64 {
    let json = Docs:as_json(store, "doc:", "")
    if !json { return 0 }; defer free(json)
    return Docs:write_file(path, json)
}
