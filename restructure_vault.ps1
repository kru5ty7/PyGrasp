# ============================================================
# VAULT RESTRUCTURE SCRIPT
# Aligns file locations and title numbers with updated TOPIC_MANIFEST.md
# ============================================================

$base = "f:\workspace\PyGrasp"
Set-Location $base

function GitMv($from, $to) {
    & git mv $from $to
    if (-not $?) { Write-Error "git mv failed: $from -> $to"; exit 1 }
}

function UpdateTitle($path, $newTitle) {
    $content = Get-Content $path -Raw
    $content = $content -replace "(?m)^title: .+", "title: $newTitle"
    Set-Content $path $content -NoNewline
}

Write-Host "=== STEP 1: 01_Core - move 02_Memory + everything-is-an-object into 00_How_Python_Runs ===" -ForegroundColor Cyan

GitMv "content/01_Core/01_Object_System/everything-is-an-object.md"   "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/stack-vs-heap.md"                    "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/object-header.md"                    "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/id-and-memory-address.md"            "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/python-memory-model.md"              "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/reference-counting.md"               "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/cyclic-references.md"                "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/garbage-collection.md"               "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/memory-allocator.md"                 "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/interning.md"                        "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/small-integer-cache.md"              "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/mutability.md"                       "content/01_Core/00_How_Python_Runs/"
GitMv "content/01_Core/02_Memory/copy-vs-deepcopy.md"                 "content/01_Core/00_How_Python_Runs/"

Write-Host "=== STEP 2: 01_Core - rename subfolders ===" -ForegroundColor Cyan

GitMv "content/01_Core/03_Scopes_and_Functions"   "content/01_Core/02_Scopes_Functions"
GitMv "content/01_Core/04_Iterators_and_Generators" "content/01_Core/03_Iterators_Generators"
GitMv "content/01_Core/07_Type_System"            "content/01_Core/04_Types_Typing"
GitMv "content/01_Core/05_Exceptions"             "content/01_Core/05_Error_Handling"
GitMv "content/01_Core/06_Modules_and_Packages"   "content/01_Core/06_Modules_Packages"

Write-Host "=== STEP 3: 02_Concurrency - move files + rename subfolders ===" -ForegroundColor Cyan

# Move thread-vs-process from Threading to Processes
GitMv "content/02_Concurrency/01_Threading/thread-vs-process.md"         "content/02_Concurrency/02_Multiprocessing/"
# Move concurrent-futures from Executors to Processes
GitMv "content/02_Concurrency/04_Executors/concurrent-futures.md"        "content/02_Concurrency/02_Multiprocessing/"
# Rename folders
GitMv "content/02_Concurrency/01_Threading"    "content/02_Concurrency/01_Threads"
GitMv "content/02_Concurrency/02_Multiprocessing" "content/02_Concurrency/02_Processes"
GitMv "content/02_Concurrency/03_Asyncio"      "content/02_Concurrency/03_Async"

Write-Host "=== STEP 4: 03_Web - rename HTTP + Web Interface folders ===" -ForegroundColor Cyan

GitMv "content/03_Web/00_HTTP_and_Protocols"  "content/03_Web/00_HTTP_Protocols"
GitMv "content/03_Web/01_Python_Web_Interface" "content/03_Web/01_Web_Interface"

Write-Host "=== STEP 5: 03_Web - create 04_FastAPI, merge pydantic + old FastAPI group + http-request-lifecycle + fastapi.md ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Force "content/03_Web/04_FastAPI" | Out-Null

# From 02_Pydantic_and_Validation
GitMv "content/03_Web/02_Pydantic_and_Validation/pydantic.md"            "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/02_Pydantic_and_Validation/pydantic-validators.md" "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/02_Pydantic_and_Validation/pydantic-settings.md"   "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/02_Pydantic_and_Validation/json-schema.md"         "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/02_Pydantic_and_Validation/serialization.md"       "content/03_Web/04_FastAPI/"

# fastapi.md from Web Interface
GitMv "content/03_Web/01_Web_Interface/fastapi.md"                       "content/03_Web/04_FastAPI/"

# From 03_FastAPI
GitMv "content/03_Web/03_FastAPI/dependency-injection.md"                "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/path-and-query-params.md"               "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/request-body.md"                        "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/response-model.md"                      "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/fastapi-dependencies.md"                "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/fastapi-middleware.md"                  "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/cors.md"                                "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/background-tasks.md"                    "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/fastapi-websockets.md"                  "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/fastapi-routers.md"                     "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/fastapi-lifespan.md"                    "content/03_Web/04_FastAPI/"
GitMv "content/03_Web/03_FastAPI/openapi.md"                             "content/03_Web/04_FastAPI/"

# http-request-lifecycle from HTTP group
GitMv "content/03_Web/00_HTTP_Protocols/http-request-lifecycle.md"       "content/03_Web/04_FastAPI/"

Write-Host "=== STEP 6: create 04_Web_Ecosystem, move auth/db/testing ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Force "content/04_Web_Ecosystem/00_Databases"   | Out-Null
New-Item -ItemType Directory -Force "content/04_Web_Ecosystem/01_Task_Queues" | Out-Null
New-Item -ItemType Directory -Force "content/04_Web_Ecosystem/02_Auth_Security" | Out-Null
New-Item -ItemType Directory -Force "content/04_Web_Ecosystem/03_Testing"     | Out-Null
New-Item -ItemType Directory -Force "content/04_Web_Ecosystem/04_HTTP_Clients"| Out-Null

Get-ChildItem "content/03_Web/05_Database/*.md"        | ForEach-Object { GitMv $_.FullName.Replace($base+"\","").Replace("\","/") "content/04_Web_Ecosystem/00_Databases/" }
Get-ChildItem "content/03_Web/04_Auth_and_Security/*.md" | ForEach-Object { GitMv $_.FullName.Replace($base+"\","").Replace("\","/") "content/04_Web_Ecosystem/02_Auth_Security/" }
Get-ChildItem "content/03_Web/06_Testing/*.md"         | ForEach-Object { GitMv $_.FullName.Replace($base+"\","").Replace("\","/") "content/04_Web_Ecosystem/03_Testing/" }

Write-Host "=== STEP 7: create 06_AI_Engineering, move 04_AI contents + internal restructure ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Force "content/06_AI_Engineering/00_LLM_Foundations"    | Out-Null
New-Item -ItemType Directory -Force "content/06_AI_Engineering/01_Embeddings_Search"  | Out-Null
New-Item -ItemType Directory -Force "content/06_AI_Engineering/02_RAG"                | Out-Null
New-Item -ItemType Directory -Force "content/06_AI_Engineering/03_LangChain"          | Out-Null
New-Item -ItemType Directory -Force "content/06_AI_Engineering/04_LangGraph"          | Out-Null
New-Item -ItemType Directory -Force "content/06_AI_Engineering/05_Agents"             | Out-Null
New-Item -ItemType Directory -Force "content/06_AI_Engineering/06_MLOps"              | Out-Null

Get-ChildItem "content/04_AI/00_LLM_Foundations/*.md"  | ForEach-Object { GitMv $_.FullName.Replace($base+"\","").Replace("\","/") "content/06_AI_Engineering/00_LLM_Foundations/" }
Get-ChildItem "content/04_AI/01_Embeddings_and_Search/*.md" | ForEach-Object { GitMv $_.FullName.Replace($base+"\","").Replace("\","/") "content/06_AI_Engineering/01_Embeddings_Search/" }

# Move reranking + hybrid-search from RAG → Embeddings_Search
GitMv "content/04_AI/02_RAG/reranking.md"    "content/06_AI_Engineering/01_Embeddings_Search/"
GitMv "content/04_AI/02_RAG/hybrid-search.md" "content/06_AI_Engineering/01_Embeddings_Search/"

# Remaining RAG files
GitMv "content/04_AI/02_RAG/rag.md"                 "content/06_AI_Engineering/02_RAG/"
GitMv "content/04_AI/02_RAG/rag-pipeline.md"        "content/06_AI_Engineering/02_RAG/"
GitMv "content/04_AI/02_RAG/retrieval-strategies.md" "content/06_AI_Engineering/02_RAG/"

Get-ChildItem "content/04_AI/03_LangChain/*.md" | ForEach-Object { GitMv $_.FullName.Replace($base+"\","").Replace("\","/") "content/06_AI_Engineering/03_LangChain/" }
Get-ChildItem "content/04_AI/04_LangGraph/*.md" | ForEach-Object { GitMv $_.FullName.Replace($base+"\","").Replace("\","/") "content/06_AI_Engineering/04_LangGraph/" }
Get-ChildItem "content/04_AI/05_Agents/*.md"    | ForEach-Object { GitMv $_.FullName.Replace($base+"\","").Replace("\","/") "content/06_AI_Engineering/05_Agents/" }

Write-Host "=== STEP 8: Update all title numbers ===" -ForegroundColor Cyan

# ---- 00_How_Python_Runs (25 notes, fix swapped frame-object/call-stack + renumber incoming memory files) ----
$r = "content/01_Core/00_How_Python_Runs"
UpdateTitle "$r/frame-object.md"           "11 - The Frame Object"
UpdateTitle "$r/call-stack.md"             "12 - The Call Stack"
UpdateTitle "$r/stack-vs-heap.md"          "13 - Stack vs Heap"
UpdateTitle "$r/everything-is-an-object.md" "14 - Everything is an Object"
UpdateTitle "$r/object-header.md"          "15 - Python Object Header"
UpdateTitle "$r/id-and-memory-address.md"  "16 - id() and Memory Addresses"
UpdateTitle "$r/python-memory-model.md"    "17 - Python's Memory Model"
UpdateTitle "$r/reference-counting.md"     "18 - Reference Counting"
UpdateTitle "$r/cyclic-references.md"      "19 - Cyclic References"
UpdateTitle "$r/garbage-collection.md"     "20 - Garbage Collection"
UpdateTitle "$r/memory-allocator.md"       "21 - Python's Memory Allocator"
UpdateTitle "$r/interning.md"              "22 - Object Interning"
UpdateTitle "$r/small-integer-cache.md"    "23 - Small Integer Cache"
UpdateTitle "$r/mutability.md"             "24 - Mutability vs Immutability"
UpdateTitle "$r/copy-vs-deepcopy.md"       "25 - Shallow Copy vs Deep Copy"

# ---- 01_Object_System (15 notes, everything-is-an-object removed, renumber per manifest order) ----
$r = "content/01_Core/01_Object_System"
UpdateTitle "$r/python-data-model.md"         "01 - The Python Data Model"
UpdateTitle "$r/dunder-methods.md"            "02 - Dunder Methods"
UpdateTitle "$r/type-and-object.md"           "03 - type and object"
UpdateTitle "$r/metaclasses.md"               "04 - Metaclasses"
UpdateTitle "$r/class-creation.md"            "05 - How Classes Are Created"
UpdateTitle "$r/mro.md"                       "06 - Method Resolution Order (MRO)"
UpdateTitle "$r/multiple-inheritance.md"      "07 - Multiple Inheritance"
UpdateTitle "$r/abstract-base-classes.md"     "08 - Abstract Base Classes"
UpdateTitle "$r/protocols.md"                 "09 - Protocols and Structural Subtyping"
UpdateTitle "$r/descriptors.md"               "10 - Descriptors"
UpdateTitle "$r/properties.md"                "11 - Properties"
UpdateTitle "$r/slots.md"                     "12 - __slots__"
UpdateTitle "$r/classmethod-staticmethod.md"  "13 - classmethod vs staticmethod"
UpdateTitle "$r/dataclasses.md"               "14 - Dataclasses"
UpdateTitle "$r/enums.md"                     "15 - Enums"

# ---- 01_Threads (remove thread-vs-process, renumber per manifest order) ----
$r = "content/02_Concurrency/01_Threads"
UpdateTitle "$r/threads.md"              "01 - Threads in Python"
UpdateTitle "$r/thread-lifecycle.md"     "02 - Thread Lifecycle"
UpdateTitle "$r/race-conditions.md"      "03 - Race Conditions"
UpdateTitle "$r/locks.md"                "04 - Locks"
UpdateTitle "$r/deadlocks.md"            "05 - Deadlocks"
UpdateTitle "$r/semaphores.md"           "06 - Semaphores"
UpdateTitle "$r/thread-safe-queues.md"   "07 - Thread-Safe Queues"
UpdateTitle "$r/thread-pool-executor.md" "08 - ThreadPoolExecutor"
UpdateTitle "$r/daemon-threads.md"       "09 - Daemon Threads"

# ---- 02_Processes (add thread-vs-process + concurrent-futures) ----
$r = "content/02_Concurrency/02_Processes"
UpdateTitle "$r/processes.md"                    "01 - Processes in Python"
UpdateTitle "$r/multiprocessing-module.md"       "02 - The multiprocessing Module"
UpdateTitle "$r/process-pool.md"                 "03 - Process Pool"
UpdateTitle "$r/inter-process-communication.md"  "04 - Inter-Process Communication"
UpdateTitle "$r/shared-memory.md"                "05 - Shared Memory"
UpdateTitle "$r/thread-vs-process.md"            "06 - Threads vs Processes"
UpdateTitle "$r/concurrent-futures.md"           "07 - concurrent.futures"

# ---- 03_Async (reorder per manifest) ----
$r = "content/02_Concurrency/03_Async"
UpdateTitle "$r/async-context-managers.md"  "08 - Async Context Managers"
UpdateTitle "$r/async-generators.md"        "09 - Async Generators"
UpdateTitle "$r/async-iterators.md"         "10 - Async Iterators"
UpdateTitle "$r/asyncio-queues.md"          "11 - Asyncio Queues"
UpdateTitle "$r/asyncio-locks.md"           "12 - Asyncio Locks"
UpdateTitle "$r/running-sync-in-async.md"   "13 - Running Sync Code in Async"
UpdateTitle "$r/aiohttp.md"                 "14 - aiohttp"
UpdateTitle "$r/async-patterns.md"          "15 - Async Patterns"

# ---- 04_FastAPI (merged group, 19 notes) ----
$r = "content/03_Web/04_FastAPI"
# pydantic group 01-05 unchanged
UpdateTitle "$r/dependency-injection.md"     "06 - Dependency Injection"
UpdateTitle "$r/fastapi.md"                  "07 - FastAPI"
UpdateTitle "$r/path-and-query-params.md"    "08 - Path and Query Parameters"
UpdateTitle "$r/request-body.md"             "09 - Request Body"
UpdateTitle "$r/response-model.md"           "10 - Response Models"
UpdateTitle "$r/fastapi-dependencies.md"     "11 - FastAPI Dependencies"
UpdateTitle "$r/fastapi-middleware.md"       "12 - Middleware in FastAPI"
UpdateTitle "$r/cors.md"                     "13 - CORS"
UpdateTitle "$r/background-tasks.md"         "14 - Background Tasks"
UpdateTitle "$r/fastapi-websockets.md"       "15 - WebSockets in FastAPI"
UpdateTitle "$r/openapi.md"                  "16 - OpenAPI"
UpdateTitle "$r/http-request-lifecycle.md"   "17 - HTTP Request Lifecycle in FastAPI"
UpdateTitle "$r/fastapi-routers.md"          "18 - Routers in FastAPI"
UpdateTitle "$r/fastapi-lifespan.md"         "19 - Lifespan Events"

# ---- 06_AI_Engineering/01_Embeddings_Search (reorder + add reranking/hybrid-search) ----
$r = "content/06_AI_Engineering/01_Embeddings_Search"
UpdateTitle "$r/embeddings.md"          "01 - Embeddings"
UpdateTitle "$r/vector-search.md"       "02 - Vector Search"
UpdateTitle "$r/vector-databases.md"    "03 - Vector Databases"
UpdateTitle "$r/similarity-metrics.md"  "04 - Similarity Metrics"
UpdateTitle "$r/chunking-strategies.md" "05 - Chunking Strategies"
UpdateTitle "$r/reranking.md"           "06 - Reranking"
UpdateTitle "$r/hybrid-search.md"       "07 - Hybrid Search"

Write-Host "=== All done! ===" -ForegroundColor Green
Write-Host "Verify with: git status && git diff --name-only HEAD"
