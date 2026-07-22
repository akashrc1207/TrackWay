from rest_framework.response import Response
from rest_framework.decorators import api_view
from rest_framework import status
from django.shortcuts import get_object_or_404
from rest_framework.permissions import IsAuthenticated
from rest_framework.decorators import permission_classes

from .models import Route, Bus, Driver, BusStop, GPSLog 
from .serializers import RouteSerializer, BusSerializer, DriverSerializer, BusStopSerializer, GPSLogSerializer


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
    serializer = GPSLogSerializer(data=request.data)

    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=201)

    return Response(serializer.errors, status=400)                    