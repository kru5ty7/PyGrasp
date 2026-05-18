---
title: 08 - factory_boy
description: "factory_boy is a Python test fixture library that generates model instances with sensible defaults, making it easy to create complex object graphs for tests without manually specifying every field."
tags: [factory-boy, testing, fixtures, models, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# factory_boy

> factory_boy generates realistic test data objects on demand  -  define your model's shape once in a factory class and create as many instances as you need with the exact overrides your test requires.

---

## Quick Reference

**Core idea:**
- `factory.Factory` for plain Python objects; `factory.django.DjangoModelFactory` for Django models (saves to DB)
- `factory.Sequence(lambda n: f'user_{n}')` generates unique sequential values per call
- `factory.SubFactory(OtherFactory)` generates a related object  -  handles foreign keys automatically
- `factory.Faker('email')` uses Faker library to generate realistic fake data
- `build()` creates an instance without saving; `create()` saves to DB; `build_batch(n)` / `create_batch(n)` for multiples

**Tricky points:**
- `create()` requires a database connection  -  in tests without a database, use `build()` or `stub()`
- `SubFactory` calls `create()` by default  -  if the parent is built (not created), related objects are also built; this is handled automatically by factory_boy's build strategy propagation
- `factory.LazyAttribute(lambda obj: ...)` computes a value based on other fields of the same factory instance  -  order matters for field dependencies
- `DjangoModelFactory` uses `_meta.model`  -  always set this to the Django model class, not the database table name
- `factory.Faker` is a thin wrapper around the `faker` library  -  any Faker provider is available by passing its method name as a string

---

## What It Is

Writing tests for models with many required fields quickly becomes tedious. A `User` model might have `email`, `username`, `first_name`, `last_name`, `date_joined`, `is_active`, `role`, and `organization`. Every test that creates a user must provide valid values for all required fields  -  even if the test only cares about the `role` field. The boilerplate is noise that obscures the test's intent.

factory_boy solves this by defining a factory class that knows how to generate valid instances of your model with reasonable defaults. The test specifies only the fields it actually cares about; factory_boy generates everything else. A test that is checking user role permissions writes `user = UserFactory(role='admin')`  -  one line, readable intent, no noise from unrelated fields.

The library mirrors the pattern introduced by Rails' factory_girl (later FactoryBot) for the Python ecosystem. It integrates with Django's test framework by saving created objects to the test database and automatically handling foreign key relationships through `SubFactory`. It also works with SQLAlchemy models, plain Python classes, and MongoDB documents. The factory definition serves as living documentation of valid model states  -  if a factory is hard to write, it often signals that the model has too many required fields or too many hidden invariants.

---

## How It Actually Works

A factory mirrors the structure of the model it produces. Fields without overrides use the factory's declared defaults; overrides are passed as keyword arguments at call time.

```python
import factory
from factory.django import DjangoModelFactory
from myapp.models import User, Post, Organization

class OrganizationFactory(DjangoModelFactory):
    class Meta:
        model = Organization

    name = factory.Sequence(lambda n: f"Organization {n}")
    slug = factory.LazyAttribute(lambda obj: obj.name.lower().replace(" ", "-"))

class UserFactory(DjangoModelFactory):
    class Meta:
        model = User

    username = factory.Sequence(lambda n: f"user_{n}")
    email = factory.LazyAttribute(lambda obj: f"{obj.username}@example.com")
    first_name = factory.Faker("first_name")
    last_name = factory.Faker("last_name")
    is_active = True
    organization = factory.SubFactory(OrganizationFactory)

class PostFactory(DjangoModelFactory):
    class Meta:
        model = Post

    title = factory.Faker("sentence", nb_words=5)
    body = factory.Faker("paragraphs", nb=3, as_list=False)
    author = factory.SubFactory(UserFactory)
    published = False
```

Using factories in tests:

```python
# Create one user with all defaults
user = UserFactory()

# Override specific fields
admin = UserFactory(role="admin", is_active=True)

# Shared organization  -  both users belong to the same org
org = OrganizationFactory()
user1 = UserFactory(organization=org)
user2 = UserFactory(organization=org)

# Build without saving to DB (no database needed)
user = UserFactory.build()
post = PostFactory.build(author=user)

# Create multiple instances
users = UserFactory.create_batch(10)
inactive_users = UserFactory.create_batch(5, is_active=False)

# Stub  -  object with only the declared attributes, no real class
user_stub = UserFactory.stub()
print(user_stub.email)  # "user_0@example.com"  -  no DB, no model class
```

For SQLAlchemy, the `SQLAlchemyModelFactory` base class requires a session to be provided.

```python
from factory.alchemy import SQLAlchemyModelFactory
from myapp.database import Session

class UserFactory(SQLAlchemyModelFactory):
    class Meta:
        model = User
        sqlalchemy_session = Session

    username = factory.Sequence(lambda n: f"user_{n}")
```

---

## How It Connects

factory_boy works best inside pytest fixtures  -  a factory can be called inside a fixture to provide model instances to tests.

[[fixtures|Fixtures]]

Testing FastAPI endpoints with realistic model data uses factories to populate the test database before each test case.

[[testing-fastapi|Testing FastAPI]]

---

## Common Misconceptions

Misconception 1: "factory_boy is only for Django projects."
Reality: factory_boy's core `factory.Factory` works with any Python class. `DjangoModelFactory` handles Django ORM integration. `SQLAlchemyModelFactory` integrates with SQLAlchemy. Plain dataclasses, attrs classes, and Pydantic models can all be generated with factory_boy.

Misconception 2: "`SubFactory` always creates a new related object, making tests slow."
Reality: `SubFactory` creates a new object only if no value is provided. Tests that need to share a related object pass it explicitly: `PostFactory(author=existing_user)`. When using `create_batch`, each batch item gets a fresh `SubFactory` instance  -  to share one across a batch, create the related object first and pass it to all batch items.

---

## Why It Matters in Practice

Tests with manually constructed model instances become maintenance burdens when models evolve  -  adding a required field breaks dozens of test setups. factory_boy centralizes model construction, so adding a field means updating one factory definition. The test bodies remain clean and focused on the behavior being tested rather than the mechanics of object construction.

---

## Interview Angle

Common question forms:
- "How do you generate test data for database models in pytest?"
- "What is the difference between `build()` and `create()` in factory_boy?"
- "How do you handle related objects (foreign keys) in factory_boy?"

Answer frame:
factory_boy defines factory classes that generate model instances with sensible defaults  -  tests override only what they care about. `build()` creates an instance without touching the database; `create()` saves it. Related objects use `SubFactory` which creates the related object automatically  -  or you pass an existing one to share it. `Sequence` ensures unique values; `Faker` generates realistic data.

---

## Related Notes

- [[fixtures|Fixtures]]
- [[pytest|pytest]]
- [[testing-fastapi|Testing FastAPI]]
- [[testing-basics|Testing Basics]]
