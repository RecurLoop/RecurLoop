// Semantic compiler/Host ABI contract used by engine define.
// Physical sizeof/alignof/offsetof values deliberately stay in HostAbi C++; no layout offsets are stored here.
compiler {
  // Source-owned compiler registry topology. Production C++ resolves these
  // objects by semantic role tags and does not know their physical keys.
  language-root "\0compiler-language"
  registry calling-conventions "calling-conventions"
  registry functions "functions"
  registry function-sources "function-sources"
  registry modules "modules"
  registry settings "settings"
  registry module-selections "module-selections"
  registry link-objects "link-objects"
  registry link-archives "link-archives"
  registry link-paths "link-paths"
  registry shared-libraries "shared-libraries"
  registry types "types"
  registry type-ids "by-id"
  registry abi-kinds "abi-kinds"

  // Source-owned slots. The key may change without changing production C++;
  // shadowing the slot preserves the role tag across compiler transactions.
  slot type-next-id "next-id" 1
  slot automatic-modules "automatic-modules" true
  slot embed-language "embed-language" true
  slot selection-generation "selection-generation" 0
  slot link-sequence "link-sequence" 0
  slot link-generation "link-generation" 0
  slot module-entry "module-entry"

  // ABI lowering behavior of type categories is source data, not a C++ setup table.
  abi-kind void void
  abi-kind integer integer
  abi-kind floating floating
  abi-kind pointer pointer
  abi-kind array aggregate
  abi-kind structure aggregate
  abi-kind function pointer

  abi "sysv-amd64"
  abi "microsoft-x64"
  abi "cdecl-x86"
  abi "stdcall-x86"
  abi "fastcall-x86"

  type "void" void
  type "i8" integer signed 8
  type "u8" integer unsigned 8
  type "i16" integer signed 16
  type "u16" integer unsigned 16
  type "i32" integer signed 32
  type "u32" integer unsigned 32
  type "i64" integer signed 64
  type "u64" integer unsigned 64
  type "f32" floating 32
  type "f64" floating 64
  type "u8*" pointer "u8"
  type "u8**" pointer "u8*"
  type "CxxString" host-opaque
  type "BitString" host-structure fields [ "data" "u8*" "bits" "u64" ]
  type "BitString*" pointer "BitString"
  type "PhraseAction" host-structure fields [ "symbol" "u8*" "bytes" "u64" ]
  type "PhraseAction*" pointer "PhraseAction"
  type "CxxByteVector" host-opaque
  type "CxxPhraseVector" host-opaque
  type "CxxNativeSectionVector" host-opaque
  type "CxxTimePoint" host-opaque
  type "CxxExceptionPointer" host-opaque
  type "Appender" host-opaque
  type "Lexicon" host-opaque
  type "JitMemory" host-opaque
  type "Phrase" host-opaque
  type "Draft" host-opaque
  type "SourceBlock" host-opaque
  type "SourceBlock*" pointer "SourceBlock"
  type "ContextMemory" host-structure fields [ "size" "u64" ]
  type "ContextConfigSourceBuffer" host-structure fields [ "size" "u64" ]
  type "ContextConfigSource" host-structure fields [ "buffer" "ContextConfigSourceBuffer" ]
  type "ContextConfigLexicon" host-structure fields [ "memory" "ContextMemory" ]
  type "ContextConfigRuntime" host-structure fields [ "memory" "ContextMemory" ]
  type "ContextConfigWorkspaceKey" host-structure fields [ "memory" "ContextMemory" ]
  type "ContextConfigWorkspaceCode" host-structure fields [ "memory" "ContextMemory" ]
  type "ContextConfigWorkspace" host-structure fields [ "key" "ContextConfigWorkspaceKey" "code" "ContextConfigWorkspaceCode" ]
  type "ContextConfigException" host-structure fields [ "continues" "u8" ]
  type "ContextConfig" host-structure fields [ "source" "ContextConfigSource" "lexicon" "ContextConfigLexicon" "runtime" "ContextConfigRuntime" "workspace" "ContextConfigWorkspace" "exception" "ContextConfigException" ]
  type "ContextArguments" host-structure fields [ "index" "i32" "count" "i32" "values" "u8**" "options" "u8" ]
  type "Phrase*" pointer "Phrase"
  type "ContextExec" host-structure fields [ "status" "i32" "invoked" "Phrase*" "start" "CxxTimePoint" "args" "ContextArguments" "pendingException" "CxxExceptionPointer" "pendingNativeEntry" "u64" "pendingNativeSymbol" "CxxString" ]
  type "ContextIOStreams" host-structure fields [ "in" "u8*" "out" "u8*" "err" "u8*" ]
  type "ContextSourceBuffer" host-structure fields [ "text" "CxxString" "match" "u64" "offset" "u64" "bits" "u64" ]
  type "ContextSource" host-structure fields [ "path" "CxxString" "line" "u64" "position" "u64" "more" "u8" "buffer" "ContextSourceBuffer" ]
  type "ContextWorkspace" host-structure fields [ "key" "Appender" "code" "Appender" "readOnlyData" "CxxByteVector" "data" "CxxByteVector" "bssBytes" "u64" "customSections" "CxxNativeSectionVector" ]
  type "ContextLookup" host-structure fields [ "stack" "CxxPhraseVector" "dictionary" "Phrase" ]
  type "ContextStaging" host-structure fields [ "stack" "CxxPhraseVector" "dictionary" "Phrase" "phrase" "Draft" ]
  type "ContextReference" host-structure fields [ "dictionary" "Phrase" ]
  type "Context" host-structure fields [ "config" "ContextConfig" "exec" "ContextExec" "io" "ContextIOStreams" "source" "ContextSource" "lexicon" "Lexicon" "runtime" "JitMemory" "workspace" "ContextWorkspace" "lookup" "ContextLookup" "staging" "ContextStaging" "reference" "ContextReference" ]
  type "Context*" pointer "Context"
  type "fn(Context*,u8*)->u64 abi sysv-amd64" function
  type "fn(Context*,u8*,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,BitString*)->u64 abi sysv-amd64" function
  type "fn(Context*,BitString*,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u8*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u8*,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,BitString*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,BitString*,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u8*)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u8*,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,BitString*)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,BitString*,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u8*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u8*,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,BitString*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,BitString*,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u8*,u64,u64,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u8*,u64,u64,u64,PhraseAction*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u8*,u64,u64,u64,u64,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u8*,u64,u64,u64,u64,u64,PhraseAction*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,BitString*,u64,u64,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,BitString*,u64,u64,u64,PhraseAction*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,BitString*,u64,u64,u64,u64,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,BitString*,u64,u64,u64,u64,u64,PhraseAction*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u8*,PhraseAction*)->u64 abi sysv-amd64" function
  type "fn(Context*,u8*,PhraseAction*)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,BitString*,PhraseAction*)->u64 abi sysv-amd64" function
  type "fn(Context*,BitString*,PhraseAction*)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u64,PhraseAction*)->u64 abi sysv-amd64" function
  type "fn(Context*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,PhraseAction*)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u64,u8*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*)->u8* abi sysv-amd64" function
  type "fn(Context*)->u64 abi sysv-amd64" function
  type "fn(Context*)->SourceBlock* abi sysv-amd64" function
  type "fn(SourceBlock*)->u8* abi sysv-amd64" function
  type "fn(SourceBlock*)->u64 abi sysv-amd64" function
  type "fn(Context*,SourceBlock*,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,SourceBlock*)->u64 abi sysv-amd64" function
  type "fn(SourceBlock*)->void abi sysv-amd64" function
  type "fn(Context*,u8*,u64,u64,u8*)->u64 abi sysv-amd64" function
  type "fn(Context*,u8*)->u8* abi sysv-amd64" function
  type "fn(Context*,u8*,u64,u64)->u8* abi sysv-amd64" function
  type "fn(Context*,u8*,u64,u64,u8*,u64,u64)->u8* abi sysv-amd64" function
  type "fn(Context*,u8*,u8*,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u8*,u8*)->u64 abi sysv-amd64" function
  type "fn(Context*,u8*,i64)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u64,u64,u64)->u64 abi sysv-amd64" function
  type "fn(Context*,u8*,u8*,u8*)->u64 abi sysv-amd64" function
  type "fn(Context*,u64,u64,u8*)->u64 abi sysv-amd64" function
  type "fn(Context*,u64)->u8* abi sysv-amd64" function
  type "fn(Context*,u8*,u64)->u8* abi sysv-amd64" function
  type "fn(Context*,u8*)->void abi sysv-amd64" function
  type "fn(Context*,u8*,u8*,u64)->u8* abi sysv-amd64" function
  type "fn(Context*,Phrase*)->u64 abi sysv-amd64" function

  extern "Context:phrase_define_data" symbol "Context:phrase_define_data" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "Context:phrase_define_data" symbol "Context:phrase_define_data$root" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "Context:phrase_define_dictionary" symbol "Context:phrase_define_dictionary" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "Context:phrase_define_dictionary" symbol "Context:phrase_define_dictionary$root" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "Context:phrase_define_from" symbol "Context:phrase_define_from" params [ "Context*" "u64" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "Context:phrase_define_from" symbol "Context:phrase_define_from$root" params [ "Context*" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "Context:phrase_find_exact" symbol "Context:phrase_find_exact" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "Context:phrase_find_first" symbol "Context:phrase_find_first" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "Context:phrase_find_longest" symbol "Context:phrase_find_longest" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "Context:source_block_capture" symbol "Context:source_block_capture" params [ "Context*" ] result "SourceBlock*" abi "sysv-amd64" imported
  extern "Context:source_block_execute_current" symbol "Context:source_block_execute_current" params [ "Context*" "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "Context:source_block_execute_scoped" symbol "Context:source_block_execute_scoped" params [ "Context*" "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "Context:source_match_longest" symbol "Context:source_match_longest" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "Context:syntax_match_longest" symbol "Context:syntax_match_longest" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "SourceBlock:body" symbol "SourceBlock:body" params [ "SourceBlock*" ] result "u8*" abi "sysv-amd64" imported
  extern "SourceBlock:header" symbol "SourceBlock:header" params [ "SourceBlock*" ] result "u8*" abi "sysv-amd64" imported
  extern "SourceBlock:header_line" symbol "SourceBlock:header_line" params [ "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "SourceBlock:header_position" symbol "SourceBlock:header_position" params [ "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "SourceBlock:line" symbol "SourceBlock:line" params [ "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "SourceBlock:path" symbol "SourceBlock:path" params [ "SourceBlock*" ] result "u8*" abi "sysv-amd64" imported
  extern "SourceBlock:position" symbol "SourceBlock:position" params [ "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "SourceBlock:release" symbol "SourceBlock:release" params [ "SourceBlock*" ] result "void" abi "sysv-amd64" imported
  extern "context:diagnostic:error" symbol "context:diagnostic:error" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:diagnostic:error:at" symbol "context:diagnostic:error:at" params [ "Context*" "u8*" "u64" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:actions:bind_root" symbol "context:actions:bind-root" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:io:write" symbol "context:io:write" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:memory:allocate" symbol "context:memory:allocate" params [ "Context*" "u64" ] result "u8*" abi "sysv-amd64" imported
  extern "context:memory:reallocate" symbol "context:memory:reallocate" params [ "Context*" "u8*" "u64" ] result "u8*" abi "sysv-amd64" imported
  extern "context:memory:release" symbol "context:memory:release" params [ "Context*" "u8*" ] result "void" abi "sysv-amd64" imported
  extern "context:memory:copy" symbol "context:memory:copy" params [ "Context*" "u8*" "u8*" "u64" ] result "u8*" abi "sysv-amd64" imported
  extern "context:memory:move" symbol "context:memory:move" params [ "Context*" "u8*" "u8*" "u64" ] result "u8*" abi "sysv-amd64" imported
  extern "context:workspace:key:append_byte" symbol "context:workspace:key:append-byte" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:workspace:code:append_byte" symbol "context:workspace:code:append-byte" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:expression:boolean:at" symbol "context:expression:boolean:at" params [ "Context*" "u8*" "u8*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:expression:format" symbol "context:expression:format$text" params [ "Context*" "u8*" ] result "u8*" abi "sysv-amd64" imported
  extern "context:expression:format" symbol "context:expression:format$slice" params [ "Context*" "u8*" "u64" "u64" ] result "u8*" abi "sysv-amd64" imported
  extern "context:expression:format:at" symbol "context:expression:format:at" params [ "Context*" "u8*" "u64" "u64" "u8*" "u64" "u64" ] result "u8*" abi "sysv-amd64" imported
  extern "context:function:address" symbol "context:function:address" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:function:compile" symbol "context:function:compile" params [ "Context*" "u8*" "u8*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:call" symbol "context:phrase:call" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:child" symbol "context:phrase:child" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:child:first" symbol "context:phrase:child:first" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:child:next" symbol "context:phrase:child:next" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:data" symbol "context:phrase:data$text" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:data" symbol "context:phrase:data" params [ "Context*" "u64" "u8*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$prototype-bits" params [ "Context*" "BitString*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$prototype-bit-slice" params [ "Context*" "BitString*" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$full-bits-action" params [ "Context*" "u64" "BitString*" "u64" "u64" "u64" "PhraseAction*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$full-bits" params [ "Context*" "u64" "BitString*" "u64" "u64" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$full-bit-slice-action" params [ "Context*" "u64" "BitString*" "u64" "u64" "u64" "u64" "u64" "PhraseAction*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$full-bit-slice" params [ "Context*" "u64" "BitString*" "u64" "u64" "u64" "u64" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$full-text-action" params [ "Context*" "u64" "u8*" "u64" "u64" "u64" "PhraseAction*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$full-text" params [ "Context*" "u64" "u8*" "u64" "u64" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$full-action" params [ "Context*" "u64" "u8*" "u64" "u64" "u64" "u64" "u64" "PhraseAction*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$full" params [ "Context*" "u64" "u8*" "u64" "u64" "u64" "u64" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$prototype-text" params [ "Context*" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define" symbol "context:phrase:define$prototype" params [ "Context*" "u8*" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:action" symbol "context:phrase:define:action$root-bits" params [ "Context*" "BitString*" "PhraseAction*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:action" symbol "context:phrase:define:action$bits" params [ "Context*" "u64" "BitString*" "PhraseAction*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:action" symbol "context:phrase:define:action$text" params [ "Context*" "u64" "u8*" "PhraseAction*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:action" symbol "context:phrase:define:action$root-text" params [ "Context*" "u8*" "PhraseAction*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:alias" symbol "context:phrase:define:alias$text" params [ "Context*" "u64" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:alias" symbol "context:phrase:define:alias$root-text" params [ "Context*" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:data" symbol "context:phrase:define:data$root-bits" params [ "Context*" "BitString*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:data" symbol "context:phrase:define:data$bits" params [ "Context*" "u64" "BitString*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:data" symbol "context:phrase:define:data$text" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:data" symbol "context:phrase:define:data$root-text" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:dictionary" symbol "context:phrase:define:dictionary$root-bits" params [ "Context*" "BitString*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:dictionary" symbol "context:phrase:define:dictionary$bits" params [ "Context*" "u64" "BitString*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:dictionary" symbol "context:phrase:define:dictionary$text" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:dictionary" symbol "context:phrase:define:dictionary$root-text" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:from" symbol "context:phrase:define:from$root-bits" params [ "Context*" "BitString*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:from" symbol "context:phrase:define:from$bits" params [ "Context*" "u64" "BitString*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:from" symbol "context:phrase:define:from$text" params [ "Context*" "u64" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:from" symbol "context:phrase:define:from$root-text" params [ "Context*" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:successor" symbol "context:phrase:define:successor$root-bits" params [ "Context*" "BitString*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:successor" symbol "context:phrase:define:successor$bits" params [ "Context*" "u64" "BitString*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:successor" symbol "context:phrase:define:successor$text" params [ "Context*" "u64" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:define:successor" symbol "context:phrase:define:successor$root-text" params [ "Context*" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:dispatch" symbol "context:phrase:dispatch" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:elaborate" symbol "context:phrase:elaborate" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find" symbol "context:phrase:find$root-bits" params [ "Context*" "BitString*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find" symbol "context:phrase:find$root-bit-slice" params [ "Context*" "BitString*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find" symbol "context:phrase:find$in-bits" params [ "Context*" "u64" "BitString*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find" symbol "context:phrase:find$in-bit-slice" params [ "Context*" "u64" "BitString*" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find" symbol "context:phrase:find$in-text" params [ "Context*" "u64" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find" symbol "context:phrase:find$in" params [ "Context*" "u64" "u8*" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find" symbol "context:phrase:find$root-text" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find" symbol "context:phrase:find$root" params [ "Context*" "u8*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:exact" symbol "context:phrase:find:exact$bits" params [ "Context*" "u64" "BitString*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:exact" symbol "context:phrase:find:exact$bit-slice" params [ "Context*" "u64" "BitString*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:exact" symbol "context:phrase:find:exact$text" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:exact" symbol "context:phrase:find:exact$slice" params [ "Context*" "u64" "u8*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:first" symbol "context:phrase:find:first$bits" params [ "Context*" "u64" "BitString*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:first" symbol "context:phrase:find:first$bit-slice" params [ "Context*" "u64" "BitString*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:first" symbol "context:phrase:find:first$text" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:first" symbol "context:phrase:find:first$slice" params [ "Context*" "u64" "u8*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:longest" symbol "context:phrase:find:longest$bits" params [ "Context*" "u64" "BitString*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:longest" symbol "context:phrase:find:longest$bit-slice" params [ "Context*" "u64" "BitString*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:longest" symbol "context:phrase:find:longest$text" params [ "Context*" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:find:longest" symbol "context:phrase:find:longest$slice" params [ "Context*" "u64" "u8*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:flags" symbol "context:phrase:flags" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:get" symbol "context:phrase:get" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:invoke" symbol "context:phrase:invoke" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:key" symbol "context:phrase:key" params [ "Context*" "u64" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:parent" symbol "context:phrase:parent" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:image:native" symbol "context:phrase:image:native" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:image:reference" symbol "context:phrase:image:reference" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:payload:bytes" symbol "context:phrase:payload:bytes" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:prototype" symbol "context:phrase:prototype" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:read" symbol "context:phrase:read" params [ "Context*" "u64" "u64" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:address" symbol "context:phrase:address" params [ "Context*" "Phrase*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set" symbol "context:phrase:set$action" params [ "Context*" "u64" "u64" "PhraseAction*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set" symbol "context:phrase:set$value" params [ "Context*" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:action" symbol "context:phrase:set:action$inline" params [ "Context*" "u64" "PhraseAction*" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:action" symbol "context:phrase:set:action$value" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:permanent" symbol "context:phrase:set:permanent" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:prototype" symbol "context:phrase:set:prototype" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:rewrite" symbol "context:phrase:set:rewrite" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:serializable" symbol "context:phrase:set:serializable$enabled" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:serializable" symbol "context:phrase:set:serializable" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:successor" symbol "context:phrase:set:successor" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:transient" symbol "context:phrase:set:transient" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:set:type" symbol "context:phrase:set:type" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:successor" symbol "context:phrase:successor" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:phrase:type" symbol "context:phrase:type" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:advance" symbol "context:source:advance" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:block:body" symbol "context:source:block:body" params [ "SourceBlock*" ] result "u8*" abi "sysv-amd64" imported
  extern "context:source:block:capture" symbol "context:source:block:capture" params [ "Context*" ] result "SourceBlock*" abi "sysv-amd64" imported
  extern "context:source:block:execute" symbol "context:source:block:execute" params [ "Context*" "SourceBlock*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:block:execute:current" symbol "context:source:block:execute:current" params [ "Context*" "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:block:execute:scoped" symbol "context:source:block:execute:scoped" params [ "Context*" "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:block:header" symbol "context:source:block:header" params [ "SourceBlock*" ] result "u8*" abi "sysv-amd64" imported
  extern "context:source:block:header:line" symbol "context:source:block:header:line" params [ "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:block:header:position" symbol "context:source:block:header:position" params [ "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:block:line" symbol "context:source:block:line" params [ "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:block:path" symbol "context:source:block:path" params [ "SourceBlock*" ] result "u8*" abi "sysv-amd64" imported
  extern "context:source:block:position" symbol "context:source:block:position" params [ "SourceBlock*" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:block:release" symbol "context:source:block:release" params [ "SourceBlock*" ] result "void" abi "sysv-amd64" imported
  extern "context:source:bytes" symbol "context:source:bytes" params [ "Context*" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:consume" symbol "context:source:consume" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:data" symbol "context:source:data" params [ "Context*" ] result "u8*" abi "sysv-amd64" imported
  extern "context:source:ensure" symbol "context:source:ensure" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:hook" symbol "context:source:hook" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:match" symbol "context:source:match" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:match:exact" symbol "context:source:match:exact" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:match:first" symbol "context:source:match:first" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:match:longest" symbol "context:source:match:longest" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:peek" symbol "context:source:peek" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:probe:longest" symbol "context:source:probe:longest" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:refill" symbol "context:source:refill" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:source:root" symbol "context:source:root" params [ "Context*" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:active" symbol "context:syntax:active" params [ "Context*" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:advance" symbol "context:syntax:advance" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:bytes" symbol "context:syntax:bytes" params [ "Context*" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:copy" symbol "context:syntax:copy" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:data" symbol "context:syntax:data" params [ "Context*" ] result "u8*" abi "sysv-amd64" imported
  extern "context:syntax:dictionary" symbol "context:syntax:dictionary" params [ "Context*" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:elaborate" symbol "context:syntax:elaborate" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:emit" symbol "context:syntax:emit$text" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:emit" symbol "context:syntax:emit" params [ "Context*" "u8*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:line" symbol "context:syntax:line" params [ "Context*" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:match" symbol "context:syntax:match" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:match:exact" symbol "context:syntax:match:exact" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:match:first" symbol "context:syntax:match:first" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:match:longest" symbol "context:syntax:match:longest" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:syntax:path" symbol "context:syntax:path" params [ "Context*" ] result "u8*" abi "sysv-amd64" imported
  extern "context:syntax:position" symbol "context:syntax:position" params [ "Context*" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:alignment" symbol "context:type:alignment" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:array" symbol "context:type:array" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:element" symbol "context:type:element" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:element:count" symbol "context:type:element:count" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:find" symbol "context:type:find" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:floating" symbol "context:type:floating" params [ "Context*" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:function" symbol "context:type:function" params [ "Context*" "u64" "u64" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:function:fixed" symbol "context:type:function:fixed" params [ "Context*" "u64" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:function:variadic" symbol "context:type:function:variadic" params [ "Context*" "u64" "u64" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:get" symbol "context:type:get" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:integer" symbol "context:type:integer" params [ "Context*" "u8*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:integer:signed" symbol "context:type:integer:signed" params [ "Context*" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:integer:unsigned" symbol "context:type:integer:unsigned" params [ "Context*" "u8*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:kind" symbol "context:type:kind" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:pointer" symbol "context:type:pointer" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:pointer:depth" symbol "context:type:pointer:depth" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:result" symbol "context:type:result" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:signed" symbol "context:type:signed" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:size" symbol "context:type:size" params [ "Context*" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:structure:complete" symbol "context:type:structure:complete" params [ "Context*" "u64" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:structure:complete:aligned" symbol "context:type:structure:complete:aligned" params [ "Context*" "u64" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:structure:complete:natural" symbol "context:type:structure:complete:natural" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:structure:complete:packed" symbol "context:type:structure:complete:packed" params [ "Context*" "u64" "u64" ] result "u64" abi "sysv-amd64" imported
  extern "context:type:structure:declare" symbol "context:type:structure:declare" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:value:assign:integer" symbol "context:value:assign:integer" params [ "Context*" "u8*" "i64" ] result "u64" abi "sysv-amd64" imported
  extern "context:value:assign:text" symbol "context:value:assign:text" params [ "Context*" "u8*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:value:contains" symbol "context:value:contains" params [ "Context*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:value:define:integer" symbol "context:value:define:integer" params [ "Context*" "u8*" "i64" ] result "u64" abi "sysv-amd64" imported
  extern "context:value:define:text" symbol "context:value:define:text" params [ "Context*" "u8*" "u8*" ] result "u64" abi "sysv-amd64" imported
  extern "context:value:format" symbol "context:value:format" params [ "Context*" "u8*" ] result "u8*" abi "sysv-amd64" imported

  linker-path "."
  linker-path "/lib"
  linker-path "/lib/x86_64-linux-gnu"
  linker-path "/lib64"
  linker-path "/usr/lib"
  linker-path "/usr/lib/x86_64-linux-gnu"
  linker-path "/usr/lib64"
  linker-path "/usr/local/lib"
}
