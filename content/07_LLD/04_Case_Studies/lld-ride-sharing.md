---
title: 05 - LLD Ride Sharing App
description: A low-level design case study for a ride-sharing application, modeling riders, drivers, trip matching, fare calculation, and real-time status tracking using Observer, Strategy, and Repository patterns.
tags: [lld, case-study, ride-sharing, uber, observer, strategy, layer-7]
status: draft
difficulty: advanced
layer: 7
domain: lld
created: 2026-05-18
---

# LLD: Ride Sharing App

> Design a ride-sharing system that matches riders with nearby drivers, calculates fares dynamically, tracks trip status in real time, and supports different vehicle and ride types.

---

## Quick Reference

**Requirements:**
- Riders request rides with pickup and dropoff locations
- Match riders with nearest available drivers
- Real-time trip status: requested -> matched -> in_progress -> completed
- Dynamic fare calculation (distance-based, surge pricing, flat rate)
- Support multiple ride types (economy, premium, XL)
- Driver and rider ratings after trip completion

**Key patterns used:**
- **Strategy** for fare calculation and driver matching
- **Observer** for real-time trip status updates
- **Repository** for driver/rider/trip data access
- **State** for trip lifecycle management

---

## Class Design

```python
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Protocol, Callable
from uuid import uuid4
import math


# --- Location ---
@dataclass(frozen=True)
class Location:
    lat: float
    lng: float

    def distance_to(self, other: "Location") -> float:
        """Haversine distance in km (simplified)."""
        dlat = math.radians(other.lat - self.lat)
        dlng = math.radians(other.lng - self.lng)
        a = (math.sin(dlat/2)**2 +
             math.cos(math.radians(self.lat)) *
             math.cos(math.radians(other.lat)) *
             math.sin(dlng/2)**2)
        return 6371 * 2 * math.asin(math.sqrt(a))


# --- Enums ---
class TripStatus(Enum):
    REQUESTED = "requested"
    MATCHED = "matched"
    DRIVER_ARRIVING = "driver_arriving"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class RideType(Enum):
    ECONOMY = "economy"
    PREMIUM = "premium"
    XL = "xl"


class DriverStatus(Enum):
    AVAILABLE = "available"
    BUSY = "busy"
    OFFLINE = "offline"


# --- Domain Models ---
@dataclass
class Driver:
    id: str
    name: str
    vehicle_type: RideType
    location: Location
    status: DriverStatus = DriverStatus.AVAILABLE
    rating: float = 5.0
    total_ratings: int = 0

    def update_rating(self, new_rating: float) -> None:
        total = self.rating * self.total_ratings + new_rating
        self.total_ratings += 1
        self.rating = total / self.total_ratings


@dataclass
class Rider:
    id: str
    name: str
    location: Location
    rating: float = 5.0


@dataclass
class Trip:
    id: str
    rider: Rider
    pickup: Location
    dropoff: Location
    ride_type: RideType
    status: TripStatus = TripStatus.REQUESTED
    driver: Driver | None = None
    fare: float = 0.0
    distance_km: float = 0.0
    created_at: datetime = field(default_factory=datetime.now)
    completed_at: datetime | None = None


# --- Fare Strategy ---
class FareStrategy(Protocol):
    def calculate(self, distance_km: float, ride_type: RideType) -> float: ...

class StandardFare:
    BASE = {"economy": 2.50, "premium": 5.00, "xl": 7.00}
    PER_KM = {"economy": 1.20, "premium": 2.50, "xl": 3.00}

    def calculate(self, distance_km: float, ride_type: RideType) -> float:
        base = self.BASE[ride_type.value]
        per_km = self.PER_KM[ride_type.value]
        return round(base + distance_km * per_km, 2)

class SurgeFare:
    def __init__(self, base_strategy: FareStrategy, multiplier: float):
        self._base = base_strategy
        self._multiplier = multiplier

    def calculate(self, distance_km: float, ride_type: RideType) -> float:
        base_fare = self._base.calculate(distance_km, ride_type)
        return round(base_fare * self._multiplier, 2)


# --- Matching Strategy ---
class MatchingStrategy(Protocol):
    def find_driver(self, drivers: list[Driver], pickup: Location,
                    ride_type: RideType) -> Driver | None: ...

class NearestDriverStrategy:
    def __init__(self, max_distance_km: float = 10.0):
        self._max = max_distance_km

    def find_driver(self, drivers: list[Driver], pickup: Location,
                    ride_type: RideType) -> Driver | None:
        available = [
            d for d in drivers
            if d.status == DriverStatus.AVAILABLE
            and d.vehicle_type == ride_type
            and d.location.distance_to(pickup) <= self._max
        ]
        if not available:
            return None
        return min(available, key=lambda d: d.location.distance_to(pickup))

class HighestRatedStrategy:
    def find_driver(self, drivers: list[Driver], pickup: Location,
                    ride_type: RideType) -> Driver | None:
        available = [
            d for d in drivers
            if d.status == DriverStatus.AVAILABLE and d.vehicle_type == ride_type
        ]
        if not available:
            return None
        return max(available, key=lambda d: d.rating)


# --- Trip Service ---
class RideService:
    def __init__(self, drivers: list[Driver], matcher: MatchingStrategy,
                 fare_calc: FareStrategy):
        self._drivers = drivers
        self._matcher = matcher
        self._fare = fare_calc
        self._trips: dict[str, Trip] = {}
        self._listeners: list[Callable[[Trip, TripStatus], None]] = []

    def on_status_change(self, callback: Callable[[Trip, TripStatus], None]) -> None:
        self._listeners.append(callback)

    def _notify(self, trip: Trip, new_status: TripStatus) -> None:
        for listener in self._listeners:
            listener(trip, new_status)

    def request_ride(self, rider: Rider, pickup: Location,
                     dropoff: Location, ride_type: RideType) -> Trip:
        trip = Trip(
            id=str(uuid4())[:8],
            rider=rider,
            pickup=pickup,
            dropoff=dropoff,
            ride_type=ride_type,
            distance_km=pickup.distance_to(dropoff),
        )
        self._trips[trip.id] = trip
        self._notify(trip, TripStatus.REQUESTED)

        # Try to match immediately
        driver = self._matcher.find_driver(self._drivers, pickup, ride_type)
        if driver:
            trip.driver = driver
            trip.status = TripStatus.MATCHED
            driver.status = DriverStatus.BUSY
            trip.fare = self._fare.calculate(trip.distance_km, ride_type)
            self._notify(trip, TripStatus.MATCHED)

        return trip

    def start_trip(self, trip_id: str) -> None:
        trip = self._trips[trip_id]
        if trip.status != TripStatus.MATCHED:
            raise ValueError(f"Cannot start trip in {trip.status} state")
        trip.status = TripStatus.IN_PROGRESS
        self._notify(trip, TripStatus.IN_PROGRESS)

    def complete_trip(self, trip_id: str) -> float:
        trip = self._trips[trip_id]
        trip.status = TripStatus.COMPLETED
        trip.completed_at = datetime.now()
        if trip.driver:
            trip.driver.status = DriverStatus.AVAILABLE
        self._notify(trip, TripStatus.COMPLETED)
        return trip.fare

    def cancel_trip(self, trip_id: str) -> None:
        trip = self._trips[trip_id]
        trip.status = TripStatus.CANCELLED
        if trip.driver:
            trip.driver.status = DriverStatus.AVAILABLE
        self._notify(trip, TripStatus.CANCELLED)


# --- Usage ---
drivers = [
    Driver("d1", "Alice Driver", RideType.ECONOMY, Location(40.7128, -74.0060)),
    Driver("d2", "Bob Driver", RideType.PREMIUM, Location(40.7200, -74.0100)),
    Driver("d3", "Charlie Driver", RideType.ECONOMY, Location(40.7300, -74.0200)),
]

service = RideService(
    drivers=drivers,
    matcher=NearestDriverStrategy(max_distance_km=15),
    fare_calc=StandardFare(),
)

# Event listener
service.on_status_change(
    lambda trip, status: print(f"[{status.value}] Trip {trip.id}: "
                               f"{trip.rider.name} -> {trip.driver.name if trip.driver else 'unmatched'}")
)

rider = Rider("r1", "Dave Rider", Location(40.7150, -74.0080))
trip = service.request_ride(
    rider,
    pickup=Location(40.7150, -74.0080),
    dropoff=Location(40.7580, -73.9855),
    ride_type=RideType.ECONOMY,
)

print(f"Distance: {trip.distance_km:.2f} km, Fare: ${trip.fare:.2f}")

service.start_trip(trip.id)
fare = service.complete_trip(trip.id)
print(f"Trip completed. Fare: ${fare:.2f}")
```

---

## SOLID Analysis

- **SRP**: `RideService` orchestrates. `MatchingStrategy` finds drivers. `FareStrategy` calculates fares. `Trip` manages trip state.
- **OCP**: New ride types, fare models, and matching algorithms are added without modifying `RideService`.
- **Strategy**: Both matching and fare calculation are pluggable strategies.
- **Observer**: Status change listeners decouple notifications from trip logic.
- **DIP**: `RideService` depends on `MatchingStrategy` and `FareStrategy` abstractions.

---

## Related Notes

- [[solid-principles|SOLID Principles]]
- [[strategy-pattern|Strategy Pattern]]
- [[observer-pattern|Observer Pattern]]
- [[repository-pattern|Repository Pattern]]
- [[design-patterns-overview|Design Patterns Overview]]
