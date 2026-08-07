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
from datetime import timedelta
from .services.journey_state_engine import load_road_polyline, snap_point_to_polyline
from .services.tracking_config import (
    MAX_GPS_ACCURACY_METERS, MAX_SPEED_KMH, MAX_JUMP_METERS_3SEC,
    MAX_TERMINAL_RADIUS_METERS
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
    if not active_journey:
        return Response(
            {
                "bus_id": bus_id,
                "active_journey": False,
                "journey_id": None,
                "status": "inactive",
                "message": "Bus is currently inactive",
            },
            status=status.HTTP_200_OK
        )

    recent_logs = list(GPSLog.objects.filter(bus_id=bus_id, journey=active_journey).order_by("-id")[:2])
    if not recent_logs:
        return Response(
            {
                "bus_id": bus_id,
                "active_journey": True,
                "journey_id": active_journey.id,
                "status": "stale",
                "signal_status": "stale",
                "message": "No GPS data for active journey yet",
            },
            status=status.HTTP_200_OK
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
    data["active_journey"] = True
    data["journey_id"] = active_journey.id
    data["bearing"] = bearing
    data["signal_status"] = signal_status
    data["status"] = signal_status

    # Include snapped road coordinates for visual map alignment
    polyline = load_road_polyline()
    snapped_lat, snapped_lng, _, _ = snap_point_to_polyline(gps.latitude, gps.longitude, polyline)
    data["snapped_latitude"] = snapped_lat
    data["snapped_longitude"] = snapped_lng
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
        return Response(
            {"error": "bus_id is required to start a journey."},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        bus = Bus.objects.get(id=bus_id)
    except Bus.DoesNotExist:
        return Response(
            {"error": f"Bus with ID {bus_id} does not exist."},
            status=status.HTTP_404_NOT_FOUND
        )

    # Reject if driver or bus already has an active journey running
    active_journey_exists = Journey.objects.filter(Q(bus=bus) | Q(driver=driver), is_active=True).first()
    if active_journey_exists:
        return Response(
            {"error": "An active journey is already running. Please end the current journey first."},
            status=status.HTTP_400_BAD_REQUEST
        )

    # Extract coordinates from request body with fallback to recent GPS log (<= 30s)
    lat = request.data.get("latitude")
    lng = request.data.get("longitude")

    if lat is None or lng is None:
        recent_log = GPSLog.objects.filter(bus=bus).order_by("-id").first()
        if recent_log and (timezone.now() - recent_log.timestamp).total_seconds() <= 30.0:
            lat = recent_log.latitude
            lng = recent_log.longitude
        else:
            return Response(
                {"error": "GPS location is required to verify terminal presence before starting a trip."},
                status=status.HTTP_400_BAD_REQUEST
            )

    lat = float(lat)
    lng = float(lng)

    # Server-Side Security Enforcement: Independent Terminal Proximity Verification
    stops = list(BusStop.objects.filter(route=bus.route).order_by("stop_order"))
    if not stops:
        return Response(
            {"error": "No terminal stops configured for this route."},
            status=status.HTTP_400_BAD_REQUEST
        )

    first_stop = stops[0]
    last_stop = stops[-1]

    dist_start_m = haversine_distance(lat, lng, first_stop.latitude, first_stop.longitude) * 1000.0
    dist_end_m = haversine_distance(lat, lng, last_stop.latitude, last_stop.longitude) * 1000.0

    if dist_start_m > MAX_TERMINAL_RADIUS_METERS and dist_end_m > MAX_TERMINAL_RADIUS_METERS:
        logger.warning(
            f"Backend security rejected journey start for Bus #{bus.id}: ({lat}, {lng}) "
            f"is outside terminal radius (Start: {dist_start_m:.1f}m, End: {dist_end_m:.1f}m > {MAX_TERMINAL_RADIUS_METERS}m)"
        )
        return Response(
            {
                "error": "You must be at a route terminal to start a journey.",
                "distance_start_m": round(dist_start_m),
                "distance_end_m": round(dist_end_m),
                "required_radius_m": round(MAX_TERMINAL_RADIUS_METERS),
            },
            status=status.HTTP_400_BAD_REQUEST
        )

    direction = "forward" if dist_start_m <= MAX_TERMINAL_RADIUS_METERS else "reverse"

    # Clear stale cached direction/segment state for new journey
    from django.core.cache import cache
    cache.delete(f"trackway:direction:bus_{bus.id}")
    cache.delete(f"trackway:terminus_dwell:bus_{bus.id}")
    for seq in range(1, 40):
        cache.delete(f"trackway:eta:bus_{bus.id}:stop_{seq}")

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
    data = dict(serializer.data)
    data["direction"] = direction
    data["start_terminal"] = first_stop.stop_name if direction == "forward" else last_stop.stop_name
    return Response(data, status=status.HTTP_201_CREATED)


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


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def active_journey(request):
    """
    Returns the active journey belonging ONLY to the authenticated driver (request.user).
    Guarantees zero cross-contamination across drivers.
    """
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {"has_active_journey": False, "error": "Driver profile not found"},
            status=status.HTTP_404_NOT_FOUND
        )

    journey = Journey.objects.filter(driver=driver, is_active=True).first()
    bus = driver.assigned_bus or (journey.bus if journey else None)

    if journey and bus:
        route = bus.route
        return Response({
            "has_active_journey": True,
            "journey_id": journey.id,
            "bus_id": bus.id,
            "bus_name": bus.bus_name,
            "bus_number": bus.bus_number,
            "route_id": route.id if route else None,
            "route_name": route.route_name if route else "Assigned Route",
            "start_time": journey.start_time.isoformat() if journey.start_time else None,
            "driver_id": driver.id,
            "driver_username": request.user.username,
            "is_broadcasting": True,
        }, status=status.HTTP_200_OK)

    return Response({
        "has_active_journey": False,
        "journey_id": None,
        "bus_id": None,
        "driver_id": driver.id,
        "driver_username": request.user.username,
        "is_broadcasting": False,
    }, status=status.HTTP_200_OK)


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

    active_j = Journey.objects.filter(driver=driver, is_active=True).first()
    bus = driver.assigned_bus or (active_j.bus if active_j else None)

    return Response({
        "token": token.key,
        "user_id": user.id,
        "username": user.username,
        "driver_id": driver.id,
        "has_active_journey": (active_j is not None and bus is not None),
        "bus_id": bus.id if bus else None,
        "bus_name": bus.bus_name if bus else "",
        "bus_number": bus.bus_number if bus else None,
        "route_id": bus.route.id if (bus and bus.route) else None,
        "route_name": bus.route.route_name if (bus and bus.route) else "",
        "active_journey_id": active_j.id if active_j else None,
        "start_time": active_j.start_time.isoformat() if (active_j and active_j.start_time) else None,
    })


from .services.journey_state_engine import SynchronizedJourneyEngine

@api_view(["GET"])
def get_bus_eta(request, bus_id):
    bus = get_object_or_404(Bus, id=bus_id)
    active_journey = Journey.objects.filter(bus=bus, is_active=True).order_by("-id").first()
    if not active_journey:
        return Response(
            {
                "bus_id": bus.id,
                "bus_name": bus.bus_name,
                "bus_number": bus.bus_number,
                "route_id": bus.route.id if bus.route else None,
                "route_name": bus.route.route_name if bus.route else "",
                "active_journey": False,
                "journey_id": None,
                "status": "inactive",
                "signal_status": "inactive",
                "message": "This bus is currently not running any journey.",
                "stops_eta": [],
                "travelled_polyline": [],
                "remaining_polyline": [],
                "next_stop": None,
            },
            status=status.HTTP_200_OK
        )

    latest_log = GPSLog.objects.filter(bus=bus, journey=active_journey).order_by("-id").first()
    recent_logs = list(GPSLog.objects.filter(bus=bus, journey=active_journey).order_by("-id")[:6])

    if not latest_log:
        return Response(
            {
                "bus_id": bus.id,
                "bus_name": bus.bus_name,
                "bus_number": bus.bus_number,
                "route_id": bus.route.id if bus.route else None,
                "route_name": bus.route.route_name if bus.route else "",
                "active_journey": True,
                "journey_id": active_journey.id,
                "status": "stale",
                "signal_status": "stale",
                "message": "Waiting for live GPS location signal",
                "stops_eta": [],
                "travelled_polyline": [],
                "remaining_polyline": [],
                "next_stop": None,
            },
            status=status.HTTP_200_OK
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
    state["active_journey"] = True
    state["journey_id"] = active_journey.id
    state["status"] = state.get("signal_status", "live")

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