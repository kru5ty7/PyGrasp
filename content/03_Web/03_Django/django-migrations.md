---
title: 08 - Django Migrations
description: "Django migrations are version-controlled schema change scripts that track model evolution, apply changes to the database, and support data transformations alongside structural changes."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django Migrations

> Django migrations are the version control system for your database schema  -  they record every structural change to your models, allow those changes to be applied consistently across development, staging, and production environments, and can be reversed if something goes wrong.

---

## Quick Reference

**Core idea:**
- `manage.py makemigrations` detects model changes and writes migration files; `manage.py migrate` applies them
- Each migration file contains `dependencies` (ordering) and `operations` (schema changes: `CreateModel`, `AddField`, `AlterField`, `RemoveField`)
- Data migrations use `RunPython` to transform data alongside schema changes within the same transaction
- `squashmigrations` collapses a sequence of migrations into one, reducing application startup time
- Migrations form a Directed Acyclic Graph (DAG); `--merge` creates a merge migration when two branches diverge

**Tricky points:**
- `makemigrations` only detects changes that Django knows about  -  custom SQL, stored procedures, and triggers are invisible to it
- Never modify a migration file that has already been applied in production  -  create a new migration instead
- `RunPython` functions receive `apps` (historical model registry) and `schema_editor`  -  use `apps.get_model()`, not the actual model class, to avoid depending on current model state
- `migrate --fake` marks a migration as applied without running it  -  useful for bringing legacy databases under migration management, dangerous if misused

---

## What It Is

A Django migration is a Python script that describes a database schema change in a way that is reproducible, reversible, and trackable by version control. Think of migrations as change records for a database  -  like a ledger for a bank account. The ledger does not store the current balance directly; it stores every transaction, and the current state is the result of replaying all transactions in order. The database schema is not stored as a static definition; it is the result of applying every migration in the correct order, starting from an empty database. This means any developer can recreate the exact production schema by running `manage.py migrate` on a fresh database.

`manage.py makemigrations` is the tool that generates these change records. It reads the current model definitions in Python, reads the last known state from the existing migration files (Django internally builds a "migration state" by replaying migrations), computes the diff, and writes a new migration file that contains the operations needed to transform the old state into the new one. The generated file is deterministic  -  the same model changes always produce the same migration operations  -  and is designed to be committed to version control alongside the code that introduced the model change. The generated migration is a proposal; reviewing it before committing is good practice, especially for complex changes like field renames.

Data migrations are migrations that transform data rather than (or in addition to) schema. They use the `RunPython` operation, which calls a Python function that receives a historical model registry (`apps`) and a `schema_editor`. The critical rule is to always use `apps.get_model('myapp', 'MyModel')` rather than importing the model class directly. The reason is subtle but important: the real model class reflects the model's current state, but inside a migration, you are operating at a historical point in the schema where the model may have had different fields. Using the historical model registry ensures that the ORM uses only the fields and relations that existed at the time this migration runs, making the migration stable even as the model continues to evolve.

---

## How It Actually Works

Django stores migration state in a database table called `django_migrations`, which records the app label and migration name for every migration that has been applied. When `manage.py migrate` runs, it reads this table, computes which migrations have not yet been applied, orders them according to their `dependencies` DAG, and applies them in sequence. Each migration runs in a transaction by default (for databases that support transactional DDL, like PostgreSQL), so a failed migration is rolled back automatically. MySQL does not support transactional DDL, which means a failed migration on MySQL may leave the schema in a partially-applied state  -  another argument for PostgreSQL in production.

Squashing migrations is important for long-lived projects. A project that has been running for years may accumulate hundreds of migration files. Each `manage.py migrate` run must load and replay all of them in memory to reconstruct the historical state, which adds startup time. `manage.py squashmigrations myapp 0001 0050` produces a single migration that contains the operations equivalent to running 0001 through 0050 in sequence, with `replaces = [('myapp', '0001_initial'), ..., ('myapp', '0050_...')]` telling Django that this squash replaces the originals. Once all environments have applied either the originals or the squash, the originals can be deleted.

```python
# A generated migration file
from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [
        ('blog', '0001_initial'),
    ]
    operations = [
        migrations.AddField(
            model_name='article',
            name='view_count',
            field=models.IntegerField(default=0),
        ),
    ]

# A data migration using RunPython
def populate_slugs(apps, schema_editor):
    Article = apps.get_model('blog', 'Article')  # historical model
    for article in Article.objects.all():
        article.slug = article.title.lower().replace(' ', '-')
        article.save()

def reverse_populate_slugs(apps, schema_editor):
    Article = apps.get_model('blog', 'Article')
    Article.objects.all().update(slug='')

class Migration(migrations.Migration):
    dependencies = [('blog', '0003_add_slug_field')]
    operations = [migrations.RunPython(populate_slugs, reverse_populate_slugs)]
```

---

## How It Connects

Migrations are generated from model definitions  -  every model field change results in a migration operation, and understanding field types and `on_delete` options is prerequisite knowledge.

[[django-orm|Django ORM]]

The project structure note explains where migration files live and why each app manages its own migrations subdirectory independently.

[[django-project-structure|Django Project Structure]]

In deployment, `manage.py migrate` is a required step before the new application code can serve traffic  -  understanding deployment pipelines requires understanding when and how migrations run.

[[django-deployment|Django Deployment]]

---

## Common Misconceptions

Misconception 1: "makemigrations and migrate are the same command."
Reality: `makemigrations` only writes Python files  -  it does not touch the database. `migrate` reads those Python files and executes the corresponding SQL against the database. A developer who runs `makemigrations` but forgets to run `migrate` has changed their model definition without changing the database schema, which will cause `OperationalError` the moment Django tries to query the missing column.

Misconception 2: "I can edit a migration file after it has been applied."
Reality: Once a migration has been applied to any environment  -  especially production  -  its content is effectively immutable. The `django_migrations` table records the migration by name; if you edit the file, the record still shows it as applied, but the database state no longer matches what the edited file would produce. Always create a new migration to make further changes.

Misconception 3: "RunPython functions should import and use the actual model class."
Reality: Inside `RunPython`, the model class's current Python definition may include fields that do not exist yet in the migration sequence, or may be missing fields that were later removed. Using `apps.get_model('myapp', 'Model')` returns the historical model state that matches the schema at the point this migration runs. This is what keeps data migrations stable across future model changes.

---

## Why It Matters in Practice

Migrations are the contract between your Python code and the database schema. A project without disciplined migration management  -  where developers modify the schema by hand in production, or reset migrations when they become inconvenient  -  loses the ability to reproduce its own schema, which is a serious operational liability. Any new developer or new environment that needs to spin up a working database must manually recreate the schema, and subtle differences between environments become the source of production-only bugs.

The discipline around data migrations  -  always using the historical model registry, always providing a reverse function, always testing migrations in CI against a snapshot of production data  -  is what makes it safe to deploy schema changes to production without downtime or data loss. Projects that treat migrations as generated boilerplate to be blindly committed end up with unmaintainable migration histories; projects that treat them as first-class code artifacts end up with safe, reproducible, reviewable schema evolution.

---

## Interview Angle

Common question forms:
- "What is the difference between makemigrations and migrate?"
- "How do you write a data migration in Django?"
- "What happens when two developers both add migrations to the same app at the same time?"

Answer frame:
A strong answer distinguishes `makemigrations` (generates Python files from model diffs) from `migrate` (applies those files to the database as SQL). It explains data migrations via `RunPython` with `apps.get_model()` for historical model access. For conflicting migrations, it describes the dependency DAG where two migration files both depend on the same parent, and explains that `manage.py makemigrations --merge` resolves this by creating a new migration with both as dependencies.

---

## Related Notes

- [[django-orm|Django ORM]]
- [[django-project-structure|Django Project Structure]]
- [[django-deployment|Django Deployment]]
- [[django-testing|Testing Django Apps]]
