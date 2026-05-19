---
title: 02 - LLD Library Management System
description: A low-level design case study for a library management system, modeling books, members, loans, reservations, and fines using the Repository pattern, SRP, and domain-driven class design.
tags: [lld, case-study, library, repository, oop, layer-7]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# LLD: Library Management System

> Design a library management system that handles book cataloging, member management, book lending, reservations, and overdue fine calculation.

---

## Quick Reference

**Requirements:**
- Manage a catalog of books with multiple copies per title
- Members can search, borrow, return, and reserve books
- Track loan status, due dates, and overdue fines
- Enforce borrowing limits (max books per member)
- Support different member types (standard, premium) with different limits

**Key patterns used:**
- **Repository** for data access (books, members, loans)
- **Strategy** for fine calculation (daily rate, capped, waived)
- **Observer** for notifications (due date reminders, reservation availability)
- **Factory** for creating different member types

---

## Class Design

```python
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Protocol
from uuid import uuid4


class BookStatus(Enum):
    AVAILABLE = "available"
    BORROWED = "borrowed"
    RESERVED = "reserved"
    LOST = "lost"


class MemberType(Enum):
    STANDARD = "standard"    # max 3 books, 14-day loan
    PREMIUM = "premium"      # max 10 books, 30-day loan


@dataclass
class Book:
    isbn: str
    title: str
    author: str
    copies: list["BookCopy"] = field(default_factory=list)

    def available_copies(self) -> list["BookCopy"]:
        return [c for c in self.copies if c.status == BookStatus.AVAILABLE]

    @property
    def is_available(self) -> bool:
        return len(self.available_copies()) > 0


@dataclass
class BookCopy:
    id: str
    book: Book
    status: BookStatus = BookStatus.AVAILABLE


@dataclass
class Member:
    id: str
    name: str
    email: str
    member_type: MemberType
    active_loans: list["Loan"] = field(default_factory=list)

    @property
    def max_books(self) -> int:
        return 3 if self.member_type == MemberType.STANDARD else 10

    @property
    def loan_days(self) -> int:
        return 14 if self.member_type == MemberType.STANDARD else 30

    @property
    def can_borrow(self) -> bool:
        return len(self.active_loans) < self.max_books


@dataclass
class Loan:
    id: str
    member: Member
    book_copy: BookCopy
    borrow_date: datetime
    due_date: datetime
    return_date: datetime | None = None

    @property
    def is_overdue(self) -> bool:
        check_date = self.return_date or datetime.now()
        return check_date > self.due_date

    @property
    def overdue_days(self) -> int:
        if not self.is_overdue:
            return 0
        check_date = self.return_date or datetime.now()
        return (check_date - self.due_date).days


@dataclass
class Reservation:
    id: str
    member: Member
    book: Book
    reserved_at: datetime
    fulfilled: bool = False


# --- Fine Strategy ---
class FineStrategy(Protocol):
    def calculate(self, loan: Loan) -> float: ...

class DailyFineStrategy:
    def __init__(self, rate_per_day: float = 0.50):
        self._rate = rate_per_day

    def calculate(self, loan: Loan) -> float:
        return loan.overdue_days * self._rate

class CappedFineStrategy:
    def __init__(self, rate_per_day: float = 0.50, max_fine: float = 25.0):
        self._rate = rate_per_day
        self._max = max_fine

    def calculate(self, loan: Loan) -> float:
        return min(loan.overdue_days * self._rate, self._max)


# --- Repository Protocol ---
class BookRepository(Protocol):
    def find_by_isbn(self, isbn: str) -> Book | None: ...
    def search(self, query: str) -> list[Book]: ...
    def save(self, book: Book) -> None: ...

class MemberRepository(Protocol):
    def get(self, member_id: str) -> Member | None: ...
    def save(self, member: Member) -> None: ...

class LoanRepository(Protocol):
    def save(self, loan: Loan) -> None: ...
    def find_active_by_member(self, member_id: str) -> list[Loan]: ...
    def find_active_by_copy(self, copy_id: str) -> Loan | None: ...


# --- In-Memory Repositories ---
class InMemoryBookRepository:
    def __init__(self):
        self._books: dict[str, Book] = {}

    def find_by_isbn(self, isbn: str) -> Book | None:
        return self._books.get(isbn)

    def search(self, query: str) -> list[Book]:
        q = query.lower()
        return [b for b in self._books.values()
                if q in b.title.lower() or q in b.author.lower()]

    def save(self, book: Book) -> None:
        self._books[book.isbn] = book


class InMemoryLoanRepository:
    def __init__(self):
        self._loans: dict[str, Loan] = {}

    def save(self, loan: Loan) -> None:
        self._loans[loan.id] = loan

    def find_active_by_member(self, member_id: str) -> list[Loan]:
        return [l for l in self._loans.values()
                if l.member.id == member_id and l.return_date is None]

    def find_active_by_copy(self, copy_id: str) -> Loan | None:
        return next(
            (l for l in self._loans.values()
             if l.book_copy.id == copy_id and l.return_date is None),
            None
        )


# --- Library Service ---
class LibraryService:
    def __init__(self, books: BookRepository, loans: LoanRepository,
                 fine_strategy: FineStrategy):
        self._books = books
        self._loans = loans
        self._fine_strategy = fine_strategy

    def borrow_book(self, member: Member, isbn: str) -> Loan:
        if not member.can_borrow:
            raise ValueError(f"{member.name} has reached borrowing limit ({member.max_books})")

        book = self._books.find_by_isbn(isbn)
        if not book:
            raise ValueError(f"Book {isbn} not found")

        copies = book.available_copies()
        if not copies:
            raise ValueError(f"No available copies of '{book.title}'")

        copy = copies[0]
        copy.status = BookStatus.BORROWED

        loan = Loan(
            id=str(uuid4())[:8],
            member=member,
            book_copy=copy,
            borrow_date=datetime.now(),
            due_date=datetime.now() + timedelta(days=member.loan_days),
        )
        member.active_loans.append(loan)
        self._loans.save(loan)
        return loan

    def return_book(self, loan_id: str) -> float:
        # Find the loan (simplified - would use loan repository)
        loan = None
        for l in self._loans._loans.values():
            if l.id == loan_id and l.return_date is None:
                loan = l
                break

        if not loan:
            raise ValueError(f"Active loan {loan_id} not found")

        loan.return_date = datetime.now()
        loan.book_copy.status = BookStatus.AVAILABLE
        loan.member.active_loans.remove(loan)

        fine = self._fine_strategy.calculate(loan)
        return fine

    def search_books(self, query: str) -> list[Book]:
        return self._books.search(query)


# --- Usage ---
book_repo = InMemoryBookRepository()
loan_repo = InMemoryLoanRepository()

# Add books
python_book = Book("978-0-13-468599-1", "Fluent Python", "Luciano Ramalho")
python_book.copies = [
    BookCopy(f"copy-{i}", python_book) for i in range(3)
]
book_repo.save(python_book)

# Create member
alice = Member("m-001", "Alice", "alice@lib.com", MemberType.STANDARD)

# Borrow
library = LibraryService(book_repo, loan_repo, CappedFineStrategy())
loan = library.borrow_book(alice, "978-0-13-468599-1")
print(f"Borrowed: {loan.book_copy.book.title}, Due: {loan.due_date.date()}")
print(f"Available copies: {len(python_book.available_copies())}")

# Return
fine = library.return_book(loan.id)
print(f"Fine: ${fine:.2f}")
```

---

## SOLID Analysis

- **SRP**: `LibraryService` orchestrates. `BookRepository` manages data. `FineStrategy` calculates fines. `Member` manages member state.
- **OCP**: New fine strategies and member types are added without modifying `LibraryService`.
- **LSP**: All fine strategies are interchangeable through the `FineStrategy` Protocol.
- **DIP**: `LibraryService` depends on repository and strategy abstractions, not concrete implementations.

---

## Related Notes

- [[solid-principles|SOLID Principles]]
- [[repository-pattern|Repository Pattern]]
- [[strategy-pattern|Strategy Pattern]]
- [[observer-pattern|Observer Pattern]]
- [[design-patterns-overview|Design Patterns Overview]]
