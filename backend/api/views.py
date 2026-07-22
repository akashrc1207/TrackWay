from rest_framework.response import Response
from rest_framework.decorators import api_view

from .models import Route, Bus, Driver
from .serializers import RouteSerializer, BusSerializer, DriverSerializer


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