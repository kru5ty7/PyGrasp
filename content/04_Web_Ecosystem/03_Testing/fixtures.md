---
title: 03 - Fixtures
description: "pytest fixtures are functions decorated with `@pytest.fixture` that provide setup, teardown, and shared state to tests  -  declared as test function parameters; `yield` fixtures run teardown after the test; `scope` controls how often they run (function/module/session)."
tags: [pytest, fixtures, yield-fixture, scope, conftest, dependency-injection, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Fixtures

> pytest fixtures are functions decorated with `@pytest.fixture` that provide setup, teardown, and shared state to tests  -  declared as test function parameters; `yield` fixtures run teardown after the test; `scope` controls how often they run (function/module/session).

---

## Quick Reference

**Core idea:**
- `@pytest.fixture`  -  decorates a function; pytest calls it and injects the result into tests that declare it as a parameter
- `yield` in a fixture: code before `yield` is setup, code after is teardown (runs after test completes)
- `scope="function"` (default)  -  fixture runs once per test; `scope="module"`  -  once per file; `scope="session"`  -  once per test run
- Fixtures can depend on other fixtures  -  declare as parameters; pytest resolves the dependency graph
- `conftest.py`  -  shared fixture file; automatically loaded; fixtures available to all tests in scope

**Tricky points:**
- A higher-scope fixture cannot depend on a lower-scope fixture  -  `session`-scoped fixture cannot use a `function`-scoped fixture (different lifetime); pytest raises an error
- `yield` fixture teardown runs even if the test fails  -  guarantees cleanup regardless of test outcome
- `autouse=True`  -  fixture applied to all tests in scope without being explicitly declared; use sparingly
- Fixture overriding: a `conftest.py` closer to the test file overrides one higher up; test file can also override fixtures locally
- Factories as fixtures: return a factory function to allow creating multiple instances in one test

---

## What It Is

Fixtures replace `setUp`/`tearDown` from JUnit-style testing with a composable, dependency-injection model. Instead of one monolithic `setUp` that runs everything, each test declares exactly which fixtures it needs, and pytest provides them. This makes setup explicit, reusable, and composable.

The `yield` fixture pattern is directly analogous to the `yield` dependency in FastAPI  -  setup before, teardown after, cleanup guaranteed via the generator protocol.

---

## How It Actually Works

Basic fixture:
```python
import pytest
from myapp.database import User

@pytest.fixture
def sample_user():
    user = User(name="Alice", email="alice@example.com")
    return user

def test_user_name(sample_user):
    assert sample_user.name == "Alice"

def test_user_email(sample_user):
    assert sample_user.email == "alice@example.com"
```

`yield` fixture with teardown:
```python
@pytest.fixture
def temp_directory(tmp_path):
    directory = tmp_path / "test_dir"
    directory.mkdir()
    yield directory  # test runs here
    # teardown: shutil.rmtree(directory)  -  but tmp_path handles it automatically
    
@pytest.fixture
def db_connection():
    conn = create_test_connection()
    conn.execute("BEGIN")
    yield conn
    conn.execute("ROLLBACK")  # always rollback  -  no state persists between tests
    conn.close()
```

Fixture depending on another fixture:
```python
@pytest.fixture
def db():
    engine = create_test_engine()
    Base.metadata.create_all(engine)
    yield engine
    Base.metadata.drop_all(engine)

@pytest.fixture
def session(db):  # depends on db fixture
    with Session(db) as session:
        yield session
        session.rollback()

def test_create_user(session):
    user = User(name="Alice")
    session.add(user)
    session.flush()
    assert user.id is not None
```

Parametrized fixture:
```python
@pytest.fixture(params=["sqlite", "postgresql"])
def db_url(request):
    if request.param == "sqlite":
        return "sqlite:///:memory:"
    return "postgresql://localhost/testdb"

def test_connection(db_url):
    # runs twice  -  once for each db_url value
    engine = create_engine(db_url)
    assert engine.connect()
```

Factory fixture:
```python
@pytest.fixture
def make_user():
    created = []
    def _make(name="Alice", email=None):
        user = User(name=name, email=email or f"{name.lower()}@example.com")
        created.append(user)
        return user
    yield _make
    # teardown: delete all created users
    for user in created:
        user.delete()

def test_two_users(make_user):
    alice = make_user("Alice")
    bob = make_user("Bob")
    assert alice.email != bob.email
```

---

## How It Connects

Fixtures are the mechanism behind FastAPI's `TestClient` and async test database sessions  -  the test client and DB session are fixtures.
[[testing-fastapi|Testing FastAPI]]

pytest's fixture system has the same dependency injection pattern as FastAPI's `Depends()`  -  both resolve a dependency graph at runtime.
[[fastapi-dependencies|FastAPI Dependencies]]

---

## Common Misconceptions

Misconception 1: "Fixtures with `scope='session'` share state safely between all tests."
Reality: Session-scoped fixtures create one instance shared across all tests. If any test modifies the fixture's state (e.g., adds rows to a session-scoped database), subsequent tests see that state. This causes test ordering dependencies. Use `scope='function'` for anything mutable unless you explicitly want shared state.

Misconception 2: "Fixtures run in the order they appear in the test signature."
Reality: pytest resolves fixtures by their dependency graph, not parameter order. The setup and teardown order follows the dependency tree, not the function signature.

---

## Why It Matters in Practice

The `db_session` fixture is the most important for web app testing:
```python
# conftest.py
@pytest.fixture(scope="session")
def engine():
    engine = create_test_engine()
    Base.metadata.create_all(engine)
    yield engine
    Base.metadata.drop_all(engine)

@pytest.fixture
def db_session(engine):
    with Session(engine) as session:
        yield session
        session.rollback()  # always rollback -> no test pollution
```

`scope="session"` for the engine (expensive to create) + `scope="function"` (default) for the session (cheap, must be fresh per test)  -  this pattern is the foundation of most web app test suites.

---

## Interview Angle

Common question forms:
- "How do you set up and tear down test state in pytest?"
- "What is a yield fixture?"

Answer frame: `@pytest.fixture`  -  function that provides setup and optionally teardown. Declare as test parameter  -  pytest injects. `yield` fixture: code before yield runs before the test, code after runs after (guaranteed cleanup). `scope` controls reuse: `"function"` = per test (default), `"module"` = per file, `"session"` = once per run. `conftest.py` for shared fixtures across tests. Fixtures can depend on other fixtures.

---

## Related Notes

- [[pytest|Pytest]]
- [[testing-basics|Testing Basics]]
- [[testing-fastapi|Testing FastAPI]]
- [[mocking|Mocking]]
