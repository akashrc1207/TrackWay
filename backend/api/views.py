from rest_framework.response import Response
from rest_framework.decorators import api_view
from rest_framework import status
from django.shortcuts import get_object_or_404
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import permission_classes
from django.db.models import Q
from django.utils import timezone

from django.contrib.auth import authenticate
from rest_framework.authtoken.models import Token
from .models import Route, Bus, Driver, BusStop, GPSLog, Journey
from .serializers import (
    RouteSerializer,
    RouteDetailSerializer,
    BusSerializer,
    BusStopSerializer,
    DriverSerializer,
    GPSLogSerializer,
    JourneySerializer,
)
from .services.eta_service import calculate_eta


@api_view(["GET"])
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
    active_journey = (
        Journey.objects.filter(bus_id=bus_id, is_active=True).order_by("-id").first()
    )
    if active_journey:
        gps = (
            GPSLog.objects.filter(bus_id=bus_id, journey=active_journey)
            .order_by("-id")
            .first()
        )
    else:
        gps = GPSLog.objects.filter(bus_id=bus_id).order_by("-id").first()

    if gps is None:
        return Response(
            {"error": "No GPS data found"}, status=status.HTTP_404_NOT_FOUND
        )

    serializer = GPSLogSerializer(gps)
    return Response(serializer.data)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def gps_update(request):
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {"error": "Driver profile not found."}, status=status.HTTP_404_NOT_FOUND
        )

    if driver.assigned_bus is None:
        return Response(
            {"error": "No bus assigned to this driver."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    active_journey = Journey.objects.filter(driver=driver, is_active=True).first()

    gps = GPSLog.objects.create(
        bus=driver.assigned_bus,
        journey=active_journey,
        latitude=request.data.get("latitude"),
        longitude=request.data.get("longitude"),
        speed=request.data.get("speed"),
    )

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
        Q(bus_number__icontains=query)
        | Q(route__route_name__icontains=query)
        | Q(route__start_location__icontains=query)
        | Q(route__end_location__icontains=query)
    )

    serializer = BusSerializer(buses, many=True)
    return Response(serializer.data)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def start_journey(request):
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        # Auto-create driver profile for user if missing
        default_bus = Bus.objects.first()
        driver = Driver.objects.create(
            user=request.user, phone="+1234567890", assigned_bus=default_bus
        )

    if driver.assigned_bus is None:
        default_bus = Bus.objects.first()
        if default_bus:
            driver.assigned_bus = default_bus
            driver.save()
        else:
            return Response(
                {"error": "No bus available in system to assign to driver"},
                status=status.HTTP_400_BAD_REQUEST,
            )

    # Return existing journey if already active
    existing_journey = Journey.objects.filter(driver=driver, is_active=True).first()

    if existing_journey:
        serializer = JourneySerializer(existing_journey)
        return Response(serializer.data, status=status.HTTP_200_OK)

    journey = Journey.objects.create(bus=driver.assigned_bus, driver=driver)

    serializer = JourneySerializer(journey)
    return Response(serializer.data, status=status.HTTP_201_CREATED)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def stop_journey(request):
    try:
        driver = Driver.objects.get(user=request.user)
    except Driver.DoesNotExist:
        return Response(
            {"error": "Driver profile not found"}, status=status.HTTP_404_NOT_FOUND
        )

    journey = Journey.objects.filter(driver=driver, is_active=True).first()

    if not journey:
        return Response(
            {"message": "No active journey found, session stopped"},
            status=status.HTTP_200_OK,
        )

    journey.is_active = False
    journey.end_time = timezone.now()
    journey.save()

    serializer = JourneySerializer(journey)
    return Response(serializer.data, status=status.HTTP_200_OK)


@api_view(["POST"])
def login_driver(request):
    username = request.data.get("username")
    password = request.data.get("password")

    if not username or not password:
        return Response(
            {"error": "Please provide both username and password"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    user = authenticate(username=username, password=password)

    if not user:
        return Response(
            {"error": "Invalid username or password"},
            status=status.HTTP_401_UNAUTHORIZED,
        )

    try:
        driver = Driver.objects.get(user=user)
    except Driver.DoesNotExist:
        return Response(
            {"error": "User is not registered as a driver"},
            status=status.HTTP_403_FORBIDDEN,
        )

    token, _ = Token.objects.get_or_create(user=user)

    active_journey = Journey.objects.filter(driver=driver, is_active=True).first()

    return Response(
        {
            "token": token.key,
            "user_id": user.id,
            "username": user.username,
            "driver_id": driver.id,
            "bus_id": driver.assigned_bus.id if driver.assigned_bus else None,
            "bus_name": driver.assigned_bus.bus_name if driver.assigned_bus else "",
            "bus_number": (
                driver.assigned_bus.bus_number if driver.assigned_bus else None
            ),
            "active_journey_id": active_journey.id if active_journey else None,
        }
    )


@api_view(["GET"])
def get_bus_eta(request, bus_id):
    bus = get_object_or_404(Bus, id=bus_id)
    active_journey = (
        Journey.objects.filter(bus=bus, is_active=True).order_by("-id").first()
    )
    if active_journey:
        latest_log = (
            GPSLog.objects.filter(bus=bus, journey=active_journey)
            .order_by("-id")
            .first()
        )
    else:
        latest_log = GPSLog.objects.filter(bus=bus).order_by("-id").first()

    if not latest_log:
        return Response(
            {"error": "No live GPS location available for this bus"},
            status=status.HTTP_404_NOT_FOUND,
        )

    stops = BusStop.objects.filter(route=bus.route).order_by("stop_order")
    eta_results = []

    for stop in stops:
        eta_info = calculate_eta(
            current_lat=latest_log.latitude,
            current_lng=latest_log.longitude,
            current_speed_kmh=latest_log.speed,
            target_lat=stop.latitude,
            target_lng=stop.longitude,
            target_stop_order=stop.stop_order,
        )
        eta_results.append(
            {
                "stop_id": stop.id,
                "stop_name": stop.stop_name,
                "stop_order": stop.stop_order,
                "latitude": stop.latitude,
                "longitude": stop.longitude,
                **eta_info,
            }
        )

    return Response(
        {
            "bus_id": bus.id,
            "bus_name": bus.bus_name,
            "bus_number": bus.bus_number,
            "route_id": bus.route.id,
            "route_name": bus.route.route_name,
            "latest_position": {
                "latitude": latest_log.latitude,
                "longitude": latest_log.longitude,
                "speed": latest_log.speed,
                "timestamp": latest_log.timestamp,
            },
            "stops_eta": eta_results,
        }
    )
