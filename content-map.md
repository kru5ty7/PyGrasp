# PyGrasp - Content Map (with sequencing)

> Proposed filenames with sequence prefixes so Quartz renders them in topic order.
> Files are **not yet renamed** - this is the reference plan.
> Format: `NN-original-slug.md`

---

## `01_Core/`

### `00_How_Python_Runs/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-what-is-python.md` | `what-is-python.md` |
| 02 | `02-compiled-vs-interpreted.md` | `compiled-vs-interpreted.md` |
| 03 | `03-cpython.md` | `cpython.md` |
| 04 | `04-other-python-implementations.md` | `other-python-implementations.md` |
| 05 | `05-source-to-execution.md` | `source-to-execution.md` |
| 06 | `06-tokenization.md` | `tokenization.md` |
| 07 | `07-parsing-and-ast.md` | `parsing-and-ast.md` |
| 08 | `08-bytecode.md` | `bytecode.md` |
| 09 | `09-pyc-files.md` | `pyc-files.md` |
| 10 | `10-interpreter-loop.md` | `interpreter-loop.md` |
| 11 | `11-call-stack.md` | `call-stack.md` |
| 12 | `12-frame-object.md` | `frame-object.md` |

---

### `01_Object_System/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-everything-is-an-object.md` | `everything-is-an-object.md` |
| 02 | `02-python-data-model.md` | `python-data-model.md` |
| 03 | `03-type-and-object.md` | `type-and-object.md` |
| 04 | `04-dunder-methods.md` | `dunder-methods.md` |
| 05 | `05-descriptors.md` | `descriptors.md` |
| 06 | `06-properties.md` | `properties.md` |
| 07 | `07-classmethod-staticmethod.md` | `classmethod-staticmethod.md` |
| 08 | `08-slots.md` | `slots.md` |
| 09 | `09-class-creation.md` | `class-creation.md` |
| 10 | `10-metaclasses.md` | `metaclasses.md` |
| 11 | `11-abstract-base-classes.md` | `abstract-base-classes.md` |
| 12 | `12-protocols.md` | `protocols.md` |
| 13 | `13-dataclasses.md` | `dataclasses.md` |
| 14 | `14-enums.md` | `enums.md` |
| 15 | `15-multiple-inheritance.md` | `multiple-inheritance.md` |
| 16 | `16-mro.md` | `mro.md` |

---

### `02_Memory/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-python-memory-model.md` | `python-memory-model.md` |
| 02 | `02-object-header.md` | `object-header.md` |
| 03 | `03-reference-counting.md` | `reference-counting.md` |
| 04 | `04-garbage-collection.md` | `garbage-collection.md` |
| 05 | `05-cyclic-references.md` | `cyclic-references.md` |
| 06 | `06-memory-allocator.md` | `memory-allocator.md` |
| 07 | `07-stack-vs-heap.md` | `stack-vs-heap.md` |
| 08 | `08-mutability.md` | `mutability.md` |
| 09 | `09-copy-vs-deepcopy.md` | `copy-vs-deepcopy.md` |
| 10 | `10-id-and-memory-address.md` | `id-and-memory-address.md` |
| 11 | `11-interning.md` | `interning.md` |
| 12 | `12-small-integer-cache.md` | `small-integer-cache.md` |

---

### `03_Scopes_and_Functions/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-namespaces-and-scopes.md` | `namespaces-and-scopes.md` |
| 02 | `02-legb-rule.md` | `legb-rule.md` |
| 03 | `03-free-variables.md` | `free-variables.md` |
| 04 | `04-closures.md` | `closures.md` |
| 05 | `05-first-class-functions.md` | `first-class-functions.md` |
| 06 | `06-higher-order-functions.md` | `higher-order-functions.md` |
| 07 | `07-args-and-kwargs.md` | `args-and-kwargs.md` |
| 08 | `08-lambda.md` | `lambda.md` |
| 09 | `09-decorators.md` | `decorators.md` |
| 10 | `10-decorator-with-arguments.md` | `decorator-with-arguments.md` |
| 11 | `11-functools.md` | `functools.md` |
| 12 | `12-partial-functions.md` | `partial-functions.md` |

---

### `04_Iterators_and_Generators/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-iterators.md` | `iterators.md` |
| 02 | `02-for-loop-internals.md` | `for-loop-internals.md` |
| 03 | `03-generators.md` | `generators.md` |
| 04 | `04-generator-expressions.md` | `generator-expressions.md` |
| 05 | `05-yield-from.md` | `yield-from.md` |
| 06 | `06-lazy-evaluation.md` | `lazy-evaluation.md` |
| 07 | `07-list-comprehensions.md` | `list-comprehensions.md` |

---

### `05_Exceptions/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-exceptions.md` | `exceptions.md` |
| 02 | `02-exception-hierarchy.md` | `exception-hierarchy.md` |
| 03 | `03-custom-exceptions.md` | `custom-exceptions.md` |
| 04 | `04-context-managers.md` | `context-managers.md` |
| 05 | `05-contextlib.md` | `contextlib.md` |

---

### `06_Modules_and_Packages/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-modules.md` | `modules.md` |
| 02 | `02-packages.md` | `packages.md` |
| 03 | `03-import-system.md` | `import-system.md` |
| 04 | `04-relative-imports.md` | `relative-imports.md` |
| 05 | `05-sys-path.md` | `sys-path.md` |
| 06 | `06-virtual-environments.md` | `virtual-environments.md` |
| 07 | `07-pip-and-packaging.md` | `pip-and-packaging.md` |

---

### `07_Type_System/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-type-hints.md` | `type-hints.md` |
| 02 | `02-typing-module.md` | `typing-module.md` |
| 03 | `03-generic-types.md` | `generic-types.md` |
| 04 | `04-type-narrowing.md` | `type-narrowing.md` |
| 05 | `05-runtime-vs-static-typing.md` | `runtime-vs-static-typing.md` |
| 06 | `06-mypy.md` | `mypy.md` |

---

## `02_Concurrency/`

### `00_Foundations/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-os-processes-and-threads.md` | `os-processes-and-threads.md` |
| 02 | `02-concurrency-vs-parallelism.md` | `concurrency-vs-parallelism.md` |
| 03 | `03-io-bound-vs-cpu-bound.md` | `io-bound-vs-cpu-bound.md` |
| 04 | `04-context-switching.md` | `context-switching.md` |
| 05 | `05-gil.md` | `gil.md` |
| 06 | `06-gil-internals.md` | `gil-internals.md` |
| 07 | `07-free-threaded-python.md` | `free-threaded-python.md` |

---

### `01_Threading/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-threads.md` | `threads.md` |
| 02 | `02-thread-lifecycle.md` | `thread-lifecycle.md` |
| 03 | `03-daemon-threads.md` | `daemon-threads.md` |
| 04 | `04-thread-vs-process.md` | `thread-vs-process.md` |
| 05 | `05-locks.md` | `locks.md` |
| 06 | `06-semaphores.md` | `semaphores.md` |
| 07 | `07-race-conditions.md` | `race-conditions.md` |
| 08 | `08-deadlocks.md` | `deadlocks.md` |
| 09 | `09-thread-safe-queues.md` | `thread-safe-queues.md` |
| 10 | `10-thread-pool-executor.md` | `thread-pool-executor.md` |

---

### `02_Multiprocessing/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-processes.md` | `processes.md` |
| 02 | `02-multiprocessing-module.md` | `multiprocessing-module.md` |
| 03 | `03-process-pool.md` | `process-pool.md` |
| 04 | `04-shared-memory.md` | `shared-memory.md` |
| 05 | `05-inter-process-communication.md` | `inter-process-communication.md` |

---

### `03_Asyncio/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-coroutines.md` | `coroutines.md` |
| 02 | `02-async-await.md` | `async-await.md` |
| 03 | `03-event-loop.md` | `event-loop.md` |
| 04 | `04-event-loop-internals.md` | `event-loop-internals.md` |
| 05 | `05-asyncio.md` | `asyncio.md` |
| 06 | `06-asyncio-tasks.md` | `asyncio-tasks.md` |
| 07 | `07-asyncio-gather.md` | `asyncio-gather.md` |
| 08 | `08-asyncio-queues.md` | `asyncio-queues.md` |
| 09 | `09-asyncio-locks.md` | `asyncio-locks.md` |
| 10 | `10-async-iterators.md` | `async-iterators.md` |
| 11 | `11-async-generators.md` | `async-generators.md` |
| 12 | `12-async-context-managers.md` | `async-context-managers.md` |
| 13 | `13-async-patterns.md` | `async-patterns.md` |
| 14 | `14-running-sync-in-async.md` | `running-sync-in-async.md` |
| 15 | `15-aiohttp.md` | `aiohttp.md` |

---

### `04_Executors/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-concurrent-futures.md` | `concurrent-futures.md` |

---

## `03_Web/`

### `00_HTTP_Basics/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-http-basics.md` | `http-basics.md` |
| 02 | `02-http-methods.md` | `http-methods.md` |
| 03 | `03-http-status-codes.md` | `http-status-codes.md` |
| 04 | `04-http-headers.md` | `http-headers.md` |
| 05 | `05-http-request-lifecycle.md` | `http-request-lifecycle.md` |
| 06 | `06-rest.md` | `rest.md` |
| 07 | `07-websockets.md` | `websockets.md` |

---

### `01_WSGI_ASGI/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-wsgi.md` | `wsgi.md` |
| 02 | `02-asgi.md` | `asgi.md` |
| 03 | `03-wsgi-vs-asgi.md` | `wsgi-vs-asgi.md` |
| 04 | `04-uvicorn.md` | `uvicorn.md` |
| 05 | `05-gunicorn.md` | `gunicorn.md` |
| 06 | `06-starlette.md` | `starlette.md` |

---

### `02_FastAPI/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-fastapi.md` | `fastapi.md` |
| 02 | `02-path-and-query-params.md` | `path-and-query-params.md` |
| 03 | `03-request-body.md` | `request-body.md` |
| 04 | `04-response-model.md` | `response-model.md` |
| 05 | `05-fastapi-routers.md` | `fastapi-routers.md` |
| 06 | `06-dependency-injection.md` | `dependency-injection.md` |
| 07 | `07-fastapi-dependencies.md` | `fastapi-dependencies.md` |
| 08 | `08-fastapi-middleware.md` | `fastapi-middleware.md` |
| 09 | `09-fastapi-lifespan.md` | `fastapi-lifespan.md` |
| 10 | `10-background-tasks.md` | `background-tasks.md` |
| 11 | `11-fastapi-security.md` | `fastapi-security.md` |
| 12 | `12-fastapi-websockets.md` | `fastapi-websockets.md` |
| 13 | `13-openapi.md` | `openapi.md` |

---

### `03_Pydantic/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-pydantic.md` | `pydantic.md` |
| 02 | `02-pydantic-validators.md` | `pydantic-validators.md` |
| 03 | `03-pydantic-settings.md` | `pydantic-settings.md` |
| 04 | `04-serialization.md` | `serialization.md` |
| 05 | `05-json-schema.md` | `json-schema.md` |

---

### `04_Auth/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-authentication-vs-authorization.md` | `authentication-vs-authorization.md` |
| 02 | `02-hashing-and-passwords.md` | `hashing-and-passwords.md` |
| 03 | `03-jwt.md` | `jwt.md` |
| 04 | `04-oauth2.md` | `oauth2.md` |
| 05 | `05-cors.md` | `cors.md` |
| 06 | `06-request-response-cycle.md` | `request-response-cycle.md` |

---

## `04_AI/`

### `00_LLM_Basics/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-llm-basics.md` | `llm-basics.md` |
| 02 | `02-embeddings.md` | `embeddings.md` |
| 03 | `03-vector-search.md` | `vector-search.md` |
| 04 | `04-rag.md` | `rag.md` |

---

### `01_LangChain/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-langchain-basics.md` | `langchain-basics.md` |
| 02 | `02-tool-calling.md` | `tool-calling.md` |
| 03 | `03-agents.md` | `agents.md` |

---

### `02_LangGraph/`
| # | Proposed filename | Current filename |
|---|-------------------|-----------------|
| 01 | `01-langgraph-core.md` | `langgraph-core.md` |
| 02 | `02-state-graph.md` | `state-graph.md` |
| 03 | `03-nodes-and-edges.md` | `nodes-and-edges.md` |
