from rest_framework.response import Response
from rest_framework.decorators import api_view
from rest_framework import status
from django.shortcuts import get_object_or_404
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import permission_classes
from django.db.models import Q

from .models import Route, Bus, Driver, BusStop, GPSLog 
from .serializers import (
    RouteSerializer,
    RouteDetailSerializer,
    BusSerializer,
    BusStopSerializer,
    DriverSerializer,
    GPSLogSerializer,
)

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

@api_view(["POST"])
def gps_update(request):
    serializer = GPSLogSerializer(data=request.data)

    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST) 

@api_view(["GET"])
def latest_gps(request, bus_id):
    gps = GPSLog.objects.filter(bus_id=bus_id).order_by("-timestamp").first()

    if gps is None:
        return Response({"message": "No GPS data found"}, status=404)

    serializer = GPSLogSerializer(gps)
    return Response(serializer.data)  

@api_view(["GET"])
def latest_gps(request, bus_id):
    gps = GPSLog.objects.filter(bus_id=bus_id).order_by("-timestamp").first()

    if gps is None:
        return Response(
            {"error": "No GPS data found"},
            status=status.HTTP_404_NOT_FOUND
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
            {"error": "Driver profile not found."},
            status=status.HTTP_404_NOT_FOUND
        )

    if driver.assigned_bus is None:
        return Response(
            {"error": "No bus assigned to this driver."},
            status=status.HTTP_400_BAD_REQUEST
        )

    gps = GPSLog.objects.create(
        bus=driver.assigned_bus,
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
    return Response(serializer.data)  

@api_view(["GET"])
def search_bus(request):
    query = request.GET.get("q", "")

    buses = Bus.objects.filter(
        Q(bus_number__icontains=query) |
        Q(route__route_name__icontains=query) |
        Q(route__start_location__icontains=query) |
        Q(route__end_location__icontains=query)
    )

    serializer = BusSerializer(buses, many=True)
    return Response(serializer.data) 

@api_view(["GET"])
def search_bus(request):
    query = request.GET.get("q", "")

    buses = Bus.objects.filter(
        Q(bus_number__icontains=query) |
        Q(route__route_name__icontains=query) |
        Q(route__start_location__icontains=query) |
        Q(route__end_location__icontains=query)
    )

    serializer = BusSerializer(buses, many=True)
    return Response(serializer.data)                     