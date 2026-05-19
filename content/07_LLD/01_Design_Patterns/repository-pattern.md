---
title: 14 - Repository Pattern
description: The Repository pattern mediates between the domain and data mapping layers, providing a collection-like interface for accessing domain objects while hiding the details of data access.
tags: [design-patterns, repository, data-access, persistence, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Repository Pattern

> The Repository pattern provides a collection-like interface for accessing domain objects, abstracting away the data source so that business logic does not know whether data comes from a database, API, file, or memory.

---

## Quick Reference

**Core idea:**
- A repository acts as an in-memory collection of domain objects with methods like `get()`, `save()`, `delete()`, `find_by()`
- Business logic calls repository methods without knowing whether the storage is Postgres, MongoDB, Redis, or a dictionary
- Implements DIP: business logic depends on the repository abstraction, not on the database directly
- Enables testing: swap `PostgresRepository` for `InMemoryRepository` in tests
- Common in Python: SQLAlchemy's `Session`, Django's `Model.objects` manager, FastAPI dependency injection

**Tricky points:**
- A repository is not a generic CRUD wrapper - it should expose domain-specific query methods (`find_active_users()`, not `find_by_sql()`)
- The repository interface should use domain objects, not raw dictionaries or ORM models
- Too many query methods bloat the repository - use specification/criteria pattern for complex queries
- Repository vs DAO (Data Access Object): Repository works with domain objects, DAO works with data transfer objects

---

## What It Is

Think of a library catalog system. When you want a book, you tell the librarian what you are looking for - a title, an author, a genre. The librarian goes to the shelves, finds the book, and hands it to you. You never walk into the storage room, figure out the shelving system, or write the Dewey Decimal lookup. The librarian is the repository. The shelves are the database. The catalog interface (search by title, by author) is the repository's API.

The Repository pattern puts a collection-like interface between your business logic and your data source. Your `UserService` calls `repo.get(user_id)` and receives a `User` domain object. It does not import SQLAlchemy, construct queries, manage sessions, or parse database rows. If the storage changes from PostgreSQL to MongoDB, only the repository implementation changes. The service is untouched.

This separation is critical for testing. Your service tests use an `InMemoryRepository` that stores users in a dictionary. Tests run in milliseconds without a database. Your integration tests use the real `PostgresRepository`. The service code is identical in both cases because it depends on the repository abstraction, not on the database.

---

## How It Actually Works

The repository is typically defined as a Protocol or ABC with methods that match how the business logic accesses data. Concrete implementations translate these method calls into database queries, API calls, or in-memory lookups. The business logic receives the repository through constructor injection.

```python
from typing import Protocol
from dataclasses import dataclass, field
from datetime import datetime
from uuid import uuid4


# Domain model - pure Python, no ORM dependencies
@dataclass
class User:
    id: str
    name: str
    email: str
    created_at: datetime
    is_active: bool = True

    @staticmethod
    def create(name: str, email: str) -> "User":
        return User(
            id=str(uuid4()),
            name=name,
            email=email,
            created_at=datetime.now(),
        )


# Repository interface - defined by the business layer
class UserRepository(Protocol):
    def get(self, user_id: str) -> User | None: ...
    def save(self, user: User) -> None: ...
    def delete(self, user_id: str) -> bool: ...
    def find_by_email(self, email: str) -> User | None: ...
    def find_active(self) -> list[User]: ...


# In-memory implementation (for tests)
class InMemoryUserRepository:
    def __init__(self):
        self._store: dict[str, User] = {}

    def get(self, user_id: str) -> User | None:
        return self._store.get(user_id)

    def save(self, user: User) -> None:
        self._store[user.id] = user

    def delete(self, user_id: str) -> bool:
        return self._store.pop(user_id, None) is not None

    def find_by_email(self, email: str) -> User | None:
        return next(
            (u for u in self._store.values() if u.email == email),
            None,
        )

    def find_active(self) -> list[User]:
        return [u for u in self._store.values() if u.is_active]


# PostgreSQL implementation (production)
class PostgresUserRepository:
    def __init__(self, connection_string: str):
        self._conn_str = connection_string
        # In real code: self._engine = create_engine(connection_string)

    def get(self, user_id: str) -> User | None:
        # In real code: session.query(UserModel).filter_by(id=user_id).first()
        print(f"SELECT * FROM users WHERE id = '{user_id}'")
        return User(id=user_id, name="DB User", email="db@test.com",
                    created_at=datetime.now())

    def save(self, user: User) -> None:
        print(f"INSERT INTO users VALUES ('{user.id}', '{user.name}', ...)")

    def delete(self, user_id: str) -> bool:
        print(f"DELETE FROM users WHERE id = '{user_id}'")
        return True

    def find_by_email(self, email: str) -> User | None:
        print(f"SELECT * FROM users WHERE email = '{email}'")
        return None

    def find_active(self) -> list[User]:
        print("SELECT * FROM users WHERE is_active = true")
        return []


# Business logic depends on abstraction only
class UserService:
    def __init__(self, repo: UserRepository):
        self._repo = repo

    def register(self, name: str, email: str) -> User:
        existing = self._repo.find_by_email(email)
        if existing:
            raise ValueError(f"Email {email} already registered")

        user = User.create(name, email)
        self._repo.save(user)
        return user

    def deactivate(self, user_id: str) -> None:
        user = self._repo.get(user_id)
        if not user:
            raise ValueError(f"User {user_id} not found")
        user.is_active = False
        self._repo.save(user)

    def get_active_users(self) -> list[User]:
        return self._repo.find_active()


# Testing - no database needed
def test_register():
    repo = InMemoryUserRepository()
    service = UserService(repo)

    user = service.register("Alice", "alice@test.com")

    assert user.name == "Alice"
    assert repo.find_by_email("alice@test.com") is not None

def test_duplicate_email():
    repo = InMemoryUserRepository()
    service = UserService(repo)
    service.register("Alice", "alice@test.com")

    try:
        service.register("Bob", "alice@test.com")
        assert False, "Should have raised"
    except ValueError as e:
        assert "already registered" in str(e)

test_register()
test_duplicate_email()
print("All tests passed!")

# Production - wire up with real database
# service = UserService(PostgresUserRepository("postgresql://localhost/mydb"))
```

---

## Visualizer

<iframe src="/static/visualizers/repository-pattern.html" style="width:100%;height:460px;border:none;border-radius:8px;" title="Repository Pattern Visualizer"></iframe>

---

## How It Connects

The Repository pattern is the canonical implementation of the Dependency Inversion Principle. Business logic depends on the repository abstraction; the database implements it.

[[dip|Dependency Inversion Principle]]

[[abstraction|Abstraction]]

Repositories are composed into services via dependency injection. The composition root wires concrete repositories to the services that need them.

[[dependency-injection-pattern|Dependency Injection Pattern]]

The Repository pattern works with domain models that represent business concepts. Understanding domain modeling helps you design repository interfaces that match how the business thinks about data.

[[design-patterns-overview|Design Patterns Overview]]

---

## Common Misconceptions

Misconception 1: "A repository is just a CRUD wrapper."
Reality: A repository exposes domain-specific queries (`find_active_users()`, `get_orders_by_customer()`), not generic CRUD (`insert()`, `update()`, `select()`). The interface should match the language of the business domain, not the language of SQL.

Misconception 2: "Django's ORM already gives me the Repository pattern."
Reality: Django's `Model.objects` manager is a query builder, not a repository. Business logic that calls `User.objects.filter(is_active=True).select_related('profile')` is directly coupled to Django's ORM. A repository wraps this behind a domain-oriented interface, making it possible to test without Django's test infrastructure.

---

## Why It Matters in Practice

The Repository pattern is the most impactful pattern for testability. Without it, testing business logic requires a running database, test data setup, and teardown - making tests slow and flaky. With an in-memory repository, tests run instantly and are fully deterministic.

Beyond testing, repositories protect your business logic from infrastructure changes. Migrating from PostgreSQL to MongoDB, adding a caching layer, or sharding your database affects only the repository implementations. The service layer, the API layer, and all business rules remain unchanged.

---

## Interview Angle

Common question forms:
- "What is the Repository pattern?"
- "How does the Repository pattern improve testability?"
- "What is the difference between a Repository and a DAO?"

Answer frame:
Define repository as a collection-like interface for domain objects. Show the Protocol, two implementations (in-memory + Postgres), and a service that depends on the abstraction. Demonstrate testing with the in-memory version. Distinguish from DAO (domain objects vs data transfer objects) and from ORM managers (domain language vs query language).

---

## Related Notes

- [[dip|Dependency Inversion Principle]]
- [[abstraction|Abstraction]]
- [[dependency-injection-pattern|Dependency Injection Pattern]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[solid-principles|SOLID Principles]]
