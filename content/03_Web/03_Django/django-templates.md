---
title: 05 - Django Templates
description: "The Django Template Language is an intentionally constrained HTML rendering system built around template inheritance, block overrides, and context variables."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django Templates

> Django's template language is deliberately limited — it cannot run arbitrary Python — and that constraint is a deliberate security and separation-of-concerns choice that forces business logic to stay in views where it can be tested.

---

## Quick Reference

**Core idea:**
- `{{ variable }}` renders a context variable; `{{ obj.attribute }}` traverses attributes and dict keys
- `{% tag %}` executes logic: `{% if %}`, `{% for %}`, `{% block %}`, `{% extends %}`, `{% include %}`, `{% url %}`
- `{% extends 'base.html' %}` enables template inheritance; `{% block name %}` marks overridable regions
- `{% load staticfiles %}` and `{% load i18n %}` import custom template tag libraries
- Context processors inject variables (e.g., `request`, `user`, `STATIC_URL`) into every template context
- `{% include 'partial.html' %}` renders a sub-template inside the current one

**Tricky points:**
- Variable resolution order: attribute, dictionary key, list index — Python's dot notation maps to all three
- A missing variable silently renders as empty string by default; `TEMPLATE_STRING_IF_INVALID` can change this in debug
- Template inheritance is single-parent: a child template can only `{% extends %}` one base
- `{% include %}` renders the partial in the current context; `{% include 'x.html' with key=val only %}` isolates it

---

## What It Is

The Django Template Language is the presentation layer in the MVT pattern — the part whose only job is to take data provided by a view and render it into an HTML string for the browser. Think of a DTL template as a mail merge document: there are fixed structural elements (the letterhead, the salutation, the footer) and placeholder slots where variable data — the recipient's name, the order total, the list of items — will be substituted. The template has no ability to query a database, call an API, or run a conditional that changes what data exists; it can only choose how to display the data the view already fetched.

Template inheritance is the feature that makes DTL practical for real applications. A `base.html` file defines the full page structure — HTML doctype, head section, nav, footer — and marks certain regions as `{% block %}` slots. Any child template that starts with `{% extends 'base.html' %}` automatically inherits the full page structure and can override only the blocks it needs to customize. The nav and footer never need to be copy-pasted. This is the equivalent of a master page in web design, and it means that a global layout change — adding a banner, updating the nav, changing the footer — requires editing exactly one file.

Context processors are the mechanism Django uses to make certain variables universally available in every template context without requiring every view to pass them explicitly. The default context processors inject `request` (giving templates access to `request.user`, `request.session`, and `request.method`), `messages` (for the one-time flash message system), and `perms` (for template-level permission checks). Adding a custom context processor is straightforward: a function that takes a `request` and returns a dictionary, registered in `TEMPLATES[0]['OPTIONS']['context_processors']`, and its returned keys become available in every template.

---

## How It Actually Works

When a view calls `render(request, 'blog/detail.html', context)`, Django's template engine searches for the template file. It checks each directory in the `DIRS` setting first, then searches for `templates/` subdirectories inside each app listed in `INSTALLED_APPS` (in the order they are listed). The first matching file wins. This is why templates are conventionally namespaced under the app name: `templates/blog/detail.html` rather than `templates/detail.html`, preventing a template in one app from accidentally shadowing a template with the same name in another app.

The template engine compiles the template text into a `Template` object composed of nodes — `TextNode` for literal HTML, `VariableNode` for `{{ }}` expressions, and `TagNode` subclasses for `{% %}` tags. This compiled form is cached in memory after first use so subsequent renders skip the parsing step. Rendering the compiled template calls `render(context)` on the root node, which traverses the node tree and concatenates the output. Variable resolution uses a lookup chain: Django tries `obj.key` as an attribute, then as a dictionary lookup `obj['key']`, then as an integer index `obj[int(key)]`. This is why `{{ article.title }}` works for both a model instance (attribute) and a dictionary (key lookup) without any template change.

```html
{# base.html #}
<!DOCTYPE html>
<html>
<head><title>{% block title %}MySite{% endblock %}</title></head>
<body>
  <nav>…</nav>
  {% block content %}{% endblock %}
  <footer>…</footer>
</body>
</html>

{# blog/detail.html #}
{% extends 'base.html' %}
{% load static %}

{% block title %}{{ article.title }} — MySite{% endblock %}

{% block content %}
  <h1>{{ article.title }}</h1>
  <img src="{% static 'blog/images/hero.png' %}" alt="hero">
  {% for tag in article.tags.all %}
    <span class="tag">{{ tag.name }}</span>
  {% endfor %}
{% endblock %}
```

---

## How It Connects

Templates receive their data from views through the context dictionary; the view is responsible for all data fetching and business logic before rendering begins.

[[django-views|Django Views]]

The `{% url %}` tag performs the same reverse resolution as Python's `reverse()` function — understanding URL namespacing is required to use it correctly.

[[django-urls|Django URL Routing]]

Context processors inject `request.user`, meaning templates can check `{% if user.is_authenticated %}` without any view code, which connects to how Django's auth system populates `request.user`.

[[django-auth|Django Authentication]]

---

## Common Misconceptions

Misconception 1: "I can call Python functions directly in Django templates."
Reality: DTL does not support arbitrary Python expression evaluation. You cannot call `{{ my_list|sorted }}` or `{{ obj.method(arg) }}`. Method calls with arguments are not supported; only zero-argument method calls work, and even then, methods that have side effects should be avoided in templates. Logic requiring function calls belongs in the view or in a custom template filter/tag.

Misconception 2: "Jinja2 is strictly better than DTL because it is more powerful."
Reality: DTL's power restrictions are intentional. Allowing arbitrary Python in templates creates security risks (especially with user-supplied templates), makes templates harder to cache safely, and encourages moving business logic into the presentation layer. Jinja2 is the right choice when performance is critical or when template authors need more expressiveness, but it requires more discipline to avoid misuse. Django supports Jinja2 as a configurable alternative.

Misconception 3: "{% include %} and {% extends %} do the same thing."
Reality: `{% extends %}` establishes single-parent inheritance — the child fills blocks in the parent's skeleton. `{% include %}` embeds a rendered partial template inside the current one. A template can `{% extends %}` only one parent but can `{% include %}` any number of partials. They are complementary, not interchangeable.

---

## Why It Matters in Practice

The template system's constraints are productivity features in disguise. When business logic cannot live in templates, it is forced into views where it can be unit-tested without spinning up a full Django environment. Teams that follow this separation produce templates that are maintainable by front-end developers who do not know Python and views that are testable by back-end developers who do not need a browser. This clean boundary is one of the reasons Django-based projects tend to age better than frameworks that permit arbitrary code in templates.

Template inheritance also has a measurable impact on maintenance cost. In a project with thirty templates, a `{% extends 'base.html' %}` architecture means thirty templates automatically inherit every future change to the base layout. Without inheritance, those thirty templates each need to be edited individually whenever the nav changes — a reliable source of inconsistency bugs.

---

## Interview Angle

Common question forms:
- "How does template inheritance work in Django?"
- "What is a context processor and when would you write a custom one?"
- "Why does Django use its own template language instead of allowing arbitrary Python?"

Answer frame:
A strong answer explains template inheritance as `{% extends %}` + `{% block %}` — child templates fill named regions of a parent skeleton, enabling DRY layout management. It describes context processors as functions registered in `TEMPLATES` settings that inject dictionary keys into every template context, useful for site-wide data like the authenticated user or active navigation item. It articulates that DTL's Python restrictions enforce separation of presentation from logic, improving testability and security.

---

## Related Notes

- [[django-overview|Django Overview and MVT Pattern]]
- [[django-views|Django Views]]
- [[django-urls|Django URL Routing]]
- [[django-forms|Django Forms]]
- [[django-auth|Django Authentication]]
