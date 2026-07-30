import os
import sys
import json
import time
import math
from datetime import datetime
from django.core.management.base import BaseCommand
from django.utils import timezone
from api.models import Bus, Driver, Journey, GPSLog, Route, BusStop


class Command(BaseCommand):
    help = "Run perfect real-time live demo simulator for TrackWay (Thaliparamba - Cherupuzha)"

    def add_arguments(self, parser):
        parser.add_argument(
            "--bus", type=str, default="Nayana", help="Bus name to simulate"
        )
        parser.add_argument(
            "--interval", type=float, default=4.0, help="Seconds between GPS updates"
        )
        parser.add_argument(
            "--step", type=int, default=5, help="Polyline points per step"
        )
        parser.add_argument(
            "--reset", action="store_true", help="Reset old GPS logs before starting"
        )

    def handle(self, *args, **options):
        bus_name = options["bus"]
        interval = options["interval"]
        step_size = options["step"]
        should_reset = options["reset"]

        self.stdout.write(self.style.SUCCESS("=" * 60))
        self.stdout.write(
            self.style.SUCCESS(
                f" [BUS] TRACKWAY PERFECT LIVE DEMO SIMULATOR ({bus_name.upper()})"
            )
        )
        self.stdout.write(self.style.SUCCESS("=" * 60))

        # 1. Fetch or create target bus & route
        bus = Bus.objects.filter(bus_name__icontains=bus_name).first()
        if not bus:
            route = Route.objects.first()
            if not route:
                self.stdout.write(
                    self.style.ERROR("No route found. Please run seed_data first.")
                )
                return
            bus = Bus.objects.create(
                bus_name="Nayana",
                bus_number="KL 59 N 4005",
                capacity=52,
                route=route,
                status="Active",
            )

        # 2. Reset old GPS logs if requested or automatically to ensure zero stale conflicts
        if should_reset or GPSLog.objects.filter(bus=bus).count() > 500:
            deleted_count, _ = GPSLog.objects.filter(bus=bus).delete()
            self.stdout.write(
                self.style.NOTICE(
                    f"Cleaned up {deleted_count} stale GPS logs for {bus.bus_name}."
                )
            )

        # 3. Ensure Driver and Active Journey
        driver = Driver.objects.filter(assigned_bus=bus).first()
        if not driver:
            driver = Driver.objects.first()

        # Deactivate any previous dead journeys
        Journey.objects.filter(bus=bus, is_active=True).update(
            is_active=False, end_time=timezone.now()
        )

        journey = Journey.objects.create(bus=bus, driver=driver, is_active=True)
        self.stdout.write(
            self.style.SUCCESS(
                f"Active Journey Created: Session #{journey.id} for {bus.bus_name} ({bus.bus_number})"
            )
        )

        # 4. Load polyline road points
        base_dir = os.path.dirname(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        )
        polyline_path = os.path.join(base_dir, "ml_models", "road_polyline.json")

        if os.path.exists(polyline_path):
            with open(polyline_path, "r") as f:
                points = json.load(f)
            self.stdout.write(
                self.style.SUCCESS(
                    f"Loaded {len(points)} dense road polyline coordinates."
                )
            )
        else:
            stops = BusStop.objects.filter(route=bus.route).order_by("stop_order")
            points = [{"latitude": s.latitude, "longitude": s.longitude} for s in stops]
            step_size = 1

        if not points:
            self.stdout.write(
                self.style.ERROR("No coordinates available for simulation.")
            )
            return

        total_points = len(points)
        idx = 0
        direction = 1
        speed_kmh = 38.0

        self.stdout.write(
            self.style.SUCCESS(
                f"Broadcasting live GPS stream for {bus.bus_name}... Press Ctrl+C to stop.\n"
            )
        )

        try:
            while True:
                curr_point = points[idx]
                lat = float(curr_point["latitude"])
                lng = float(curr_point["longitude"])

                # Calculate progress %
                progress = ((idx + 1) / total_points) * 100.0

                # Create single clean GPS log entry
                GPSLog.objects.create(
                    bus=bus,
                    journey=journey,
                    latitude=lat,
                    longitude=lng,
                    speed=round(speed_kmh, 1),
                )

                now_str = datetime.now().strftime("%H:%M:%S")
                dir_str = (
                    "Forward (Thaliparamba -> Cherupuzha)"
                    if direction == 1
                    else "Return (Cherupuzha -> Thaliparamba)"
                )

                self.stdout.write(
                    f"[{now_str}] Bus {bus.bus_name} ({bus.bus_number}) | Lat: {lat:.5f}, Lng: {lng:.5f} | Speed: {speed_kmh:.1f} km/h | Progress: {progress:.1f}% [{dir_str}]"
                )
                sys.stdout.flush()

                # Advance index along polyline
                idx += direction * step_size

                if idx >= total_points:
                    idx = total_points - 1
                    direction = -1
                    speed_kmh = 35.0
                    self.stdout.write(
                        self.style.NOTICE(
                            "\nReached Destination (Cherupuzha Bus Stand)! Reversing direction to Thaliparamba...\n"
                        )
                    )
                elif idx < 0:
                    idx = 0
                    direction = 1
                    speed_kmh = 38.0
                    self.stdout.write(
                        self.style.NOTICE(
                            "\nReached Origin (Thaliparamba)! Reversing direction to Cherupuzha...\n"
                        )
                    )

                time.sleep(interval)

        except KeyboardInterrupt:
            journey.is_active = False
            journey.end_time = timezone.now()
            journey.save()
            self.stdout.write(self.style.SUCCESS("\nDemo simulation stopped cleanly."))
