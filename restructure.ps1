$base = "f:\workspace\PyGrasp\content"

function Move-Note($subfolder, $newName, $oldSlug) {
    $src = "$base\$oldSlug"
    $dst = "$base\$subfolder\$newName"
    if (Test-Path $src) {
        Move-Item -Path $src -Destination $dst -Force
        Write-Host "  OK  $oldSlug -> $subfolder\$newName"
    } else {
        Write-Host "  --  SKIP $oldSlug (not found)"
    }
}

# Create all subdirectories first
$dirs = @(
    "01_Core\00_How_Python_Runs",
    "01_Core\01_Object_System",
    "01_Core\02_Memory",
    "01_Core\03_Scopes_and_Functions",
    "01_Core\04_Iterators_and_Generators",
    "01_Core\05_Exceptions",
    "01_Core\06_Modules_and_Packages",
    "01_Core\07_Type_System",
    "02_Concurrency\00_Foundations",
    "02_Concurrency\01_Threading",
    "02_Concurrency\02_Multiprocessing",
    "02_Concurrency\03_Asyncio",
    "02_Concurrency\04_Executors"
)
foreach ($d in $dirs) {
    New-Item -ItemType Directory -Path "$base\$d" -Force | Out-Null
}

Write-Host "=== 01_Core\00_How_Python_Runs ==="
Move-Note "01_Core\00_How_Python_Runs" "01-what-is-python.md"              "01_Core\what-is-python.md"
Move-Note "01_Core\00_How_Python_Runs" "02-compiled-vs-interpreted.md"     "01_Core\compiled-vs-interpreted.md"
Move-Note "01_Core\00_How_Python_Runs" "03-cpython.md"                     "01_Core\cpython.md"
Move-Note "01_Core\00_How_Python_Runs" "04-other-python-implementations.md" "01_Core\other-python-implementations.md"
Move-Note "01_Core\00_How_Python_Runs" "05-source-to-execution.md"         "01_Core\source-to-execution.md"
Move-Note "01_Core\00_How_Python_Runs" "06-tokenization.md"                "01_Core\tokenization.md"
Move-Note "01_Core\00_How_Python_Runs" "07-parsing-and-ast.md"             "01_Core\parsing-and-ast.md"
Move-Note "01_Core\00_How_Python_Runs" "08-bytecode.md"                    "01_Core\bytecode.md"
Move-Note "01_Core\00_How_Python_Runs" "09-pyc-files.md"                   "01_Core\pyc-files.md"
Move-Note "01_Core\00_How_Python_Runs" "10-interpreter-loop.md"            "01_Core\interpreter-loop.md"
Move-Note "01_Core\00_How_Python_Runs" "11-call-stack.md"                  "01_Core\call-stack.md"
Move-Note "01_Core\00_How_Python_Runs" "12-frame-object.md"                "01_Core\frame-object.md"

Write-Host "=== 01_Core\01_Object_System ==="
Move-Note "01_Core\01_Object_System" "01-everything-is-an-object.md"  "01_Core\everything-is-an-object.md"
Move-Note "01_Core\01_Object_System" "02-python-data-model.md"        "01_Core\python-data-model.md"
Move-Note "01_Core\01_Object_System" "03-type-and-object.md"          "01_Core\type-and-object.md"
Move-Note "01_Core\01_Object_System" "04-dunder-methods.md"           "01_Core\dunder-methods.md"
Move-Note "01_Core\01_Object_System" "05-descriptors.md"              "01_Core\descriptors.md"
Move-Note "01_Core\01_Object_System" "06-properties.md"               "01_Core\properties.md"
Move-Note "01_Core\01_Object_System" "07-classmethod-staticmethod.md" "01_Core\classmethod-staticmethod.md"
Move-Note "01_Core\01_Object_System" "08-slots.md"                    "01_Core\slots.md"
Move-Note "01_Core\01_Object_System" "09-class-creation.md"           "01_Core\class-creation.md"
Move-Note "01_Core\01_Object_System" "10-metaclasses.md"              "01_Core\metaclasses.md"
Move-Note "01_Core\01_Object_System" "11-abstract-base-classes.md"    "01_Core\abstract-base-classes.md"
Move-Note "01_Core\01_Object_System" "12-protocols.md"                "01_Core\protocols.md"
Move-Note "01_Core\01_Object_System" "13-dataclasses.md"              "01_Core\dataclasses.md"
Move-Note "01_Core\01_Object_System" "14-enums.md"                    "01_Core\enums.md"
Move-Note "01_Core\01_Object_System" "15-multiple-inheritance.md"     "01_Core\multiple-inheritance.md"
Move-Note "01_Core\01_Object_System" "16-mro.md"                      "01_Core\mro.md"

Write-Host "=== 01_Core\02_Memory ==="
Move-Note "01_Core\02_Memory" "01-python-memory-model.md"  "01_Core\python-memory-model.md"
Move-Note "01_Core\02_Memory" "02-object-header.md"        "01_Core\object-header.md"
Move-Note "01_Core\02_Memory" "03-reference-counting.md"   "01_Core\reference-counting.md"
Move-Note "01_Core\02_Memory" "04-garbage-collection.md"   "01_Core\garbage-collection.md"
Move-Note "01_Core\02_Memory" "05-cyclic-references.md"    "01_Core\cyclic-references.md"
Move-Note "01_Core\02_Memory" "06-memory-allocator.md"     "01_Core\memory-allocator.md"
Move-Note "01_Core\02_Memory" "07-stack-vs-heap.md"        "01_Core\stack-vs-heap.md"
Move-Note "01_Core\02_Memory" "08-mutability.md"           "01_Core\mutability.md"
Move-Note "01_Core\02_Memory" "09-copy-vs-deepcopy.md"     "01_Core\copy-vs-deepcopy.md"
Move-Note "01_Core\02_Memory" "10-id-and-memory-address.md" "01_Core\id-and-memory-address.md"
Move-Note "01_Core\02_Memory" "11-interning.md"            "01_Core\interning.md"
Move-Note "01_Core\02_Memory" "12-small-integer-cache.md"  "01_Core\small-integer-cache.md"

Write-Host "=== 01_Core\03_Scopes_and_Functions ==="
Move-Note "01_Core\03_Scopes_and_Functions" "01-namespaces-and-scopes.md"   "01_Core\namespaces-and-scopes.md"
Move-Note "01_Core\03_Scopes_and_Functions" "02-legb-rule.md"               "01_Core\legb-rule.md"
Move-Note "01_Core\03_Scopes_and_Functions" "03-free-variables.md"          "01_Core\free-variables.md"
Move-Note "01_Core\03_Scopes_and_Functions" "04-closures.md"                "01_Core\closures.md"
Move-Note "01_Core\03_Scopes_and_Functions" "05-first-class-functions.md"   "01_Core\first-class-functions.md"
Move-Note "01_Core\03_Scopes_and_Functions" "06-higher-order-functions.md"  "01_Core\higher-order-functions.md"
Move-Note "01_Core\03_Scopes_and_Functions" "07-args-and-kwargs.md"         "01_Core\args-and-kwargs.md"
Move-Note "01_Core\03_Scopes_and_Functions" "08-lambda.md"                  "01_Core\lambda.md"
Move-Note "01_Core\03_Scopes_and_Functions" "09-decorators.md"              "01_Core\decorators.md"
Move-Note "01_Core\03_Scopes_and_Functions" "10-decorator-with-arguments.md" "01_Core\decorator-with-arguments.md"
Move-Note "01_Core\03_Scopes_and_Functions" "11-functools.md"               "01_Core\functools.md"
Move-Note "01_Core\03_Scopes_and_Functions" "12-partial-functions.md"       "01_Core\partial-functions.md"

Write-Host "=== 01_Core\04_Iterators_and_Generators ==="
Move-Note "01_Core\04_Iterators_and_Generators" "01-iterators.md"            "01_Core\iterators.md"
Move-Note "01_Core\04_Iterators_and_Generators" "02-for-loop-internals.md"   "01_Core\for-loop-internals.md"
Move-Note "01_Core\04_Iterators_and_Generators" "03-generators.md"           "01_Core\generators.md"
Move-Note "01_Core\04_Iterators_and_Generators" "04-generator-expressions.md" "01_Core\generator-expressions.md"
Move-Note "01_Core\04_Iterators_and_Generators" "05-yield-from.md"           "01_Core\yield-from.md"
Move-Note "01_Core\04_Iterators_and_Generators" "06-lazy-evaluation.md"      "01_Core\lazy-evaluation.md"
Move-Note "01_Core\04_Iterators_and_Generators" "07-list-comprehensions.md"  "01_Core\list-comprehensions.md"

Write-Host "=== 01_Core\05_Exceptions ==="
Move-Note "01_Core\05_Exceptions" "01-exceptions.md"          "01_Core\exceptions.md"
Move-Note "01_Core\05_Exceptions" "02-exception-hierarchy.md" "01_Core\exception-hierarchy.md"
Move-Note "01_Core\05_Exceptions" "03-custom-exceptions.md"   "01_Core\custom-exceptions.md"
Move-Note "01_Core\05_Exceptions" "04-context-managers.md"    "01_Core\context-managers.md"
Move-Note "01_Core\05_Exceptions" "05-contextlib.md"          "01_Core\contextlib.md"

Write-Host "=== 01_Core\06_Modules_and_Packages ==="
Move-Note "01_Core\06_Modules_and_Packages" "01-modules.md"              "01_Core\modules.md"
Move-Note "01_Core\06_Modules_and_Packages" "02-packages.md"             "01_Core\packages.md"
Move-Note "01_Core\06_Modules_and_Packages" "03-import-system.md"        "01_Core\import-system.md"
Move-Note "01_Core\06_Modules_and_Packages" "04-relative-imports.md"     "01_Core\relative-imports.md"
Move-Note "01_Core\06_Modules_and_Packages" "05-sys-path.md"             "01_Core\sys-path.md"
Move-Note "01_Core\06_Modules_and_Packages" "06-virtual-environments.md" "01_Core\virtual-environments.md"
Move-Note "01_Core\06_Modules_and_Packages" "07-pip-and-packaging.md"    "01_Core\pip-and-packaging.md"

Write-Host "=== 01_Core\07_Type_System ==="
Move-Note "01_Core\07_Type_System" "01-type-hints.md"              "01_Core\type-hints.md"
Move-Note "01_Core\07_Type_System" "02-typing-module.md"           "01_Core\typing-module.md"
Move-Note "01_Core\07_Type_System" "03-generic-types.md"           "01_Core\generic-types.md"
Move-Note "01_Core\07_Type_System" "04-type-narrowing.md"          "01_Core\type-narrowing.md"
Move-Note "01_Core\07_Type_System" "05-runtime-vs-static-typing.md" "01_Core\runtime-vs-static-typing.md"
Move-Note "01_Core\07_Type_System" "06-mypy.md"                    "01_Core\mypy.md"

Write-Host "=== 02_Concurrency\00_Foundations ==="
Move-Note "02_Concurrency\00_Foundations" "01-os-processes-and-threads.md"  "02_Concurrency\os-processes-and-threads.md"
Move-Note "02_Concurrency\00_Foundations" "02-concurrency-vs-parallelism.md" "02_Concurrency\concurrency-vs-parallelism.md"
Move-Note "02_Concurrency\00_Foundations" "03-io-bound-vs-cpu-bound.md"     "02_Concurrency\io-bound-vs-cpu-bound.md"
Move-Note "02_Concurrency\00_Foundations" "04-context-switching.md"         "02_Concurrency\context-switching.md"
Move-Note "02_Concurrency\00_Foundations" "05-gil.md"                       "02_Concurrency\gil.md"
Move-Note "02_Concurrency\00_Foundations" "06-gil-internals.md"             "02_Concurrency\gil-internals.md"
Move-Note "02_Concurrency\00_Foundations" "07-free-threaded-python.md"      "02_Concurrency\free-threaded-python.md"

Write-Host "=== 02_Concurrency\01_Threading ==="
Move-Note "02_Concurrency\01_Threading" "01-threads.md"              "02_Concurrency\threads.md"
Move-Note "02_Concurrency\01_Threading" "02-thread-lifecycle.md"     "02_Concurrency\thread-lifecycle.md"
Move-Note "02_Concurrency\01_Threading" "03-daemon-threads.md"       "02_Concurrency\daemon-threads.md"
Move-Note "02_Concurrency\01_Threading" "04-thread-vs-process.md"    "02_Concurrency\thread-vs-process.md"
Move-Note "02_Concurrency\01_Threading" "05-locks.md"                "02_Concurrency\locks.md"
Move-Note "02_Concurrency\01_Threading" "06-semaphores.md"           "02_Concurrency\semaphores.md"
Move-Note "02_Concurrency\01_Threading" "07-race-conditions.md"      "02_Concurrency\race-conditions.md"
Move-Note "02_Concurrency\01_Threading" "08-deadlocks.md"            "02_Concurrency\deadlocks.md"
Move-Note "02_Concurrency\01_Threading" "09-thread-safe-queues.md"   "02_Concurrency\thread-safe-queues.md"
Move-Note "02_Concurrency\01_Threading" "10-thread-pool-executor.md" "02_Concurrency\thread-pool-executor.md"

Write-Host "=== 02_Concurrency\02_Multiprocessing ==="
Move-Note "02_Concurrency\02_Multiprocessing" "01-processes.md"                   "02_Concurrency\processes.md"
Move-Note "02_Concurrency\02_Multiprocessing" "02-multiprocessing-module.md"      "02_Concurrency\multiprocessing-module.md"
Move-Note "02_Concurrency\02_Multiprocessing" "03-process-pool.md"                "02_Concurrency\process-pool.md"
Move-Note "02_Concurrency\02_Multiprocessing" "04-shared-memory.md"               "02_Concurrency\shared-memory.md"
Move-Note "02_Concurrency\02_Multiprocessing" "05-inter-process-communication.md" "02_Concurrency\inter-process-communication.md"

Write-Host "=== 02_Concurrency\03_Asyncio ==="
Move-Note "02_Concurrency\03_Asyncio" "01-coroutines.md"             "02_Concurrency\coroutines.md"
Move-Note "02_Concurrency\03_Asyncio" "02-async-await.md"            "02_Concurrency\async-await.md"
Move-Note "02_Concurrency\03_Asyncio" "03-event-loop.md"             "02_Concurrency\event-loop.md"
Move-Note "02_Concurrency\03_Asyncio" "04-event-loop-internals.md"   "02_Concurrency\event-loop-internals.md"
Move-Note "02_Concurrency\03_Asyncio" "05-asyncio.md"                "02_Concurrency\asyncio.md"
Move-Note "02_Concurrency\03_Asyncio" "06-asyncio-tasks.md"          "02_Concurrency\asyncio-tasks.md"
Move-Note "02_Concurrency\03_Asyncio" "07-asyncio-gather.md"         "02_Concurrency\asyncio-gather.md"
Move-Note "02_Concurrency\03_Asyncio" "08-asyncio-queues.md"         "02_Concurrency\asyncio-queues.md"
Move-Note "02_Concurrency\03_Asyncio" "09-asyncio-locks.md"          "02_Concurrency\asyncio-locks.md"
Move-Note "02_Concurrency\03_Asyncio" "10-async-iterators.md"        "02_Concurrency\async-iterators.md"
Move-Note "02_Concurrency\03_Asyncio" "11-async-generators.md"       "02_Concurrency\async-generators.md"
Move-Note "02_Concurrency\03_Asyncio" "12-async-context-managers.md" "02_Concurrency\async-context-managers.md"
Move-Note "02_Concurrency\03_Asyncio" "13-async-patterns.md"         "02_Concurrency\async-patterns.md"
Move-Note "02_Concurrency\03_Asyncio" "14-running-sync-in-async.md"  "02_Concurrency\running-sync-in-async.md"
Move-Note "02_Concurrency\03_Asyncio" "15-aiohttp.md"                "02_Concurrency\aiohttp.md"

Write-Host "=== 02_Concurrency\04_Executors ==="
Move-Note "02_Concurrency\04_Executors" "01-concurrent-futures.md" "02_Concurrency\concurrent-futures.md"

Write-Host "`nAll done."
