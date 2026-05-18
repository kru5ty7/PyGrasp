---
title: 08 - Flask-SQLAlchemy
description: "Flask-SQLAlchemy integrates SQLAlchemy's ORM into Flask's request lifecycle, binding sessions to the request context and providing a declarative model base."
tags: [flask, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Flask-SQLAlchemy

> Flask-SQLAlchemy wires SQLAlchemy's ORM into Flask's application and request contexts — binding database sessions to the request lifecycle, providing a `db.Model` base class, and managing connection pool teardown automatically.

---

## Quick Reference

**Core idea:**
- `db = SQLAlchemy()` at module level, `db.init_app(app)` in the factory — standard lazy initialization
- `class User(db.Model)` defines a mapped ORM model using Flask-SQLAlchemy's declarative base
- `db.session.add(obj)`, `db.session.commit()`, `db.session.rollback()`, `db.session.query(User)` are the core session operations
- Flask-SQLAlchemy wraps SQLAlchemy's engine and session factory — the underlying SQLAlchemy ORM mechanics apply in full
- `db.create_all()` creates tables from model definitions; Alembic (via Flask-Migrate) manages production schema migrations

**Tricky points:**
- `db.session` is scoped to the request — it is a `scoped_session` tied to the application context, not a plain session, so it is automatically removed at request teardown
- Calling `db.session.commit()` in a `before_request` hook is rarely correct and often a sign of incorrect session lifecycle management
- `db.create_all()` does not detect schema changes — it only creates missing tables; for any schema evolution, use Flask-Migrate
- Accessing `db.session` outside a request or app context raises `RuntimeError` because the session registry cannot find an active application context
- Lazy-loading relationships trigger additional SQL queries — understanding when SQLAlchemy fires additional queries prevents N+1 problems

---

## What It Is

A relational database is like a well-organized filing cabinet. Each table is a drawer, each row is a folder, and the columns are the labeled sections inside each folder. SQLAlchemy's ORM is the filing system that lets Python code work with this cabinet using Python objects instead of raw folder labels — you retrieve a `User` object, modify its `.email` attribute, and the ORM translates this into an `UPDATE` statement. Flask-SQLAlchemy is the integration layer that mounts this filing system inside a Flask application, ensuring that the filing clerk (the database session) is properly set up when a request begins and properly put away when it ends.

Without Flask-SQLAlchemy, integrating SQLAlchemy with Flask requires manual session lifecycle management: creating a session factory with `sessionmaker`, managing the engine, handling session scope and teardown, and wiring session removal into Flask's `teardown_appcontext` hook. Flask-SQLAlchemy does all of this automatically. It creates the engine from `SQLALCHEMY_DATABASE_URI` in Flask's config, creates a `scoped_session` tied to the application context, and registers a `teardown_appcontext` callback that calls `db.session.remove()` at the end of each request. The `db.Model` declarative base gives all models access to the session and the metadata needed for `db.create_all()`.

The relationship between Flask-SQLAlchemy and SQLAlchemy Core is that of a polished facade over a full engine. Flask-SQLAlchemy uses SQLAlchemy's engine, connection pool, ORM session, and mapper system internally. This means every feature of the underlying SQLAlchemy library — relationship loading strategies, column types, hybrid properties, query optimization with `joinedload()` and `subqueryload()`, direct Core expressions — is available and works exactly as the SQLAlchemy documentation describes. Flask-SQLAlchemy adds the Flask integration layer; it does not replace or simplify the underlying library.

---

## How It Actually Works

Flask-SQLAlchemy's session is a `scoped_session` from SQLAlchemy, scoped to the application context. When you access `db.session` for the first time within a request, SQLAlchemy checks if a session exists for the current scope key (the application context) and creates one if it does not. All subsequent accesses within the same request return the same session. When the request ends and Flask pops the application context, the registered teardown callback calls `db.session.remove()`, which calls `session.close()` and returns the underlying connection to the pool. This means you never need to explicitly close sessions — the lifecycle is managed automatically by the Flask-SQLAlchemy integration.

```python
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class User(db.Model):
    __tablename__ = 'users'
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    posts = db.relationship('Post', backref='author', lazy='select')

    def __repr__(self):
        return f'<User {self.username}>'

# View function
from flask import jsonify

@app.route('/users/<int:user_id>')
def get_user(user_id):
    user = db.session.get(User, user_id)  # SQLAlchemy 2.x preferred over .query.get()
    if user is None:
        abort(404)
    return jsonify({'id': user.id, 'username': user.username})

@app.route('/users', methods=['POST'])
def create_user():
    data = request.get_json()
    user = User(username=data['username'], email=data['email'])
    db.session.add(user)
    db.session.commit()
    return jsonify({'id': user.id}), 201
```

`db.create_all()` iterates over all `db.Model` subclasses and issues `CREATE TABLE IF NOT EXISTS` for each one. It is useful for development and test setup but is not a migration tool — it cannot alter existing tables, add columns, or rename constraints. Flask-Migrate wraps Alembic to provide migration scripts that can be generated automatically from model changes (`flask db migrate`) and applied incrementally (`flask db upgrade`). The standard architecture separates the two: `db.create_all()` for in-memory SQLite in tests, Alembic migrations for all persistent environments.

---

## How It Connects

Flask-SQLAlchemy's session scoping relies on Flask's application context — the session is registered and removed as the context is pushed and popped, making context understanding essential for using the session correctly outside requests.

[[flask-context|Flask Application and Request Context]]

Flask-SQLAlchemy is a facade over SQLAlchemy's ORM — the underlying session mechanics, relationship loading, and query API are defined by SQLAlchemy Core and ORM, which the dedicated notes cover in depth.

[[sqlalchemy-core|SQLAlchemy Core]] — MISSING_NOTE

The `init_app()` initialization of Flask-SQLAlchemy is part of the extension pattern described in the extensions note — Flask-SQLAlchemy is the canonical example of a well-behaved Flask extension.

[[flask-extensions|Flask Extensions]]

---

## Common Misconceptions

Misconception 1: "`db.create_all()` keeps my schema in sync with my models."
Reality: `db.create_all()` only creates tables that do not exist yet. If you add a column to a model, rename a table, or drop a column, `db.create_all()` does nothing. Schema evolution in any environment with existing data requires migration scripts via Flask-Migrate and Alembic.

Misconception 2: "I need to explicitly commit and close my session in every view function."
Reality: Flask-SQLAlchemy's teardown hook calls `db.session.remove()` at the end of every request, which closes the session and returns the connection to the pool. You must still call `db.session.commit()` to persist your changes, but you never need to call `db.session.close()` — doing so can actually cause issues if you try to use the session again in the same request.

Misconception 3: "`db.session.query(User)` and `db.session.execute(select(User))` are interchangeable."
Reality: `db.session.query()` is the SQLAlchemy 1.x legacy query interface. `db.session.execute(select(User))` is the SQLAlchemy 2.x style. Flask-SQLAlchemy 3.x is built on SQLAlchemy 2.x, so the 2.x style is preferred. Both work in current versions, but new code should use the 2.x API.

---

## Why It Matters in Practice

Flask-SQLAlchemy is the default ORM layer for Flask applications in the same way that Django's ORM is inseparable from Django — nearly every Flask application with a persistent data store uses it. Understanding how `db.session` is scoped to the request, why `db.create_all()` is not a migration tool, and how relationships translate to SQL queries is baseline knowledge for any Flask backend developer. The N+1 query problem — where accessing a relationship on each item in a list fires one query per item — is one of the most common performance issues in Flask applications and is diagnosed by understanding how SQLAlchemy's lazy loading works.

The transition from the SQLAlchemy 1.x legacy query API (`db.session.query(User).filter_by(id=1)`) to the SQLAlchemy 2.x core expression style (`db.session.execute(select(User).where(User.id == 1))`) is a practical concern for anyone maintaining or building a Flask application today. Flask-SQLAlchemy 3.x ships with SQLAlchemy 2.x under the hood, and understanding both APIs prevents confusion when reading existing codebases or Flask tutorials written before 2023.

---

## Interview Angle

Common question forms:
- "How does Flask-SQLAlchemy manage database sessions?"
- "What is the difference between `db.create_all()` and running migrations?"
- "How do you use Flask-SQLAlchemy with the application factory pattern?"

Answer frame:
A strong answer explains `scoped_session` and the teardown hook — sessions are scoped to the application context, created on first access within a request, and removed automatically at context teardown. The migration answer distinguishes `create_all()` (idempotent table creation, no schema diffing) from Alembic migrations (schema diffing, versioned upgrade/downgrade scripts). The factory pattern answer explains `db = SQLAlchemy()` at module level and `db.init_app(app)` inside the factory, and why direct `SQLAlchemy(app)` initialization prevents multiple app instances.

---

## Related Notes

- [[flask-extensions|Flask Extensions]]
- [[flask-context|Flask Application and Request Context]]
- [[flask-application-factory|Flask Application Factory Pattern]]
- [[sqlalchemy-core|SQLAlchemy Core]] — MISSING_NOTE
- [[flask-testing|Testing Flask Apps]]
