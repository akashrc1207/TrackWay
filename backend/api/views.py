from rest_framework.response import Response
from rest_framework.decorators import api_view
from rest_framework import status
import logging
from django.shortcuts import get_object_or_404
from django.db.models import Q
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from django.contrib.auth import authenticate
from rest_framework.authtoken.models import Token

from .models import Route, Bus, Driver, BusStop, GPSLog, Journey
from .serializers import (
    RouteSerializer, BusSerializer, DriverSerializer, BusStopSerializer,
    GPSLogSerializer, JourneySerializer, RouteDetailSerializer
)
from .services.eta_service import infer_direction, haversine_distance
from .services.eta_engine import ETAEngine
from .services.bearing_calculator import calculate_bearing
from .services.tracking_config import (
    MAX_GPS_ACCURACY_METERS, MAX_SPEED_KMH, MAX_JUMP_METERS_3SEC
)
from .services.telemetry import TelemetryTracker

logger = logging.getLogger("trackway.views")

@api_view(['GET'])
def route_list(request):
    routes = Route.objects.all()
    serializer = RouteSerializer(routes, many=True)
    return Response(serializer.data)

@api_view(["GET"])
def bus_list(request):
    buses = Bus.objects.all()
    serializer = BusSerializer(buses, many=True)
    return Response(serializer.data)

@api_view(["GET"])
def driver_list(request):
    drivers = Driver.objects.all()
    serializer = DriverSerializer(drivers, many=True)
    return Response(serializer.data)  

@api_view(["GET"])
def bus_stop_list(request):
    bus_stops = BusStop.objects.all()
    serializer = BusStopSerializer(bus_stops, many=True)
    return Response(serializer.data) 

@api_view(["GET"])
def gps_list(request):
    gps_logs = GPSLog.objects.all()
    serializer = GPSLogSerializer(gps_logs, many=True)
    return Response(serializer.data) 

@api_view(["GET"])
def latest_gps(request, bus_id):
    active_journey = Journey.objects.filter(bus_id=bus_id, is_active=True).order_by("-id").first()
    if active_journey:
        recent_logs = list(GPSLog.objects.filter(bus_id=bus_id, journey=active_journey).order_by("-id")[:2])
    else:
        recent_logs = list(GPSLog.objects.filter(bus_id=bus_id).order_by("-id")[:2])

    if not recent_logs:
        return Response(
            {"error": "No GPS data found"},
            status=status.HTTP_404_NOT_FOUND
        )

    gps = recent_logs[0]
    bearing = 0.0
    if len(recent_logs) >= 2:
        prev_gps = recent_logs[1]
        bearing = calculate_bearing(
            prev_gps.latitude, prev_gps.longitude,
            gps.latitude, gps.longitude
        )

    signal_status = ETAEngine.get_signal_status(gps.timestamp)
    serializer = GPSLogSerializer(gps)
    data = dict(serializer.data)
    data["bearing"] = bearing
    data["signal_status"] = signal_status
    return Response(data)

@api_view(["POST"])
@permission_classes([IsAuthenticated])
def gps_update(request):
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {"error": "Driver profile not found."},
            status=status.HTTP_404_NOT_FOUND
        )

    if driver.assigned_bus is None:
        return Response(
            {"error": "No bus assigned to this driver."},
            status=status.HTTP_400_BAD_REQUEST
        )

    lat = request.data.get("latitude")
    lng = request.data.get("longitude")
    speed = request.data.get("speed", 0.0)
    accuracy = request.data.get("accuracy", 10.0)

    if lat is None or lng is None:
        return Response({"error": "Latitude and longitude are required"}, status=status.HTTP_400_BAD_REQUEST)

    lat = float(lat)
    lng = float(lng)
    speed = float(speed)
    accuracy = float(accuracy)

    TelemetryTracker.record_gps_received()

    # 1. Accuracy Check
    if accuracy > MAX_GPS_ACCURACY_METERS:
        logger.warning(f"Rejected GPS update for Bus #{driver.assigned_bus.id}: Accuracy {accuracy}m > {MAX_GPS_ACCURACY_METERS}m")
        TelemetryTracker.record_gps_rejected("accuracy_low")
        return Response({"error": f"GPS accuracy too low ({accuracy}m)"}, status=status.HTTP_400_BAD_REQUEST)

    # 2. Distance Jump & Speed Check against previous log
    active_journey = Journey.objects.filter(driver=driver, is_active=True).first()
    prev_log = GPSLog.objects.filter(bus=driver.assigned_bus).order_by("-id").first()

    if prev_log:
        dist_km = haversine_distance(prev_log.latitude, prev_log.longitude, lat, lng)
        dist_meters = dist_km * 1000.0
        dt_sec = max(0.1, (timezone.now() - prev_log.timestamp).total_seconds())

        # If less than 2 minutes since last log and position changed within normal geographic range (<= 10km)
        if dt_sec <= 120.0 and dist_km <= 10.0:
            implied_speed_kmh = (dist_km / (dt_sec / 3600.0)) if dt_sec > 0 else 0.0

            if implied_speed_kmh > MAX_SPEED_KMH:
                logger.warning(f"Rejected GPS update for Bus #{driver.assigned_bus.id}: Implied speed {implied_speed_kmh:.1f} km/h > {MAX_SPEED_KMH} km/h")
                TelemetryTracker.record_gps_rejected("implied_speed_impossible")
                return Response({"error": f"Implied speed physically impossible ({implied_speed_kmh:.1f} km/h)"}, status=status.HTTP_400_BAD_REQUEST)

            if dt_sec <= 3.5 and dist_meters > MAX_JUMP_METERS_3SEC:
                logger.warning(f"Rejected GPS update for Bus #{driver.assigned_bus.id}: Distance jump {dist_meters:.1f}m > {MAX_JUMP_METERS_3SEC}m in {dt_sec:.1f}s")
                TelemetryTracker.record_gps_rejected("jump_impossible")
                return Response({"error": f"Distance jump physically impossible ({dist_meters:.1f}m in {dt_sec:.1f}s)"}, status=status.HTTP_400_BAD_REQUEST)

    gps = GPSLog.objects.create(
        bus=driver.assigned_bus,
        journey=active_journey,
        latitude=lat,
        longitude=lng,
        speed=speed,
    )

    logger.info(f"Accepted GPS update for Bus #{driver.assigned_bus.id}: ({lat}, {lng}), speed={speed}km/h")
    serializer = GPSLogSerializer(gps)
    return Response(serializer.data, status=status.HTTP_201_CREATED)    

@api_view(["GET"])
def route_details(request, route_id):
    route = get_object_or_404(Route, id=route_id)
    serializer = RouteDetailSerializer(route)
    data = dict(serializer.data)

    # Load dense road geometry polyline
    import os, json
    base_dir = os.path.dirname(os.path.abspath(__file__))
    polyline_file = os.path.join(base_dir, "ml_models", "road_polyline.json")
    if os.path.exists(polyline_file):
        with open(polyline_file, "r") as f:
            data["road_polyline"] = json.load(f)

    return Response(data)  

@api_view(["GET"])
def search_bus(request):
    query = request.GET.get("q", "")

    buses = Bus.objects.filter(
        Q(bus_number__icontains=query) |
        Q(bus_name__icontains=query) |
        Q(route__route_name__icontains=query) |
        Q(route__start_location__icontains=query) |
        Q(route__end_location__icontains=query)
    ).distinct()

    serializer = BusSerializer(buses, many=True)
    return Response(serializer.data) 

@api_view(["GET"])
def available_buses(request):
    """
    Returns all buses that are not currently assigned to an active journey.
    """
    active_bus_ids = Journey.objects.filter(is_active=True).values_list("bus_id", flat=True)
    available = Bus.objects.exclude(id__in=active_bus_ids)

    data = []
    for b in available:
        data.append({
            "id": b.id,
            "bus_name": b.bus_name,
            "bus_number": b.bus_number,
            "route": b.route.route_name if b.route else "Unassigned",
            "capacity": b.capacity,
            "status": b.status,
            "is_available": True,
        })
    return Response(data, status=status.HTTP_200_OK)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def start_journey(request):
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        driver = Driver.objects.create(
            user=request.user,
            phone=f"+91{request.user.id}{request.user.username[:6]}"
        )

    bus_id = request.data.get("bus_id")
    if not bus_id and driver.assigned_bus:
        bus_id = driver.assigned_bus.id

    if not bus_id:
        default_bus = Bus.objects.first()
        if default_bus:
            bus_id = default_bus.id
        else:
            return Response(
                {"error": "No bus specified and none available in system."},
                status=status.HTTP_400_BAD_REQUEST
            )

    try:
        bus = Bus.objects.get(id=bus_id)
    except Bus.DoesNotExist:
        return Response(
            {"error": f"Bus with ID {bus_id} does not exist."},
            status=status.HTTP_404_NOT_FOUND
        )

    # Ensure bus is not already assigned to another driver's active journey
    active_journey_on_bus = Journey.objects.filter(bus=bus, is_active=True).exclude(driver=driver).first()
    if active_journey_on_bus:
        return Response(
            {"error": "Bus already assigned to another active journey."},
            status=status.HTTP_400_BAD_REQUEST
        )

    # Return existing journey if already active for this driver on this bus
    existing_journey = Journey.objects.filter(driver=driver, bus=bus, is_active=True).first()
    if existing_journey:
        driver.assigned_bus = bus
        driver.save()
        serializer = JourneySerializer(existing_journey)
        return Response(serializer.data, status=status.HTTP_200_OK)

    # Close any lingering active journeys for this driver
    Journey.objects.filter(driver=driver, is_active=True).update(is_active=False, end_time=timezone.now())

    driver.assigned_bus = bus
    driver.save()

    journey = Journey.objects.create(
        bus=bus,
        driver=driver,
        is_active=True
    )

    serializer = JourneySerializer(journey)
    return Response(serializer.data, status=status.HTTP_201_CREATED)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def stop_journey(request):
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {"error": "Driver profile not found"},
            status=status.HTTP_404_NOT_FOUND
        )

    journey = Journey.objects.filter(
        driver=driver,
        is_active=True
    ).first()

    if journey:
        journey.is_active = False
        journey.end_time = timezone.now()
        journey.save()

    # Release bus lock
    driver.assigned_bus = None
    driver.save()

    if journey:
        serializer = JourneySerializer(journey)
        return Response(serializer.data, status=status.HTTP_200_OK)

    return Response(
        {"message": "No active journey found, bus released"},
        status=status.HTTP_200_OK
    )


@api_view(["POST"])
def login_driver(request):
    username = request.data.get("username")
    password = request.data.get("password")

    if not username or not password:
        return Response(
            {"error": "Please provide both username and password"},
            status=status.HTTP_400_BAD_REQUEST
        )

    user = authenticate(username=username, password=password)

    if not user:
        return Response(
            {"error": "Invalid username or password"},
            status=status.HTTP_401_UNAUTHORIZED
        )

    try:
        driver = Driver.objects.get(user=user)
    except Driver.DoesNotExist:
        return Response(
            {"error": "User is not registered as a driver"},
            status=status.HTTP_403_FORBIDDEN
        )

    token, _ = Token.objects.get_or_create(user=user)

    active_journey = Journey.objects.filter(driver=driver, is_active=True).first()

    return Response({
        "token": token.key,
        "user_id": user.id,
        "username": user.username,
        "driver_id": driver.id,
        "bus_id": driver.assigned_bus.id if driver.assigned_bus else None,
        "bus_name": driver.assigned_bus.bus_name if driver.assigned_bus else "",
        "bus_number": driver.assigned_bus.bus_number if driver.assigned_bus else None,
        "active_journey_id": active_journey.id if active_journey else None,
    })


from .services.journey_state_engine import SynchronizedJourneyEngine

@api_view(["GET"])
def get_bus_eta(request, bus_id):
    bus = get_object_or_404(Bus, id=bus_id)
    active_journey = Journey.objects.filter(bus=bus, is_active=True).order_by("-id").first()
    if active_journey:
        latest_log = GPSLog.objects.filter(bus=bus, journey=active_journey).order_by("-id").first()
        recent_logs = list(GPSLog.objects.filter(bus=bus, journey=active_journey).order_by("-id")[:6])
    else:
        latest_log = GPSLog.objects.filter(bus=bus).order_by("-id").first()
        recent_logs = list(GPSLog.objects.filter(bus=bus).order_by("-id")[:6])

    if not latest_log:
        return Response(
            {"error": "No live GPS location available for this bus"},
            status=status.HTTP_404_NOT_FOUND
        )

    gps_points = [(log.latitude, log.longitude) for log in reversed(recent_logs)]
    raw_direction = infer_direction(gps_points)
    stops = BusStop.objects.filter(route=bus.route)

    state = SynchronizedJourneyEngine.compute_synchronized_state(
        bus_id=bus.id,
        bus_name=bus.bus_name,
        bus_number=bus.bus_number,
        route_id=bus.route.id,
        route_name=bus.route.route_name,
        current_lat=latest_log.latitude,
        current_lng=latest_log.longitude,
        speed_kmh=latest_log.speed,
        timestamp=latest_log.timestamp,
        raw_direction=raw_direction,
        stops=stops,
        recent_logs=recent_logs,
    )

    return Response(state)


@api_view(["GET"])
def metrics_summary(request):
    active_journeys = Journey.objects.filter(is_active=True).count()
    active_buses = Bus.objects.filter(status="Active").count()
    summary = TelemetryTracker.get_metrics_summary(
        active_journeys_count=active_journeys,
        active_buses_count=active_buses,
    )
    return Response(summary)