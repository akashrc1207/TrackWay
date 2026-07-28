from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from api.models import Route, Bus, BusStop, Driver, GPSLog, Journey

class Command(BaseCommand):
    help = "Seed database with realistic routes, bus stops, buses, drivers, and initial GPS logs for TrackWay"

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

        # 2. Get or Create Real Route
        route1, _ = Route.objects.get_or_create(
            route_name="Thaliparamba-Cherupuzha",
            defaults={
                "start_location": "Thaliparamba",
                "end_location": "Cherupuzha",
                "total_distance": 42.0,
            }
        )

        # 3. Get or Create Real Bus Stops
        stops_data = [
            {"stop_name": "Oduvallithattu Bus Stop", "latitude": 12.1150, "longitude": 75.4500, "stop_order": 1},
            {"stop_name": "Karuvanchal Bus Stop", "latitude": 12.1800, "longitude": 75.4800, "stop_order": 2},
            {"stop_name": "Alakode Bus Stop", "latitude": 12.2300, "longitude": 75.5200, "stop_order": 3},
        ]

        for s in stops_data:
            BusStop.objects.get_or_create(
                route=route1,
                stop_name=s["stop_name"],
                defaults={
                    "latitude": s["latitude"],
                    "longitude": s["longitude"],
                    "stop_order": s["stop_order"],
                }
            )

        # 4. Get or Create Real Bus
        bus1, _ = Bus.objects.get_or_create(
            bus_number="KL59J1234",
            defaults={
                "capacity": 50,
                "route": route1,
                "status": "Active",
            }
        )

        # 5. Create/Assign Driver Profile
        driver, _ = Driver.objects.get_or_create(
            user=driver_user,
            defaults={
                "phone": "+919876543210",
                "assigned_bus": bus1,
            }
        )
        if driver.assigned_bus != bus1:
            driver.assigned_bus = bus1
            driver.save()

        # 6. Create Initial GPS Log
        GPSLog.objects.get_or_create(
            bus=bus1,
            latitude=12.1155,
            longitude=75.4510,
            speed=30.0,
        )

        self.stdout.write(self.style.SUCCESS("Successfully updated TrackWay seed data!"))
