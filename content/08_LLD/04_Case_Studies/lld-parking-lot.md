---
title: 01 - LLD Parking Lot System
description: A low-level design case study for a parking lot management system, applying OOP principles and design patterns to model vehicles, spots, floors, and ticketing with Python classes and clean architecture.
tags: [lld, case-study, parking-lot, oop, design-patterns, layer-7]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# LLD: Parking Lot System

> Design a parking lot management system that handles multiple floors, different vehicle types, ticket issuance, and fee calculation using object-oriented principles.

---

## Quick Reference

**Requirements:**
- Multi-floor parking lot with different spot sizes (compact, regular, large)
- Support for motorcycles, cars, and buses with size-based spot assignment
- Ticket issuance on entry, fee calculation on exit based on duration
- Track available spots per floor and per type
- Thread-safe for concurrent entry/exit

**Key patterns used:**
- **Strategy** for fee calculation (hourly, daily, flat-rate)
- **Factory** for creating the correct spot assignment
- **Singleton** for the parking lot instance (optional)
- **Observer** for notifying display boards when availability changes

---

## Requirements Analysis

A parking lot system must handle vehicle entry (assign a spot, issue a ticket), vehicle exit (calculate fee, free the spot), and real-time availability tracking. The design must accommodate different vehicle sizes, different pricing strategies, and concurrent access from multiple entry/exit gates.

The key design decisions are: how to model the relationship between vehicles and spots (a vehicle occupies a spot), how to find available spots efficiently (by floor and size), how to calculate fees flexibly (different strategies for different contexts), and how to ensure thread safety at entry/exit gates.

---

## Class Design

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Protocol
from uuid import uuid4
import threading


# --- Enums ---
class VehicleSize(Enum):
    MOTORCYCLE = 1
    COMPACT = 2
    REGULAR = 3
    LARGE = 4


class SpotSize(Enum):
    COMPACT = 1     # fits motorcycle, compact car
    REGULAR = 2     # fits motorcycle, compact, regular car
    LARGE = 3       # fits everything including buses


# --- Domain Models ---
@dataclass
class Vehicle:
    license_plate: str
    size: VehicleSize


@dataclass
class ParkingSpot:
    id: str
    floor: int
    size: SpotSize
    vehicle: Vehicle | None = None

    @property
    def is_available(self) -> bool:
        return self.vehicle is None

    def can_fit(self, vehicle: Vehicle) -> bool:
        """A vehicle fits if its size <= spot size."""
        size_map = {
            VehicleSize.MOTORCYCLE: 1,
            VehicleSize.COMPACT: 1,
            VehicleSize.REGULAR: 2,
            VehicleSize.LARGE: 3,
        }
        spot_capacity = {SpotSize.COMPACT: 1, SpotSize.REGULAR: 2, SpotSize.LARGE: 3}
        return size_map[vehicle.size] <= spot_capacity[self.size]

    def park(self, vehicle: Vehicle) -> None:
        if not self.is_available:
            raise ValueError(f"Spot {self.id} is occupied")
        if not self.can_fit(vehicle):
            raise ValueError(f"Vehicle {vehicle.license_plate} too large for spot {self.id}")
        self.vehicle = vehicle

    def unpark(self) -> Vehicle:
        if self.vehicle is None:
            raise ValueError(f"Spot {self.id} is empty")
        vehicle = self.vehicle
        self.vehicle = None
        return vehicle


@dataclass
class ParkingTicket:
    id: str
    vehicle: Vehicle
    spot: ParkingSpot
    entry_time: datetime
    exit_time: datetime | None = None

    @property
    def duration(self) -> timedelta:
        end = self.exit_time or datetime.now()
        return end - self.entry_time


# --- Strategy: Fee Calculation ---
class FeeStrategy(Protocol):
    def calculate(self, ticket: ParkingTicket) -> float: ...


class HourlyFeeStrategy:
    def __init__(self, rate_per_hour: float):
        self._rate = rate_per_hour

    def calculate(self, ticket: ParkingTicket) -> float:
        hours = ticket.duration.total_seconds() / 3600
        return max(1, round(hours)) * self._rate  # minimum 1 hour


class FlatRateFeeStrategy:
    def __init__(self, daily_rate: float):
        self._rate = daily_rate

    def calculate(self, ticket: ParkingTicket) -> float:
        days = ticket.duration.total_seconds() / 86400
        return max(1, round(days)) * self._rate


class TieredFeeStrategy:
    """First 2 hours: $5/hr, next 4 hours: $3/hr, after that: $2/hr."""
    def calculate(self, ticket: ParkingTicket) -> float:
        hours = ticket.duration.total_seconds() / 3600
        total = 0.0
        if hours <= 2:
            total = hours * 5
        elif hours <= 6:
            total = 2 * 5 + (hours - 2) * 3
        else:
            total = 2 * 5 + 4 * 3 + (hours - 6) * 2
        return round(total, 2)


# --- Parking Floor ---
class ParkingFloor:
    def __init__(self, floor_number: int, spots: list[ParkingSpot]):
        self.floor_number = floor_number
        self._spots = spots

    def find_available_spot(self, vehicle: Vehicle) -> ParkingSpot | None:
        """Find the smallest available spot that fits the vehicle."""
        available = [s for s in self._spots if s.is_available and s.can_fit(vehicle)]
        if not available:
            return None
        # Prefer smallest spot that fits (efficient use of space)
        return min(available, key=lambda s: s.size.value)

    @property
    def available_count(self) -> dict[SpotSize, int]:
        counts: dict[SpotSize, int] = {}
        for spot in self._spots:
            if spot.is_available:
                counts[spot.size] = counts.get(spot.size, 0) + 1
        return counts


# --- Parking Lot (main class) ---
class ParkingLot:
    def __init__(self, name: str, floors: list[ParkingFloor],
                 fee_strategy: FeeStrategy):
        self.name = name
        self._floors = floors
        self._fee_strategy = fee_strategy
        self._active_tickets: dict[str, ParkingTicket] = {}
        self._lock = threading.Lock()

    def enter(self, vehicle: Vehicle) -> ParkingTicket:
        """Assign a spot and issue a ticket. Thread-safe."""
        with self._lock:
            for floor in self._floors:
                spot = floor.find_available_spot(vehicle)
                if spot:
                    spot.park(vehicle)
                    ticket = ParkingTicket(
                        id=str(uuid4())[:8],
                        vehicle=vehicle,
                        spot=spot,
                        entry_time=datetime.now(),
                    )
                    self._active_tickets[ticket.id] = ticket
                    return ticket

            raise ValueError("Parking lot is full")

    def exit(self, ticket_id: str) -> float:
        """Calculate fee, free the spot. Thread-safe."""
        with self._lock:
            ticket = self._active_tickets.pop(ticket_id, None)
            if not ticket:
                raise ValueError(f"Ticket {ticket_id} not found")

            ticket.exit_time = datetime.now()
            ticket.spot.unpark()
            fee = self._fee_strategy.calculate(ticket)
            return fee

    def availability(self) -> dict[int, dict[SpotSize, int]]:
        return {
            floor.floor_number: floor.available_count
            for floor in self._floors
        }


# --- Build and use ---
def create_parking_lot() -> ParkingLot:
    floors = []
    for floor_num in range(1, 4):  # 3 floors
        spots = []
        for i in range(5):
            spots.append(ParkingSpot(f"F{floor_num}-C{i}", floor_num, SpotSize.COMPACT))
        for i in range(10):
            spots.append(ParkingSpot(f"F{floor_num}-R{i}", floor_num, SpotSize.REGULAR))
        for i in range(3):
            spots.append(ParkingSpot(f"F{floor_num}-L{i}", floor_num, SpotSize.LARGE))
        floors.append(ParkingFloor(floor_num, spots))

    return ParkingLot("Downtown Garage", floors, TieredFeeStrategy())


lot = create_parking_lot()
car = Vehicle("ABC-123", VehicleSize.REGULAR)
ticket = lot.enter(car)
print(f"Ticket: {ticket.id}, Spot: {ticket.spot.id}")
print(f"Availability: {lot.availability()}")

fee = lot.exit(ticket.id)
print(f"Fee: ${fee:.2f}")
```

---

## Design Decisions

The design uses composition extensively. The `ParkingLot` composes `ParkingFloor` objects. Each floor composes `ParkingSpot` objects. The fee calculation is a Strategy (swappable algorithm). Spot assignment uses a simple search with smallest-fit preference, which could be extracted into its own Strategy if different assignment algorithms were needed.

Thread safety is achieved with a single lock on the `ParkingLot` for entry/exit operations. For higher throughput, per-floor locks could reduce contention, but the simpler approach is sufficient for most parking lots.

---

## SOLID Analysis

- **SRP**: `ParkingSpot` manages spot state. `ParkingFloor` manages spot search. `ParkingLot` manages tickets. `FeeStrategy` calculates fees. Each class has one responsibility.
- **OCP**: New fee strategies (weekend rates, member discounts) require new classes, not modification of existing code.
- **LSP**: All fee strategies are substitutable through the `FeeStrategy` Protocol.
- **ISP**: The Protocol is focused - one method (`calculate`). No client depends on methods it does not use.
- **DIP**: `ParkingLot` depends on `FeeStrategy` Protocol, not on a concrete strategy class.

---

## Related Notes

- [[solid-principles|SOLID Principles]]
- [[strategy-pattern|Strategy Pattern]]
- [[factory-method|Factory Method Pattern]]
- [[thread-safety-basics|Thread Safety Basics]]
- [[design-patterns-overview|Design Patterns Overview]]
