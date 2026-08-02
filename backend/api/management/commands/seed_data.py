import csv
import os

from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from api.models import Route, Bus, BusStop, Driver, GPSLog


class Command(BaseCommand):
    help = (
        "Seed the database with the real Thaliparamba-Cherupuzha route (38 stops), "
        "a small bus fleet, and a driver login for TrackWay."
    )

    def handle(self, *args, **options):
        self.stdout.write("Seeding TrackWay database...")

        # 1. Create Driver User
        driver_user, created = User.objects.get_or_create(username="driver1")
        if created:
            driver_user.set_password("driver123")
            driver_user.first_name = "John"
            driver_user.last_name = "Doe"
            driver_user.save()
            self.stdout.write("Created user: driver1 (password: driver123)")

        # 2. Get or Create the Real Route
        # 45.1 km matches the road-distance total baked into
        # ml_models/stop_road_distances.json (used by the ETA engine).
        route1, _ = Route.objects.get_or_create(
            route_name="Thaliparamba-Cherupuzha",
            defaults={
                "start_location": "Thaliparamba",
                "end_location": "Cherupuzha",
                "total_distance": 45.1,
            }
        )
        if route1.total_distance != 45.1:
            route1.total_distance = 45.1
            route1.save()

        # 3. Seed the real 38 bus stops from the same bus_stops.csv the LSTM
        # model and ETA engine use, so the route shown in the app always
        # matches what the ETA/direction logic is actually calculating
        # against. (The old version of this command hardcoded 3 fake stops
        # with different coordinates than the rest of the system.)
        ml_models_dir = os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
            "ml_models",
        )
        stops_csv_path = os.path.join(ml_models_dir, "bus_stops.csv")

        created_stops = 0
        if os.path.exists(stops_csv_path):
            with open(stops_csv_path, newline="") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    _, was_created = BusStop.objects.get_or_create(
                        route=route1,
                        stop_order=int(row["stop_number"]),
                        defaults={
                            "stop_name": row["stop_name"],
                            "latitude": float(row["latitude"]),
                            "longitude": float(row["longitude"]),
                        }
                    )
                    if was_created:
                        created_stops += 1
            total_stops = BusStop.objects.filter(route=route1).count()
            self.stdout.write(f"Seeded {created_stops} new bus stops ({total_stops} total on route).")
        else:
            self.stdout.write(self.style.WARNING(
                f"bus_stops.csv not found at {stops_csv_path}; no stops were seeded. "
                "The route will have no BusStop rows until this is fixed."
            ))

        # 4. Create the fleet buses that run this route
        buses_data = [
            {"bus_name": "Nayana", "bus_number": "KL 59 N 4005", "capacity": 52},
            {"bus_name": "Holy Angel", "bus_number": "KL 59 M 6555", "capacity": 48},
            {"bus_name": "Big Show", "bus_number": "KL 59 Z 8499", "capacity": 55},
        ]

        buses = []
        for b in buses_data:
            bus, _ = Bus.objects.get_or_create(
                bus_number=b["bus_number"],
                defaults={
                    "bus_name": b["bus_name"],
                    "capacity": b["capacity"],
                    "route": route1,
                    "status": "Active",
                }
            )
            buses.append(bus)

        # 5. Assign the driver to the first bus
        driver, _ = Driver.objects.get_or_create(
            user=driver_user,
            defaults={
                "phone": "+919876543210",
                "assigned_bus": buses[0],
            }
        )
        if driver.assigned_bus != buses[0]:
            driver.assigned_bus = buses[0]
            driver.save()

        # 6. Create an initial GPS log at the route's starting stop, so a
        # freshly-seeded bus has *some* live position before a real driver
        # session or the run_demo simulator starts broadcasting.
        first_stop = BusStop.objects.filter(route=route1, stop_order=1).first()
        if first_stop:
            GPSLog.objects.get_or_create(
                bus=buses[0],
                latitude=first_stop.latitude,
                longitude=first_stop.longitude,
                speed=0.0,
            )

        self.stdout.write(self.style.SUCCESS(
            "Successfully seeded TrackWay database with the real 38-stop route!"
        ))
